import Foundation
import Security

/// Jednoduchý obal nad Klíčenkou pro citlivé řetězce (přístupový ticket do IS/STAG).
enum KeychainStore {
    private static let service = "cz.utb.zkouskovnik.stag"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    /// Uloží (nebo přepíše) hodnotu. Dostupná i na pozadí po prvním odemčení, jen na tomto zařízení.
    static func set(_ value: String, for key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Uložení do Klíčenky selhalo: \(status)")
        }
    }

    static func string(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
