import Foundation
import WidgetKit

/// Poskytovatel časové osy widgetu „Další hodina“.
///
/// Rozvrh čte z `TimetableSnapshot`, který aplikace ukládá do sdíleného kontejneru App Group.
/// Časová osa obsahuje záznamy pro „teď“, každou půlnoc a začátek i konec každé hodiny
/// v příštích 2 dnech; po posledním záznamu si systém vyžádá novou (politika `.atEnd`).
struct NextClassProvider: TimelineProvider {
    /// Kolik dní dopředu plánujeme záznamy (začátky a konce hodin + půlnoci).
    private static let horizonDays = 2

    /// Vrátí zástupný záznam, který systém zobrazí, než má k dispozici skutečná data.
    ///
    /// Systém ho volá synchronně, např. při prvním vykreslení nebo v redigovaném stavu.
    ///
    /// - Parameter context: Kontext widgetu; zde se nepoužívá.
    /// - Returns: Ukázkový záznam `NextClassEntry.sampleUpcoming()`.
    func placeholder(in context: Context) -> NextClassEntry {
        .sampleUpcoming()
    }

    /// Dodá jeden záznam pro okamžité zobrazení, typicky v galerii widgetů.
    ///
    /// Systém metodu volá, když potřebuje rychle jediný stav widgetu. Načte rozvrh z App Group;
    /// v galerii (`context.isPreview`) bez uloženého rozvrhu vrátí ukázková data.
    ///
    /// - Parameters:
    ///   - context: Kontext widgetu; rozhoduje příznak `isPreview`.
    ///   - completion: Blok, kterému se předá výsledný záznam.
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

    /// Sestaví časovou osu záznamů pro průběžné zobrazování widgetu.
    ///
    /// Systém metodu volá po přidání widgetu, po skončení předchozí osy a po vynuceném
    /// obnovení z aplikace. Záznamy vzniknou pro okamžiky z `entryDates(now:snapshot:calendar:)`
    /// z rozvrhu v App Group; politika je `.atEnd`.
    ///
    /// - Parameters:
    ///   - context: Kontext widgetu; zde se nepoužívá.
    ///   - completion: Blok, kterému se předá hotová časová osa.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextClassEntry>) -> Void) {
        let now = Date.now
        let snapshot = TimetableSnapshot.load()
        let entries = Self.entryDates(now: now, snapshot: snapshot).map {
            NextClassEntry(date: $0, snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Spočítá okamžiky záznamů časové osy.
    ///
    /// Zahrnuje „teď“, každou půlnoc a začátek i konec každé hodiny v příštích 2 dnech.
    /// Odpočet uvnitř záznamu se hýbe sám (`Text(…, style: .relative)`, `ProgressView(timerInterval:)`).
    ///
    /// - Parameters:
    ///   - now: Aktuální okamžik, první záznam osy.
    ///   - snapshot: Uložený rozvrh; bez něj osa obsahuje jen „teď“ a půlnoci.
    ///   - calendar: Kalendář pro výpočet dní; výchozí je `.current`.
    /// - Returns: Vzestupně seřazené okamžiky bez duplicit.
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
