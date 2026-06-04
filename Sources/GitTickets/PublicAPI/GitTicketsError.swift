import Foundation

/// Errors thrown by the GitTickets SDK.
public enum GitTicketsError: Error, Sendable {

    /// ``GitTickets/configure(_:)`` has not been called, or the SDK is in its
    /// skeleton state.
    case notConfigured

    /// The relay could not be reached. The underlying transport error is
    /// included (e.g. `URLError.notConnectedToInternet`).
    case relayUnreachable(underlying: any Error)

    /// The relay returned a non-2xx status.
    case relayRejected(statusCode: Int, message: String?)

    /// The relay's response signature did not match. Indicates either a shared
    /// secret mismatch or a MITM attempt.
    case signatureMismatch

    /// Rate-limited by the relay or by GitHub. `retryAfter` reflects the
    /// `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?)

    /// The user denied the Device Flow authorization request.
    case deviceFlowDenied

    /// The Device Flow user code expired before the user completed authorization.
    case deviceFlowExpired

    /// Transient — Device Flow polling is in progress. Callers using the
    /// `DeviceFlowCoordinator` directly should keep polling.
    case deviceFlowPending

    /// Attachment exceeds the configured byte limit (default 5 MB).
    case attachmentTooLarge(byteLimit: Int)

    /// Caller attempted to attach an image while configured for `.deviceFlow`.
    /// GitHub has no public attachment upload API and Device Flow mode has no
    /// relay-side storage. Strip attachments from the report before retrying.
    case attachmentNotSupportedInDeviceFlow

    /// Payload failed validation (missing title, body too short, etc.).
    case payloadInvalid(reason: String)

    /// The Keychain operation failed with the given status code.
    case keychain(OSStatus)
}

extension GitTicketsError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notConfigured:
            return "GitTickets is not configured. Call GitTickets.configure(_:) at app launch."
        case .relayUnreachable(let underlying):
            return "Relay unreachable: \(underlying)"
        case .relayRejected(let statusCode, let message):
            return "Relay rejected submission (\(statusCode))\(message.map { ": \($0)" } ?? "")"
        case .signatureMismatch:
            return "Relay response signature did not match. Check the shared secret matches the relay's GITTICKETS_SHARED_SECRET."
        case .rateLimited(let retryAfter):
            return "Rate-limited.\(retryAfter.map { " Retry after \($0)s." } ?? "")"
        case .deviceFlowDenied:
            return "Device Flow authorization was denied by the user."
        case .deviceFlowExpired:
            return "Device Flow user code expired before authorization completed."
        case .deviceFlowPending:
            return "Device Flow authorization is still pending."
        case .attachmentTooLarge(let byteLimit):
            return "Attachment exceeds the \(byteLimit)-byte limit."
        case .attachmentNotSupportedInDeviceFlow:
            return "Image attachments are not supported when using AuthMode.deviceFlow."
        case .payloadInvalid(let reason):
            return "Payload invalid: \(reason)"
        case .keychain(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
