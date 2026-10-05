import AppIntents
import Foundation
import SwiftUI

// Akce nad rozvrhem. Data čtou z `TimetableSnapshot` (App Group), který aplikace ukládá po načtení ze STAGu.
// Intenty zůstávají ve výchozí MainActor izolaci (konformance k `AppIntent` je díky `Sendable` neizolovaná)
// a `perform()` je výslovně `@MainActor`, protože pracuje se SwiftData a SwiftUI.

/// „Další hodina“ – nejbližší (nebo právě probíhající) hodina podle rozvrhu.
struct NextLessonIntent: AppIntent {
    static let title: LocalizedStringResource = "Další hodina"
    static let description = IntentDescription("Řekne, kdy a kde máš nejbližší hodinu podle rozvrhu ze STAGu.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let now = Date.now
        let header = "Další hodina"

        guard let snapshot = TimetableSnapshot.load(), !snapshot.events.isEmpty else {
            let text = IntentText.timetableNotLoaded
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: text))
        }

        guard let next = snapshot.upcoming(after: now, limit: 1, daysAhead: 14).first else {
            let text = "V nejbližších 14 dnech nemáš žádnou výuku."
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: text))
        }

        let event = next.event
        var sentence: String
        if next.start <= now {
            sentence = "Právě probíhá: \(event.subjectName) (\(event.typeName)) do \(IntentText.time(next.end))"
        } else {
            sentence = "Další hodina: \(event.subjectName) (\(event.typeName)) "
                + "\(IntentText.dayPhrase(next.start)) \(IntentText.atTime(next.start))"
        }
        if let location = event.locationText {
            sentence += ", místnost \(location)"
        }
        sentence += "."

        return .result(
            dialog: "\(sentence)",
            view: TimetableSnippetView(title: header, lessons: [next], emptyText: "")
        )
    }
}

/// „Rozvrh na den“ – vyjmenuje hodiny dne (dnes / zítra / pozítří).
struct TimetableForDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Rozvrh na den"
    static let description = IntentDescription("Vypíše hodiny vybraného dne – čas, předmět, typ a místnost.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Den", default: .dnes)
    var day: ScheduleDay

    static var parameterSummary: some ParameterSummary {
        Summary("Rozvrh na \(\.$day)")
    }

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
            let text = "\(header): Volno – žádná výuka."
            return .result(dialog: "\(text)", view: TimetableSnippetView(title: header, lessons: [], emptyText: "Volno"))
        }

        let count = lessons.count
        let items = lessons.map { lesson in
            let event = lesson.event
            var item = "\(IntentText.time(lesson.start)) \(event.subjectCode) \(event.typeName)"
            if let location = event.locationText { item += ", \(location)" }
            return item
        }
        let countText = "\(count) \(CzechPlural.form(count, one: "hodinu", few: "hodiny", many: "hodin"))"
        let sentence = "\(header) máš \(countText): \(items.joined(separator: "; "))."

        return .result(
            dialog: "\(sentence)",
            view: TimetableSnippetView(title: header, lessons: lessons, emptyText: "Volno")
        )
    }
}
