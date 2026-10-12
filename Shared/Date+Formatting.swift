import Foundation

extension Locale {
    /// Locale podle jazyka, ve kterém aplikace (nebo widget) právě běží.
    ///
    /// Angličtina → britské zvyklosti (24hodinový čas, den před měsícem), jinak čeština.
    /// Jazyk se za běhu nemění (iOS při změně jazyka aplikaci ukončí), proto stačí spočítat jednou.
    nonisolated static let app: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "cs"
        return language.hasPrefix("en") ? Locale(identifier: "en_GB") : Locale(identifier: "cs_CZ")
    }()

    /// Jazyk aplikace – alias pro `Locale.app`.
    ///
    /// Název zůstává kvůli kompatibilitě
    /// se staršími voláními (`.locale(.czech)`, `.environment(\.locale, .czech)`).
    nonisolated static var czech: Locale { .app }
}

extension Date {
    /// Krátký formát termínu, např. „po 6. 10. 9:00“ (anglicky „Mon 06/10, 09:00“).
    var deadlineFormatted: String {
        formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.defaultDigits)
                .hour()
                .minute()
                .locale(.app)
        )
    }

    /// Dlouhý formát, např. „pondělí 6. října 9:00“ (anglicky „Monday 6 October 09:00“).
    var deadlineLongFormatted: String {
        formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .hour()
                .minute()
                .locale(.app)
        )
    }

    /// Spočítá počet kalendářních dní mezi referenčním dnem a tímto datem.
    ///
    /// Počítá se od půlnoci, ne po 24 hodinách (0 = dnes, 1 = zítra, −1 = včera).
    /// - Parameters:
    ///   - reference: Referenční okamžik, výchozí je aktuální čas.
    ///   - calendar: Kalendář pro výpočet, výchozí je aktuální.
    /// - Returns: Rozdíl ve dnech (záporný pro minulost).
    func calendarDays(from reference: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: self)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
