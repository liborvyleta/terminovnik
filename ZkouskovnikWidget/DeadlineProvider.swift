import Foundation
import WidgetKit

/// Poskytovatel časové osy – čte přehled, který zapisuje aplikace do App Group.
struct DeadlineProvider: TimelineProvider {
    /// Kolik dní dopředu plánujeme záznamy (půlnoci + okamžiky termínů).
    private static let horizonDays = 7

    func placeholder(in context: Context) -> DeadlineEntry {
        .sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
        let now = Date.now
        let deadlines = WidgetSnapshot.load()?.deadlines ?? []
        // V galerii widgetů ukážeme ukázková data, pokud uživatel zatím nic nemá.
        if context.isPreview && deadlines.isEmpty {
            completion(.sample(now: now))
        } else {
            completion(DeadlineEntry(date: now, deadlines: deadlines))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
        let now = Date.now
        let deadlines = WidgetSnapshot.load()?.deadlines ?? []
        let entries = Self.entryDates(now: now, deadlines: deadlines).map {
            DeadlineEntry(date: $0, deadlines: deadlines)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// „Teď“, každá půlnoc následujících 7 dní a okamžik každého termínu v příštích 7 dnech.
    static func entryDates(now: Date, deadlines: [WidgetDeadline], calendar: Calendar = .current) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now

        var dates: Set<Date> = [now]
        for offset in 1...horizonDays {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: startOfToday) {
                dates.insert(midnight)
            }
        }
        for deadline in deadlines where deadline.dueDate > now && deadline.dueDate <= horizon {
            dates.insert(deadline.dueDate)
        }
        return dates.sorted()
    }
}
