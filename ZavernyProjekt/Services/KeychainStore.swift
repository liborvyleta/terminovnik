import Foundation
import Security
import os

/// Chyba Klíčenky – nese `OSStatus` (např. `errSecInteractionNotAllowed`, když je zařízení
/// po restartu ještě zamčené a položky nejsou dostupné).
nonisolated struct KeychainError: Error, Equatable {
    let status: OSStatus

    /// Přechodná chyba – data existují, ale teď k nim není přístup (zamčené zařízení před prvním odemčením)
    var isTransient: Bool { status == errSecInteractionNotAllowed }
}

/// Jednoduchý obal nad Klíčenkou pro citlivé údaje (přístupový ticket a účet IS/STAG).
///
/// Odlišuje „položka neexistuje“ (`errSecItemNotFound` → `nil`) od ostatních chyb (`throws`),
/// aby přechodná nedostupnost Klíčenky nevedla ke smazání přihlášení.
/// Položky jsou dostupné i na pozadí po prvním odemčení a jen na tomto zařízení (nejdou do záloh).
nonisolated enum KeychainStore {
    private static let service = "cz.liborvyleta.terminovnik.stag"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Terminovnik", category: "keychain")

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    // MARK: Čtení

    /// Data položky; `nil` = položka neexistuje, jiná chyba se vyhodí (`KeychainError`).
    static func data(for key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError(status: errSecDecode) }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Text položky; `nil` = položka neexistuje, jiná chyba se vyhodí.
    static func readString(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { throw KeychainError(status: errSecDecode) }
        return text
    }

    /// Text položky, nebo `nil` (neexistuje i při chybě). Pro místa, kde na důvodu nezáleží.
    static func string(for key: String) -> String? {
        try? readString(for: key)
    }

    /// Stav položky bez načtení jejího obsahu: `errSecSuccess`, `errSecItemNotFound`, nebo jiná chyba.
    static func status(for key: String) -> OSStatus {
        var query = baseQuery(key)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    /// Existuje položka? Při jiné chybě než „nenalezeno“ se vyhodí `KeychainError`.
    static func contains(_ key: String) throws -> Bool {
        let status = status(for: key)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError(status: status)
        }
    }

    // MARK: Zápis

    /// Uloží (nebo přepíše) data. Přepis přes `SecItemUpdate`, nová položka přes `SecItemAdd`,
    /// takže stará hodnota nezmizí dřív, než je zapsaná nová.
    /// - Returns: `true`, pokud se hodnota opravdu uložila
    @discardableResult
    static func set(_ data: Data, for key: String) -> Bool {
        let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        var status = SecItemUpdate(baseQuery(key) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery(key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = accessibility
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        if status != errSecSuccess {
            // Jen kód chyby – nikdy ne hodnotu ani klíč s osobními údaji.
            logger.error("Uložení do Klíčenky selhalo: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    /// Uloží (nebo přepíše) text.
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        set(Data(value.utf8), for: key)
    }

    /// Smaže položku. `true` i tehdy, když položka neexistovala.
    @discardableResult
    static func remove(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logger.error("Smazání z Klíčenky selhalo: \(status, privacy: .public)")
            return false
        }
        return true
    }
}
