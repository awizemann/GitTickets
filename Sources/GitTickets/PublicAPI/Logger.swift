import Foundation

/// Severity levels for ``GitTicketsLogger`` messages.
public enum GitTicketsLogLevel: Sendable, Hashable {
    case debug
    case info
    case warning
    case error
}

/// Receives SDK log lines. Wire up to your app's logger of choice (OSLog,
/// swift-log, custom) by conforming a `Sendable` type and passing it via
/// ``Configuration/logger``.
public protocol GitTicketsLogger: Sendable {

    /// Called for each log line the SDK emits.
    ///
    /// - Parameters:
    ///   - level: Severity.
    ///   - message: Pre-formatted message, never contains secrets or PII.
    ///   - error: Underlying error when applicable.
    func log(level: GitTicketsLogLevel, message: String, error: (any Error)?)
}
