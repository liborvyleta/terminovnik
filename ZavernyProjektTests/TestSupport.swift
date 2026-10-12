import Foundation
import SwiftData
@testable import ZavernyProjekt

// Společné pomůcky pro testy. Vše je deterministické (pevná data, pevná časová zóna)
// a nikdy nesahá na skutečná data uživatele (žádné `.shared` úložiště, App Group ani síť).

/// Pevně nastavené kalendáře pro deterministické testy.
///
/// Nabízí kalendář Europe/Prague pro funkce s kalendářem v parametru
/// a kalendář zařízení pro funkce, které interně používají `Calendar.current`.
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

/// Vytvoří konkrétní okamžik v daném kalendáři.
///
/// - Parameters:
///   - year: Rok.
///   - month: Měsíc (1–12).
///   - day: Den v měsíci.
///   - hour: Hodina, výchozí 0.
///   - minute: Minuta, výchozí 0.
///   - calendar: Kalendář pro sestavení data, výchozí Europe/Prague.
/// - Returns: Datum odpovídající zadaným složkám; při neplatné kombinaci test spadne.
func makeDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0,
    calendar: Calendar = TestCalendar.prague
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Vytvoří SwiftData kontejner jen v paměti.
///
/// Každý test tak dostane vlastní prázdnou databázi s modely `Subject` a `ExamTask`.
///
/// - Returns: Nový paměťový `ModelContainer`.
/// - Throws: Chybu SwiftData, pokud kontejner nelze vytvořit.
func makeInMemoryContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Subject.self, ExamTask.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

/// Dekóduje JSON fixture (odpověď STAGu) zapsanou jako text.
///
/// - Parameters:
///   - type: Cílový typ.
///   - json: JSON v textové podobě.
/// - Returns: Dekódovaná hodnota.
/// - Throws: `DecodingError`, pokud JSON neodpovídá typu.
func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}
