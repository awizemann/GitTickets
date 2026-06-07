import Foundation

/// Persistent storage for the OAuth access token obtained via Device Flow.
///
/// Backed by Keychain via ``Keychain``. The default service is namespaced by the host
/// `Bundle.main.bundleIdentifier` so two GitTickets-using apps on the same device get
/// distinct stored tokens — without that namespacing, on macOS (where same-team apps share
/// a Keychain) the two apps would read each other's tokens.
///
/// Synchronization is disabled at the underlying Keychain layer (`kSecAttrSynchronizable =
/// false`), so the token does NOT replicate via iCloud Keychain to the user's other devices.
/// Each install completes its own Device Flow once.
struct TokenStore {

    /// Base service prefix; the host bundle identifier is appended unless the caller
    /// provides an explicit `service`.
    static let defaultServicePrefix = "com.gittickets.device-flow-token"

    /// Default Keychain account within the service.
    static let defaultAccount = "access-token"

    let service: String
    let account: String
    let accessGroup: String?

    init(
        service: String? = nil,
        account: String = TokenStore.defaultAccount,
        accessGroup: String? = nil,
        hostBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown"
    ) {
        self.service = service ?? "\(TokenStore.defaultServicePrefix).\(hostBundleIdentifier)"
        self.account = account
        self.accessGroup = accessGroup
    }

    /// Returns the stored token, or `nil` if no Device Flow has completed yet.
    func read() throws -> String? {
        guard let data = try Keychain.read(service: service, account: account, accessGroup: accessGroup),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Stores the token, replacing any previous value.
    func write(_ token: String) throws {
        try Keychain.write(service: service, account: account, data: Data(token.utf8), accessGroup: accessGroup)
    }

    /// Erases the stored token. Used on sign-out and on terminal auth errors (401 from the
    /// Issues API typically means the token was revoked server-side).
    func delete() throws {
        try Keychain.delete(service: service, account: account, accessGroup: accessGroup)
    }
}
