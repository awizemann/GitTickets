import Foundation

/// Outcome of a single HTTP exchange.
struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    /// Case-insensitive header lookup.
    func header(_ name: String) -> String? {
        let target = name.lowercased()
        for (key, value) in headers where key.lowercased() == target {
            return value
        }
        return nil
    }
}

/// Thin URLSession wrapper used by the relay client and the GitHub API
/// client. Adds:
///
/// - Per-request `User-Agent` header from ``UserAgent``.
/// - Bounded retries on 5xx responses for all methods.
/// - Bounded retries on transport errors for **safe** (idempotent) methods
///   only — POST/PUT/PATCH/DELETE are NOT retried on transport errors so
///   that a connection drop after the server processed the request doesn't
///   produce a duplicate side effect.
/// - `Retry-After`-aware backoff on 5xx responses; exponential backoff with
///   jitter as the fallback. 429 responses are surfaced to the caller (the
///   relay client maps them to ``GitTicketsError/rateLimited(retryAfter:)``).
///
/// Concurrency model: instances are `Sendable` and stateless beyond the
/// configured `URLSession`.
struct HTTPClient: Sendable {

    /// Configuration knobs.
    struct Configuration: Sendable {
        var maxAttempts: Int
        var baseBackoff: TimeInterval
        var maxBackoff: TimeInterval
        var jitter: Bool

        public static let `default` = Configuration(
            maxAttempts: 3,
            baseBackoff: 0.5,
            maxBackoff: 30,
            jitter: true
        )

        public init(
            maxAttempts: Int,
            baseBackoff: TimeInterval,
            maxBackoff: TimeInterval,
            jitter: Bool = true
        ) {
            // Guard against maxAttempts == 0, which would skip the request
            // loop entirely and throw URLError(.unknown) with no actual
            // transport ever firing.
            self.maxAttempts = max(1, maxAttempts)
            self.baseBackoff = baseBackoff
            self.maxBackoff = maxBackoff
            self.jitter = jitter
        }
    }

    let session: URLSession
    let configuration: Configuration
    let userAgent: String

    init(
        session: URLSession = .shared,
        configuration: Configuration = .default,
        userAgent: String = UserAgent.string()
    ) {
        self.session = session
        self.configuration = configuration
        self.userAgent = userAgent
    }

    /// Sends a request with bounded retry. See type-level docs for which
    /// methods/error classes are retried.
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await sendRetrying { _ in request }
    }

    /// Sends a request with bounded retry. The `buildRequest` closure runs
    /// before every attempt — useful for signed requests so each retry can
    /// be re-signed with a fresh timestamp (the relay's replay window is
    /// only ~5 minutes, and reusing a stale signature across retries that
    /// straddle that window turns transient 5xx into permanent 401).
    func sendRetrying(buildRequest: (Int) async throws -> URLRequest) async throws -> HTTPResponse {
        var attempt = 0
        var lastError: (any Error)?
        while attempt < configuration.maxAttempts {
            let request = try await buildRequest(attempt)
            let isIdempotent = Self.isIdempotent(request)
            do {
                let stamped = stamp(request)
                let (data, response) = try await session.data(for: stamped)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                let headers = http.allHeaderFields.reduce(into: [String: String]()) { dict, pair in
                    if let key = pair.key as? String, let value = pair.value as? String {
                        dict[key] = value
                    }
                }
                let envelope = HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
                if (500...599).contains(http.statusCode), attempt + 1 < configuration.maxAttempts {
                    let delay = retryDelay(for: envelope, attempt: attempt)
                    try await Task.sleep(nanoseconds: nanoseconds(from: delay))
                    attempt += 1
                    continue
                }
                return envelope
            } catch {
                lastError = error
                // Do not retry transport errors on non-idempotent methods —
                // a connection dropped after the relay created the GitHub
                // issue but before the response reached us would otherwise
                // double-file.
                guard isIdempotent else { throw error }
                if attempt + 1 >= configuration.maxAttempts { break }
                let delay = RateLimitBackoff.exponentialDelay(
                    attempt: attempt,
                    base: configuration.baseBackoff,
                    maxDelay: configuration.maxBackoff,
                    jitter: configuration.jitter
                )
                try await Task.sleep(nanoseconds: nanoseconds(from: delay))
                attempt += 1
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func stamp(_ request: URLRequest) -> URLRequest {
        var stamped = request
        if stamped.value(forHTTPHeaderField: "User-Agent") == nil {
            stamped.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        return stamped
    }

    private static let idempotentMethods: Set<String> = ["GET", "HEAD", "OPTIONS"]

    private static func isIdempotent(_ request: URLRequest) -> Bool {
        let method = (request.httpMethod ?? "GET").uppercased()
        return idempotentMethods.contains(method)
    }

    private func retryDelay(for response: HTTPResponse, attempt: Int) -> TimeInterval {
        if let raw = response.header("Retry-After"),
           let parsed = RateLimitBackoff.parseRetryAfter(raw) {
            return min(parsed, configuration.maxBackoff)
        }
        return RateLimitBackoff.exponentialDelay(
            attempt: attempt,
            base: configuration.baseBackoff,
            maxDelay: configuration.maxBackoff,
            jitter: configuration.jitter
        )
    }

    private func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        let clamped = max(0, seconds)
        return UInt64(clamped * 1_000_000_000)
    }
}
