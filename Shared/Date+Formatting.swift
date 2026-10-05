import Foundation

extension Locale {
    /// Česká lokalizace – data formátujeme česky nezávisle na jazyku zařízení
    static let czech = Locale(identifier: "cs_CZ")
}

extension Date {
    /// Krátký formát termínu, např. „po 6. 10. 9:00“
    var deadlineFormatted: String {
        formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.defaultDigits)
                .hour()
                .minute()
                .locale(.czech)
        )
    }

    /// Dlouhý formát, např. „pondělí 6. října 9:00“
    var deadlineLongFormatted: String {
        formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .hour()
                .minute()
                .locale(.czech)
        )
    }

    /// Počet kalendářních dní mezi dneškem a tímto datem
    /// (0 = dnes, 1 = zítra, −1 = včera). Počítá se od půlnoci, ne po 24 hodinách.
    func calendarDays(from reference: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: self)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
