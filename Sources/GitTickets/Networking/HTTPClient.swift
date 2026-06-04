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
/// - Bounded retries on transport errors and 5xx responses.
/// - `Retry-After`-aware backoff on 429 responses (returned to the caller —
///   the caller decides whether to retry through us or surface as
///   ``GitTicketsError/rateLimited(retryAfter:)``).
///
/// Concurrency model: instances are `Sendable` and stateless beyond the
/// configured `URLSession`.
struct HTTPClient: Sendable {

    /// Configuration knobs.
    struct Configuration: Sendable {
        var maxAttempts: Int
        var baseBackoff: TimeInterval
        var maxBackoff: TimeInterval

        public static let `default` = Configuration(maxAttempts: 3, baseBackoff: 0.5, maxBackoff: 30)
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

    /// Sends a request with bounded retry on transport errors and 5xx
    /// responses. Returns the final response regardless of status — the
    /// caller maps non-2xx into domain errors.
    ///
    /// - Note: 429 is NOT retried automatically. The caller inspects
    ///   `Retry-After` via ``HTTPResponse/header(_:)`` to surface
    ///   ``GitTicketsError/rateLimited(retryAfter:)``.
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        var attempt = 0
        var lastError: (any Error)?
        while attempt < configuration.maxAttempts {
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
                    try await Task.sleep(nanoseconds: backoffNanos(for: attempt))
                    attempt += 1
                    continue
                }
                return envelope
            } catch {
                lastError = error
                if attempt + 1 >= configuration.maxAttempts { break }
                try await Task.sleep(nanoseconds: backoffNanos(for: attempt))
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

    private func backoffNanos(for attempt: Int) -> UInt64 {
        let seconds = RateLimitBackoff.exponentialDelay(
            attempt: attempt,
            base: configuration.baseBackoff,
            maxDelay: configuration.maxBackoff
        )
        return UInt64(seconds * 1_000_000_000)
    }
}
