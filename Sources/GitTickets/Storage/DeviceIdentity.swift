import Foundation

/// Stable per-install device identifier used for per-device rate limiting and
/// Phase 2 correlation.
///
/// Backed by Keychain. The default service is namespaced by the host
/// `Bundle.main.bundleIdentifier` so two GitTickets-using apps on the same
/// device get distinct identifiers — without that namespacing, on macOS
/// (where same-team apps share a Keychain) the two apps would read the same
/// UUID and the relay would conflate their rate-limit / 'My Issues' state.
///
/// Hosts can opt into cross-app identity by passing an `accessGroup` that
/// the apps share, plus a stable `service` (e.g. their team identifier).
///
/// This is NEVER an Apple-supplied tracking identifier (no IDFA, no
/// `identifierForVendor`). It's a UUID we generate locally.
struct DeviceIdentity {

    /// Base service prefix; the host bundle identifier is appended unless
    /// the caller provides an explicit `service`.
    static let defaultServicePrefix = "com.gittickets.device-id"

    /// Default Keychain account within the service.
    static let defaultAccount = "device"

    let service: String
    let account: String
    let accessGroup: String?

    /// Initializes the identity store.
    ///
    /// - Parameters:
    ///   - service: Keychain service identifier. Defaults to
    ///     `"com.gittickets.device-id.<host-bundle-id>"`, which scopes the
    ///     UUID to the host app even when the OS shares Keychain across
    ///     apps from the same team.
    ///   - account: Keychain account within the service. Almost always
    ///     leave at the default.
    ///   - accessGroup: Keychain access group. `nil` (default) uses the
    ///     app's default group; set to share the identity across apps in
    ///     the same App Group.
    ///   - hostBundleIdentifier: Used by the default `service`. Tests can
    ///     override; production should leave at the default.
    init(
        service: String? = nil,
        account: String = DeviceIdentity.defaultAccount,
        accessGroup: String? = nil,
        hostBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown"
    ) {
        self.service = service ?? "\(DeviceIdentity.defaultServicePrefix).\(hostBundleIdentifier)"
        self.account = account
        self.accessGroup = accessGroup
    }

    /// Returns the existing stored identifier, or generates and stores one.
    func currentOrGenerate() throws -> String {
        if let data = try Keychain.read(service: service, account: account, accessGroup: accessGroup),
           let stored = String(data: data, encoding: .utf8),
           !stored.isEmpty {
            return stored
        }
        let fresh = UUID().uuidString
        try Keychain.write(service: service, account: account, data: Data(fresh.utf8), accessGroup: accessGroup)
        return fresh
    }

    /// Returns the existing stored identifier, or `nil` without generating one.
    func current() throws -> String? {
        guard let data = try Keychain.read(service: service, account: account, accessGroup: accessGroup),
              let stored = String(data: data, encoding: .utf8),
              !stored.isEmpty
        else { return nil }
        return stored
    }

    /// Erases the stored identifier. Mainly for tests; production should
    /// effectively never call this (would orphan all past submissions).
    func reset() throws {
        try Keychain.delete(service: service, account: account, accessGroup: accessGroup)
    }
}
