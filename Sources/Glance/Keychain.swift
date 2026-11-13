import Foundation
import Security

/// API keys are stored in the login Keychain, one item per service.
///
/// Note: the Keychain remembers WHICH APP may read an item by its code
/// signature. If you rebuild Glance without a developer certificate, macOS will
/// ask once whether the new build may read the saved keys; choose "Always Allow".
enum Keychain {
    private static let service = "Glance API keys"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Saves `value`, or deletes the item when `value` is empty.
    static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrLabel as String] = "Glance: \(account)"
        SecItemAdd(item as CFDictionary, nil)
    }
}
