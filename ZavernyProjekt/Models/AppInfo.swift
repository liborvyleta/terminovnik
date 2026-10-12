import Foundation

/// Údaje o aplikaci a autorovi pro sekci „O aplikaci“ a zásady ochrany osobních údajů.
///
/// Před odesláním do App Store musí být vyplněné `privacyPolicyURL` (veřejně dostupné zásady,
/// stejná adresa jako v App Store Connect → Privacy Policy URL) a kontakt na podporu
/// (`supportURL` a/nebo `supportEmail`, stejná Support URL jako v App Store Connect).
/// Dokud jsou hodnoty `nil`, příslušné řádky se v aplikaci nezobrazí.
nonisolated enum AppInfo {
    /// Veřejná adresa zásad ochrany osobních údajů; `nil` = řádek se nezobrazí.
    static let privacyPolicyURL: URL? = nil
    /// Stránka podpory (Support URL v App Store Connect); `nil` = řádek se nezobrazí.
    static let supportURL: URL? = nil
    /// E-mail pro podporu a dotazy k osobním údajům; `nil` = řádek se nezobrazí.
    static let supportEmail: String? = nil
    /// Autor a správce aplikace.
    static let developerName = "Libor Výleta"

    /// Odkaz `mailto:` na podporu s předvyplněným předmětem zprávy.
    ///
    /// Vrací `nil`, pokud `supportEmail` není vyplněný nebo obsahuje jen bílé znaky.
    static var supportMailURL: URL? {
        guard let email = supportEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "Termínovník")]
        return components.url
    }
}
