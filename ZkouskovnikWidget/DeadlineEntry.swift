import Foundation
import SwiftUI
import WidgetKit

/// Jeden záznam časové osy widgetu – deadliny a okamžik, vůči kterému se počítá odpočet.
nonisolated struct DeadlineEntry: TimelineEntry {
    /// Okamžik, kdy systém záznam zobrazí. Odpočet („Zítra“, „Za 3 dny“…) se počítá vůči němu.
    let date: Date
    /// Nesplněné deadliny seřazené od nejbližšího (včetně těch po termínu).
    let deadlines: [WidgetDeadline]

    var nearest: WidgetDeadline? { deadlines.first }
}

// MARK: - Ukázková data (galerie widgetů, placeholder, #Preview)

nonisolated extension DeadlineEntry {
    /// Realistická ukázka s předměty FAI UTB – termíny jsou relativní vůči `now`.
    static func sample(now: Date = .now) -> DeadlineEntry {
        DeadlineEntry(date: now, deadlines: WidgetDeadline.samples(now: now))
    }

    /// Prázdný stav – vše hotovo.
    static func empty(now: Date = .now) -> DeadlineEntry {
        DeadlineEntry(date: now, deadlines: [])
    }
}

nonisolated extension WidgetDeadline {
    /// Názvy termínů a typů jsou lokalizované (galerie widgetů v angličtině), kódy a názvy předmětů ne.
    static func samples(now: Date = .now) -> [WidgetDeadline] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        func at(days: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            WidgetDeadline(
                id: UUID(), title: String(localized: "Zápočtový test"), subjectCode: "AP9PT",
                subjectName: "Pokročilé mobilní technologie", hexColor: "#3E63DD",
                typeTitle: String(localized: "Zápočet"), typeSymbol: "checkmark.seal.fill",
                dueDate: at(days: 1, hour: 9)
            ),
            WidgetDeadline(
                id: UUID(), title: String(localized: "Odevzdání semestrálního projektu"), subjectCode: "AP9PT",
                subjectName: "Pokročilé mobilní technologie", hexColor: "#3E63DD",
                typeTitle: String(localized: "Projekt"), typeSymbol: "hammer.fill",
                dueDate: at(days: 3, hour: 23, minute: 59)
            ),
            WidgetDeadline(
                id: UUID(), title: String(localized: "Písemná zkouška"), subjectCode: "AP9SI",
                subjectName: "Softwarové inženýrství", hexColor: "#E5484D",
                typeTitle: String(localized: "Zkouška"), typeSymbol: "graduationcap.fill",
                dueDate: at(days: 5, hour: 8, minute: 30)
            ),
            WidgetDeadline(
                id: UUID(), title: String(localized: "Analýza rizik – seminární práce"), subjectCode: "AP9BI",
                subjectName: "Bezpečnost informačních systémů", hexColor: "#30A46C",
                typeTitle: String(localized: "Úkol"), typeSymbol: "doc.text.fill",
                dueDate: at(days: 8, hour: 12)
            ),
            WidgetDeadline(
                id: UUID(), title: String(localized: "Ústní zkouška"), subjectCode: "AP9UI",
                subjectName: "Umělá inteligence", hexColor: "#8E4EC6",
                typeTitle: String(localized: "Zkouška"), typeSymbol: "graduationcap.fill",
                dueDate: at(days: 12, hour: 10)
            ),
            WidgetDeadline(
                id: UUID(), title: String(localized: "Prezentace týmového projektu"), subjectCode: "AP9TP",
                subjectName: "Týmový projekt", hexColor: "#F76B15",
                typeTitle: String(localized: "Projekt"), typeSymbol: "hammer.fill",
                dueDate: at(days: 16, hour: 14)
            ),
            WidgetDeadline(
                id: UUID(), title: String(localized: "Zápočet z cvičení"), subjectCode: "AP9DS",
                subjectName: "Distribuované systémy", hexColor: "#12A594",
                typeTitle: String(localized: "Zápočet"), typeSymbol: "checkmark.seal.fill",
                dueDate: at(days: 20, hour: 11)
            )
        ]
    }
}
