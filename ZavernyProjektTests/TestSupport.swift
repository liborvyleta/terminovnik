import Foundation
import SwiftData
@testable import ZavernyProjekt

// Společné pomůcky pro testy. Vše je deterministické (pevná data, pevná časová zóna)
// a nikdy nesahá na skutečná data uživatele (žádné `.shared` úložiště, App Group ani síť).

enum TestCalendar {
    /// Gregoriánský kalendář v časové zóně Europe/Prague – pro funkce, které berou kalendář parametrem.
    static let prague: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.locale = Locale(identifier: "cs_CZ")
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Kalendář zařízení – pro funkce, které interně používají `Calendar.current`
    /// (Countdown, DeadlineUrgency, Dashboard). Data stavíme ve stejném kalendáři,
    /// takže výsledky nezávisí na časové zóně simulátoru.
    static var device: Calendar { .current }
}

/// Konkrétní okamžik v daném kalendáři (výchozí Europe/Prague).
func makeDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0,
    calendar: Calendar = TestCalendar.prague
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// SwiftData kontejner jen v paměti – každý test dostane vlastní prázdnou databázi.
func makeInMemoryContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Subject.self, ExamTask.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

/// Dekódování JSON fixture (odpovědi STAGu) z textu.
func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}
