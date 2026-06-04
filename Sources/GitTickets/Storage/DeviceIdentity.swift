import Foundation

/// Stable per-install device identifier used for per-device rate limiting and
/// Phase 2 correlation.
///
/// Backed by Keychain so it survives app reinstalls within the same Keychain
/// access group, but is NEVER an Apple-supplied tracking identifier (no IDFA,
/// no `identifierForVendor`). This is a UUID we generated locally.
///
/// On first call, generates a fresh `UUID().uuidString` and stores it. On
/// subsequent calls, returns the stored value.
struct DeviceIdentity {

    /// Default Keychain service for the production SDK identifier.
    static let defaultService = "com.gittickets.device-id"

    /// Default Keychain account within the service.
    static let defaultAccount = "device"

    let service: String
    let account: String

    init(service: String = DeviceIdentity.defaultService, account: String = DeviceIdentity.defaultAccount) {
        self.service = service
        self.account = account
    }

    /// Returns the existing stored identifier, or generates and stores one.
    func currentOrGenerate() throws -> String {
        if let data = try Keychain.read(service: service, account: account),
           let stored = String(data: data, encoding: .utf8),
           !stored.isEmpty {
            return stored
        }
        let fresh = UUID().uuidString
        try Keychain.write(service: service, account: account, data: Data(fresh.utf8))
        return fresh
    }

    /// Returns the existing stored identifier, or `nil` without generating one.
    func current() throws -> String? {
        guard let data = try Keychain.read(service: service, account: account),
              let stored = String(data: data, encoding: .utf8),
              !stored.isEmpty
        else { return nil }
        return stored
    }

    /// Erases the stored identifier. Mainly for tests; production should
    /// effectively never call this (would orphan all past submissions).
    func reset() throws {
        try Keychain.delete(service: service, account: account)
    }
}
