import Foundation
import WidgetKit

/// Poskytovatel časové osy „Další hodina“ – čte rozvrh, který aplikace ukládá do App Group.
struct NextClassProvider: TimelineProvider {
    /// Kolik dní dopředu plánujeme záznamy (začátky a konce hodin + půlnoci).
    private static let horizonDays = 2

    func placeholder(in context: Context) -> NextClassEntry {
        .sampleUpcoming()
    }

    func getSnapshot(in context: Context, completion: @escaping (NextClassEntry) -> Void) {
        let now = Date.now
        let snapshot = TimetableSnapshot.load()
        // V galerii widgetů ukážeme ukázkový rozvrh, pokud uživatel zatím žádný nemá.
        if context.isPreview && snapshot == nil {
            completion(.sample(now: now))
        } else {
            completion(NextClassEntry(date: now, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextClassEntry>) -> Void) {
        let now = Date.now
        let snapshot = TimetableSnapshot.load()
        let entries = Self.entryDates(now: now, snapshot: snapshot).map {
            NextClassEntry(date: $0, snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// „Teď“, každá půlnoc a začátek i konec každé hodiny v příštích 2 dnech.
    /// Odpočet uvnitř záznamu se hýbe sám (`Text(…, style: .relative)`, `ProgressView(timerInterval:)`).
    static func entryDates(now: Date, snapshot: TimetableSnapshot?, calendar: Calendar = .current) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now

        var dates: Set<Date> = [now]
        for offset in 1...horizonDays {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: startOfToday) {
                dates.insert(midnight)
            }
        }

        if let snapshot {
            for offset in 0...horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
                for occurrence in snapshot.occurrences(on: day, calendar: calendar) {
                    for moment in [occurrence.start, occurrence.end] where moment > now && moment <= horizon {
                        dates.insert(moment)
                    }
                }
            }
        }
        return dates.sorted()
    }
}
