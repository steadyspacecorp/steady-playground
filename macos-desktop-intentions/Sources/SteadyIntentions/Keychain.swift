import Foundation
import Security

/// Stores the Steady Personal Access Token in the macOS Keychain.
enum Keychain {
    private static let service = "space.steady.intentions"
    private static let account = "steady-pat"

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        }
        set {
            // Clear any existing entry first.
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)

            guard let value = newValue, !value.isEmpty,
                  let data = value.data(using: .utf8) else {
                return
            }
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
