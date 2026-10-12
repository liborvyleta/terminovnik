import AppIntents
import Foundation
import SwiftUI

// Akce nad rozvrhem. Data čtou z `TimetableSnapshot` (App Group), který aplikace ukládá po načtení ze STAGu.
// Intenty zůstávají ve výchozí MainActor izolaci (konformance k `AppIntent` je díky `Sendable` neizolovaná)
// a `perform()` je výslovně `@MainActor`, protože pracuje se SwiftData a SwiftUI.

/// „Další hodina“ – nejbližší (nebo právě probíhající) hodina podle rozvrhu.
///
/// Akce se nabízí v Siri, aplikaci Zkratky a ve Spotlightu. Aplikaci neotevírá; čte uložený rozvrh
/// a odpoví větou s předmětem, typem, dnem, časem a místností spolu s náhledem `TimetableSnippetView`.
struct NextLessonIntent: AppIntent {
    static let title: LocalizedStringResource = "Další hodina"
    static let description = IntentDescription("Řekne, kdy a kde máš nejbližší hodinu podle rozvrhu ze STAGu.")
    static let openAppWhenRun: Bool = false

    /// Najde nejbližší hodinu v příštích 14 dnech (probíhající se počítá).
    /// - Returns: Odpověď s větou a náhledem hodiny; bez rozvrhu nebo výuky vysvětlující text.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let now = Date.now
        let header = String(localized: "Další hodina")

        guard let snapshot = TimetableSnapshot.load(), !snapshot.events.isEmpty else {
            let text = IntentText.timetableNotLoaded
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: text))
        }

        guard let next = snapshot.upcoming(after: now, limit: 1, daysAhead: 14).first else {
            let text = String(localized: "V nejbližších 14 dnech nemáš žádnou výuku.")
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: text))
        }

        let event = next.event
        var sentence: String
        if next.start <= now {
            let end = IntentText.time(next.end)
            sentence = String(localized: "Právě probíhá: \(event.subjectName) (\(event.typeName)) do \(end)")
        } else {
            let day = IntentText.dayPhrase(next.start)
            let time = IntentText.atTime(next.start)
            sentence = String(localized: "Další hodina: \(event.subjectName) (\(event.typeName)) \(day) \(time)",
                              comment: "Např. „Další hodina: Datamining (Přednáška) zítra v 9:00“")
        }
        if let location = event.locationText {
            sentence += String(localized: ", místnost \(location)", comment: "Doplněk věty o další hodině")
        }
        sentence += "."

        return .result(
            dialog: "\(sentence)",
            view: TimetableSnippetView(title: header, lessons: [next], emptyText: "")
        )
    }
}

/// „Rozvrh na den“ – vyjmenuje hodiny dne (dnes / zítra / pozítří).
///
/// Akce se nabízí v Siri, aplikaci Zkratky a ve Spotlightu. Aplikaci neotevírá; vypíše čas, kód
/// předmětu, typ a místnost každé hodiny a zobrazí jejich seznam v `TimetableSnippetView`.
struct TimetableForDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Rozvrh na den"
    static let description = IntentDescription("Vypíše hodiny vybraného dne – čas, předmět, typ a místnost.")
    static let openAppWhenRun: Bool = false

    /// Den, pro který se rozvrh vypíše; výchozí je dnešek.
    @Parameter(title: "Den", default: .dnes)
    var day: ScheduleDay

    static var parameterSummary: some ParameterSummary {
        Summary("Rozvrh na \(\.$day)")
    }

    /// Vypíše hodiny zvoleného dne seřazené podle začátku.
    /// - Returns: Odpověď s výčtem hodin a jejich náhledem; bez rozvrhu nebo výuky vysvětlující text.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: day.dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
        let header = "\(day.label) (\(IntentText.shortDay(date)))"

        guard let snapshot = TimetableSnapshot.load(), !snapshot.events.isEmpty else {
            let text = IntentText.timetableNotLoaded
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: text))
        }

        let lessons = snapshot.occurrences(on: date)
        guard !lessons.isEmpty else {
            let text = String(localized: "\(header): Volno – žádná výuka.")
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: String(localized: "Volno")))
        }

        let count = lessons.count
        let items = lessons.map { lesson in
            let event = lesson.event
            var item = "\(IntentText.time(lesson.start)) \(event.subjectCode) \(event.typeName)"
            if let location = event.locationText { item += ", \(location)" }
            return item
        }
        let list = items.joined(separator: "; ")
        let sentence = String(localized: "\(header) máš \(count) hodin: \(list).",
                              comment: "Např. „Dnes (út 6. 10.) máš 3 hodiny: …“ – plurál podle počtu hodin (2. argument)")

        return .result(
            dialog: "\(sentence)",
            view: TimetableSnippetView(title: header, lessons: lessons, emptyText: String(localized: "Volno"))
        )
    }
}
