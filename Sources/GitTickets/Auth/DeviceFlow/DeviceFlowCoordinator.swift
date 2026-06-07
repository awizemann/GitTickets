import Foundation

/// Result of ``DeviceFlowCoordinator/requestAuthorization()`` — the public-facing fields the
/// form needs to show the user (the code, where to enter it) plus the opaque `deviceCode`
/// that gets handed back to ``DeviceFlowCoordinator/pollForToken(authorization:)`` and is
/// never shown to the user.
struct DeviceFlowAuthorization: Sendable, Equatable {
    let userCode: String
    let verificationURI: URL
    /// Pre-filled with the user code so `ASWebAuthenticationSession` opens straight to the
    /// confirmation screen — saves the user typing the code manually. Falls back to
    /// `verificationURI` when GitHub omits the field.
    let verificationURIComplete: URL
    let expiresAt: Date
    /// Initial polling interval. ``pollForToken(authorization:)`` may bump this on `slow_down`.
    let interval: TimeInterval
    let deviceCode: String
}

/// GitHub OAuth Device Flow state machine. Hand-rolled (no AppAuth-iOS dep) — the protocol is
/// small enough that pulling in a library just to read three fields out of two responses costs
/// more than it saves.
///
/// Wire docs:
/// <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow>
///
/// Usage shape (consumed by PR 12's form):
///
/// ```swift
/// let auth = try await coordinator.requestAuthorization()
/// // Show auth.userCode; open ASWebAuthenticationSession(url: auth.verificationURIComplete)
/// let token = try await coordinator.pollForToken(authorization: auth)
/// try TokenStore().write(token)
/// ```
///
/// Concurrency: instances are `Sendable` and stateless beyond the injected dependencies.
struct DeviceFlowCoordinator: Sendable {

    let clientID: String
    let scopes: [DeviceFlowScope]
    let http: HTTPClient
    let baseURL: URL
    let clock: @Sendable () -> Date
    /// Injected so tests can fast-forward through polling. Defaults to `Task.sleep`.
    let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Standard GitHub host. Overridden in tests so MockURLProtocol can intercept.
    static let defaultBaseURL = URL(string: "https://github.com")!

    init(
        clientID: String,
        scopes: [DeviceFlowScope],
        http: HTTPClient = HTTPClient(),
        baseURL: URL = DeviceFlowCoordinator.defaultBaseURL,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            let ns = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: ns)
        }
    ) {
        self.clientID = clientID
        self.scopes = scopes
        self.http = http
        self.baseURL = baseURL
        self.clock = clock
        self.sleep = sleep
    }

    // MARK: - Step 1: request user code

    /// `POST /login/device/code` — returns the user code, the URL the user enters it at, and
    /// the opaque `device_code` we hand back to ``pollForToken(authorization:)``.
    func requestAuthorization() async throws -> DeviceFlowAuthorization {
        let url = baseURL.appendingPathComponent("/login/device/code")
        let body = FormURLEncoded.encode([
            ("client_id", clientID),
            ("scope", scopes.map(\.rawValue).joined(separator: " ")),
        ])
        let response = try await postForm(url: url, body: body)
        try Self.validateOK(response)
        let decoded: DeviceCodeResponse
        do {
            decoded = try DeviceFlowJSON.decoder.decode(DeviceCodeResponse.self, from: response.body)
        } catch {
            throw GitTicketsError.payloadInvalid(reason: "Could not decode device-code response: \(error)")
        }
        guard let verifyURL = URL(string: decoded.verificationURI) else {
            throw GitTicketsError.payloadInvalid(reason: "Device-code response had unparseable verification_uri")
        }
        let verifyComplete = decoded.verificationURIComplete
            .flatMap(URL.init(string:))
            ?? verifyURL
        return DeviceFlowAuthorization(
            userCode: decoded.userCode,
            verificationURI: verifyURL,
            verificationURIComplete: verifyComplete,
            expiresAt: clock().addingTimeInterval(TimeInterval(decoded.expiresIn)),
            interval: TimeInterval(max(1, decoded.interval)),
            deviceCode: decoded.deviceCode
        )
    }

    // MARK: - Step 2: poll for token

    /// Polls `POST /login/oauth/access_token` at `authorization.interval` until the user
    /// completes (success) or one of the terminal errors fires:
    ///
    /// - `authorization_pending` → keep polling at the current interval.
    /// - `slow_down` → bump the interval by 5s (per RFC 8628 §3.5) and keep polling. GitHub
    ///   may also include a fresh `interval` in the response; we take the larger.
    /// - `expired_token` → throws ``GitTicketsError/deviceFlowExpired``.
    /// - `access_denied` → throws ``GitTicketsError/deviceFlowDenied``.
    /// - Any other error → throws ``GitTicketsError/payloadInvalid(reason:)``.
    ///
    /// Also enforces a wall-clock cutoff at `authorization.expiresAt` independent of the
    /// server signal: if the user just closes the browser, the server keeps returning
    /// `authorization_pending` forever and we'd otherwise spin until cancellation. Treats
    /// that as expired.
    func pollForToken(authorization: DeviceFlowAuthorization) async throws -> String {
        var interval = authorization.interval
        let url = baseURL.appendingPathComponent("/login/oauth/access_token")
        while clock() < authorization.expiresAt {
            try await sleep(interval)
            let body = FormURLEncoded.encode([
                ("client_id", clientID),
                ("device_code", authorization.deviceCode),
                ("grant_type", AccessTokenRequest.grantType),
            ])
            let response = try await postForm(url: url, body: body)
            try Self.validateOK(response)
            let decoded: AccessTokenResponse
            do {
                decoded = try DeviceFlowJSON.decoder.decode(AccessTokenResponse.self, from: response.body)
            } catch {
                throw GitTicketsError.payloadInvalid(reason: "Could not decode access-token response: \(error)")
            }
            if let token = decoded.accessToken, !token.isEmpty {
                return token
            }
            switch decoded.error {
            case "authorization_pending":
                // GitHub may rotate the interval mid-flow; respect server > our memory.
                if let server = decoded.interval { interval = max(interval, TimeInterval(server)) }
                continue
            case "slow_down":
                // RFC 8628 §3.5: bump by 5s. GitHub also tends to include a fresh `interval`;
                // take whichever is larger so we don't undercut it.
                interval = max(interval + 5, decoded.interval.map(TimeInterval.init) ?? 0)
                continue
            case "expired_token":
                throw GitTicketsError.deviceFlowExpired
            case "access_denied":
                throw GitTicketsError.deviceFlowDenied
            case let other?:
                throw GitTicketsError.payloadInvalid(reason: "Device Flow error: \(other) — \(decoded.errorDescription ?? "no description")")
            case .none:
                throw GitTicketsError.payloadInvalid(reason: "Device Flow response had neither access_token nor error")
            }
        }
        throw GitTicketsError.deviceFlowExpired
    }

    // MARK: - Helpers

    private func postForm(url: URL, body: Data) async throws -> HTTPResponse {
        do {
            return try await http.sendRetrying { _ in
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.httpBody = body
                return req
            }
        } catch {
            throw GitTicketsError.relayUnreachable(underlying: error)
        }
    }

    /// The token endpoint returns HTTP 200 even on auth errors, so we only treat 4xx/5xx as
    /// transport failures (rate-limited, GitHub maintenance, etc.). 401 here would mean the
    /// `client_id` itself is unknown — that's a developer config error, not a Device Flow state.
    private static func validateOK(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 429:
            let retryAfter = response.header("Retry-After").flatMap { RateLimitBackoff.parseRetryAfter($0) }
            throw GitTicketsError.rateLimited(retryAfter: retryAfter)
        default:
            throw GitTicketsError.relayRejected(statusCode: response.statusCode, message: nil)
        }
    }
}
