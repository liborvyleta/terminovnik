import Foundation

/// Správné české tvary podle počtu: 1 kredit, 2–4 kredity, 5+ kreditů.
///
/// Jen čeština – nový kód místo toho používá celou frázi s číslem v `String(localized:)`
/// a plurálové varianty ve String Catalogu (funguje i pro angličtinu).
/// Soubor se kompiluje do aplikace, widgetu i hodinek.
enum CzechPlural {
    /// Vybere tvar podle počtu (rozhoduje absolutní hodnota).
    /// - Parameters:
    ///   - count: Počet.
    ///   - one: Tvar pro 1.
    ///   - few: Tvar pro 2–4.
    ///   - many: Tvar pro 0 a 5 a více.
    /// - Returns: Zvolený tvar slova (bez čísla).
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        switch abs(count) {
        case 1: one
        case 2...4: few
        default: many
        }
    }

    /// Tvar slova „kredit“ podle počtu.
    /// - Parameter count: Počet kreditů.
    /// - Returns: „kredit“, „kredity“ nebo „kreditů“.
    static func credits(_ count: Int) -> String {
        form(count, one: "kredit", few: "kredity", many: "kreditů")
    }

    /// Tvar slova „úkol“ podle počtu.
    /// - Parameter count: Počet úkolů.
    /// - Returns: „úkol“, „úkoly“ nebo „úkolů“.
    static func tasks(_ count: Int) -> String {
        form(count, one: "úkol", few: "úkoly", many: "úkolů")
    }

    /// Tvar slova „den“ podle počtu.
    /// - Parameter count: Počet dní.
    /// - Returns: „den“, „dny“ nebo „dní“.
    static func days(_ count: Int) -> String {
        form(count, one: "den", few: "dny", many: "dní")
    }
}
