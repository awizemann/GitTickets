import Foundation
import Security

/// Thin Swift wrapper around the Security framework's generic-password Keychain.
///
/// Used by ``DeviceIdentity`` for the stable per-install UUID and by the
/// Device Flow `TokenStore` for OAuth tokens.
///
/// All operations are synchronous and key off (service, account) like the
/// underlying SecItem API.
enum Keychain {

    /// Reads the value stored under (service, account), or `nil` if no item exists.
    /// Throws ``GitTicketsError/keychain(_:)`` for any unexpected `OSStatus`.
    static func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw GitTicketsError.keychain(status)
        }
    }

    /// Writes data under (service, account). Overwrites any existing value.
    /// Items use `kSecAttrAccessibleAfterFirstUnlock` so they survive reboots
    /// but are unreadable until the device is unlocked at least once.
    static func write(service: String, account: String, data: Data) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Try to update first; fall through to add if not present.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw GitTicketsError.keychain(addStatus)
            }
        default:
            throw GitTicketsError.keychain(updateStatus)
        }
    }

    /// Deletes the item at (service, account). No-op when the item is absent.
    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw GitTicketsError.keychain(status)
        }
    }
}
