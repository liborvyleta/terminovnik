import Foundation
import Security
import os

/// Chyba Klíčenky – nese `OSStatus` (např. `errSecInteractionNotAllowed`, když je zařízení
/// po restartu ještě zamčené a položky nejsou dostupné).
///
/// Vyhazují ji čtecí metody ``KeychainStore``; volající (např. úložiště účtu STAG) podle
/// ``isTransient`` rozhodne, zda přihlášení zachovat.
nonisolated struct KeychainError: Error, Equatable {
    /// Návratový kód funkcí Security frameworku
    let status: OSStatus

    /// Přechodná chyba – data existují, ale teď k nim není přístup (zamčené zařízení před prvním odemčením)
    var isTransient: Bool { status == errSecInteractionNotAllowed }
}

/// Jednoduchý obal nad Klíčenkou pro citlivé údaje (přístupový ticket a účet IS/STAG).
///
/// Odlišuje „položka neexistuje“ (`errSecItemNotFound` → `nil`) od ostatních chyb (`throws`),
/// aby přechodná nedostupnost Klíčenky nevedla ke smazání přihlášení.
/// Položky jsou dostupné i na pozadí po prvním odemčení a jen na tomto zařízení (nejdou do záloh).
/// Všechny položky jsou typu generic password se společnou službou a klíčem v `kSecAttrAccount`.
nonisolated enum KeychainStore {
    /// Hodnota `kSecAttrService` všech položek aplikace
    private static let service = "cz.liborvyleta.terminovnik.stag"
    /// Logger chyb (zapisuje jen kódy, nikdy hodnoty)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Terminovnik", category: "keychain")

    /// Základní dotaz na položku daného klíče.
    /// - Parameter key: název položky (`kSecAttrAccount`)
    /// - Returns: Slovník s třídou, službou a účtem pro funkce `SecItem…`.
    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    // MARK: - Čtení

    /// Data položky; `nil` = položka neexistuje, jiná chyba se vyhodí (`KeychainError`).
    /// - Parameter key: název položky
    /// - Returns: Uložená data, nebo `nil`, pokud položka neexistuje.
    /// - Throws: ``KeychainError`` s kódem `SecItemCopyMatching` (např. zamčené zařízení),
    ///   nebo s `errSecDecode`, pokud výsledek nejsou data.
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
    /// - Parameter key: název položky
    /// - Returns: Text v UTF-8, nebo `nil`, pokud položka neexistuje.
    /// - Throws: ``KeychainError`` z ``data(for:)``, nebo s `errSecDecode`, když data nejsou platné UTF-8.
    static func readString(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { throw KeychainError(status: errSecDecode) }
        return text
    }

    /// Text položky, nebo `nil` (neexistuje i při chybě). Pro místa, kde na důvodu nezáleží.
    /// - Parameter key: název položky
    /// - Returns: Text položky, nebo `nil` při neexistenci i jakékoli chybě.
    static func string(for key: String) -> String? {
        try? readString(for: key)
    }

    /// Stav položky bez načtení jejího obsahu: `errSecSuccess`, `errSecItemNotFound`, nebo jiná chyba.
    /// - Parameter key: název položky
    /// - Returns: Kód vrácený `SecItemCopyMatching` při dotazu jen na atributy.
    static func status(for key: String) -> OSStatus {
        var query = baseQuery(key)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    /// Existuje položka? Při jiné chybě než „nenalezeno“ se vyhodí `KeychainError`.
    /// - Parameter key: název položky
    /// - Returns: `true`, pokud položka existuje, `false`, pokud ne.
    /// - Throws: ``KeychainError`` při jiném stavu než `errSecSuccess` nebo `errSecItemNotFound`.
    static func contains(_ key: String) throws -> Bool {
        let status = status(for: key)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError(status: status)
        }
    }

    // MARK: - Zápis

    /// Uloží (nebo přepíše) data. Přepis přes `SecItemUpdate`, nová položka přes `SecItemAdd`,
    /// takže stará hodnota nezmizí dřív, než je zapsaná nová.
    ///
    /// Položka má přístupnost `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; chyba se zaloguje jen kódem.
    /// - Parameters:
    ///   - data: ukládaná hodnota
    ///   - key: název položky
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
    /// - Parameters:
    ///   - value: text uložený v UTF-8
    ///   - key: název položky
    /// - Returns: `true`, pokud se hodnota opravdu uložila (viz ``set(_:for:)``).
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        set(Data(value.utf8), for: key)
    }

    /// Smaže položku. `true` i tehdy, když položka neexistovala.
    /// - Parameter key: název položky
    /// - Returns: `false` jen při jiné chybě než „nenalezeno“ (ta se zaloguje).
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
