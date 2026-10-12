import Foundation
import SwiftUI
import WidgetKit

/// Jeden záznam časové osy widgetu „Další hodina“.
///
/// Nese nejbližší výskyty výuky z rozvrhu uloženého aplikací v App Group a okamžik,
/// vůči kterému se určuje stav „probíhá / za chvíli / zítra“. Záznamy vytváří `NextClassProvider`.
nonisolated struct NextClassEntry: TimelineEntry {
    /// Okamžik, kdy systém záznam zobrazí. Stav „probíhá / za chvíli / zítra“ se počítá vůči němu.
    let date: Date
    /// Nejbližší výskyty od `date` seřazené podle začátku (probíhající hodina se počítá).
    let occurrences: [TimetableOccurrence]
    /// Má aplikace uložený rozvrh? `false` = uživatel se zatím nepřihlásil do STAGu.
    let hasTimetable: Bool

    /// Nejbližší výskyt vůbec (i za několik dní) – pro nápovědu „Příště…“ v prázdném stavu.
    ///
    /// - Returns: První výskyt, nebo `nil`, pokud žádný není.
    var next: TimetableOccurrence? { occurrences.first }

    /// Výskyty dnes a zítra – jen ty widget ukazuje jako „další hodiny“.
    ///
    /// - Returns: Výskyty začínající před půlnocí pozítří; při selhání výpočtu data všechny výskyty.
    var soon: [TimetableOccurrence] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) else { return occurrences }
        return occurrences.filter { $0.start < dayAfterTomorrow }
    }

    /// Zjistí, zda výskyt právě probíhá (vůči `date`).
    ///
    /// - Parameter occurrence: Posuzovaný výskyt.
    /// - Returns: `true`, pokud platí `start <= date < end`.
    func isOngoing(_ occurrence: TimetableOccurrence) -> Bool {
        occurrence.start <= date && date < occurrence.end
    }

    /// Zjistí, zda je výskyt dnes (vůči `date`). Probíhající hodina se počítá jako dnešní.
    ///
    /// - Parameter occurrence: Posuzovaný výskyt.
    /// - Returns: `true`, pokud výskyt probíhá nebo začíná ve stejný den jako `date`.
    func isToday(_ occurrence: TimetableOccurrence) -> Bool {
        isOngoing(occurrence) || Calendar.current.isDate(occurrence.start, inSameDayAs: date)
    }

    /// Relevance pro chytrý zásobník (Smart Stack) – widget vyzdvihne těsně před hodinou a během ní.
    ///
    /// Skóre 100 hodinu před začátkem, 80 během hodiny, 20 pro pozdější dnešní hodinu,
    /// 5 pro zítřejší a 0 bez výuky.
    ///
    /// - Returns: Relevance záznamu pro systém.
    var relevance: TimelineEntryRelevance? {
        guard let first = soon.first else { return TimelineEntryRelevance(score: 0) }
        if isOngoing(first) {
            return TimelineEntryRelevance(score: 80, duration: first.end.timeIntervalSince(date))
        }
        let untilStart = first.start.timeIntervalSince(date)
        if untilStart <= 60 * 60 {
            return TimelineEntryRelevance(score: 100, duration: untilStart)
        }
        return TimelineEntryRelevance(score: isToday(first) ? 20 : 5)
    }
}

nonisolated extension NextClassEntry {
    /// Vytvoří záznam z uloženého rozvrhu.
    ///
    /// Převezme nejvýše 6 výskytů v příštích 14 dnech od `date`.
    ///
    /// - Parameters:
    ///   - date: Okamžik záznamu.
    ///   - snapshot: Uložený rozvrh, nebo `nil`, pokud ještě nebyl načten.
    init(date: Date, snapshot: TimetableSnapshot?) {
        self.init(
            date: date,
            occurrences: snapshot?.upcoming(after: date, limit: 6, daysAhead: 14) ?? [],
            hasTimetable: snapshot != nil
        )
    }
}

// MARK: - Ukázková data (placeholder, galerie widgetů, #Preview, snímky)

nonisolated extension NextClassEntry {
    /// Ukázka z `TimetableSnapshot.sample` k aktuálnímu času.
    ///
    /// Když by ukázkový rozvrh zrovna nic dnes neměl (večer, víkend), posune ukázkové hodiny na dnešek.
    ///
    /// - Parameter now: Referenční okamžik, vůči kterému se počítají relativní termíny; výchozí je aktuální čas.
    /// - Returns: Ukázkový záznam s alespoň jednou dnešní hodinou.
    static func sample(now: Date = .now) -> NextClassEntry {
        let real = NextClassEntry(date: now, snapshot: .sample)
        if let first = real.soon.first, real.isToday(first) {
            return real
        }
        return sampleUpcoming(now: now)
    }

    /// Ukázka „další hodina za 20–25 minut“ – akce z `TimetableSnapshot.sample` posunuté na dnešek.
    ///
    /// - Parameter now: Referenční okamžik, vůči kterému se počítají relativní termíny; výchozí je aktuální čas.
    /// - Returns: Záznam, jehož první hodina začíná na nejbližších celých 5 minut po `now + 20 min`.
    static func sampleUpcoming(now: Date = .now) -> NextClassEntry {
        let start = rounded(now.addingTimeInterval(20 * 60), toMinutes: 5, up: true)
        return NextClassEntry(date: now, occurrences: sampleDay(startingAt: start), hasTimetable: true)
    }

    /// Ukázka „hodina právě probíhá“ (začala zhruba před 35 minutami).
    ///
    /// - Parameter now: Referenční okamžik, vůči kterému se počítají relativní termíny; výchozí je aktuální čas.
    /// - Returns: Záznam s probíhající první hodinou.
    static func sampleOngoing(now: Date = .now) -> NextClassEntry {
        let start = rounded(now.addingTimeInterval(-35 * 60), toMinutes: 5, up: false)
        return NextClassEntry(date: now, occurrences: sampleDay(startingAt: start), hasTimetable: true)
    }

    /// Ukázka bez výuky dnes i zítra – nejbližší hodina až za 3 dny v 8:00.
    ///
    /// - Parameter now: Referenční okamžik, vůči kterému se počítají relativní termíny; výchozí je aktuální čas.
    /// - Returns: Záznam s jediným vzdáleným výskytem.
    static func sampleFree(now: Date = .now) -> NextClassEntry {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now)) ?? now
        let events = TimetableSnapshot.sample.events
        let occurrences: [TimetableOccurrence] = events.first { $0.id == "s3" }.map { event in
            let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
            return [TimetableOccurrence(event: event, start: start, end: start.addingTimeInterval(2 * 3600))]
        } ?? []
        return NextClassEntry(date: now, occurrences: occurrences, hasTimetable: true)
    }

    /// Ukázka stavu, kdy rozvrh ještě není načtený (uživatel se nepřihlásil do STAGu).
    ///
    /// - Parameter now: Referenční okamžik, vůči kterému se počítají relativní termíny; výchozí je aktuální čas.
    /// - Returns: Záznam bez výskytů s `hasTimetable == false`.
    static func noTimetable(now: Date = .now) -> NextClassEntry {
        NextClassEntry(date: now, occurrences: [], hasTimetable: false)
    }

    /// Tři akce ukázkového rozvrhu za sebou od `start`: cvičení 2 h, přednáška 1 h, po pauze přednáška 2 h.
    ///
    /// - Parameter start: Začátek první akce.
    /// - Returns: Výskyty akcí, které v ukázkovém rozvrhu existují.
    private static func sampleDay(startingAt start: Date) -> [TimetableOccurrence] {
        let events = Dictionary(uniqueKeysWithValues: TimetableSnapshot.sample.events.map { ($0.id, $0) })
        let plan: [(id: String, from: Double, to: Double)] = [
            ("s2", 0, 120),   // AP9PT – cvičení
            ("s1", 120, 180), // AP9PT – přednáška
            ("s4", 240, 360)  // AP9EV – přednáška
        ]
        return plan.compactMap { item in
            guard let event = events[item.id] else { return nil }
            return TimetableOccurrence(
                event: event,
                start: start.addingTimeInterval(item.from * 60),
                end: start.addingTimeInterval(item.to * 60)
            )
        }
    }

    /// Zaokrouhlí datum na násobek zadaného počtu minut.
    ///
    /// - Parameters:
    ///   - date: Zaokrouhlované datum.
    ///   - minutes: Krok zaokrouhlení v minutách.
    ///   - up: `true` zaokrouhlí nahoru, `false` dolů.
    /// - Returns: Zaokrouhlené datum.
    private static func rounded(_ date: Date, toMinutes minutes: Int, up: Bool) -> Date {
        let step = TimeInterval(minutes * 60)
        let value = date.timeIntervalSinceReferenceDate / step
        return Date(timeIntervalSinceReferenceDate: (up ? value.rounded(.up) : value.rounded(.down)) * step)
    }
}
