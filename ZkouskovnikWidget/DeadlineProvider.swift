import Foundation
import WidgetKit

/// Poskytovatel časové osy widgetu „Nejbližší deadliny“.
///
/// Data čte z přehledu (`WidgetSnapshot`), který aplikace zapisuje do sdíleného
/// kontejneru App Group. Časová osa obsahuje záznamy pro „teď“, každou půlnoc a okamžik
/// každého termínu v příštích 7 dnech; po posledním záznamu si systém vyžádá novou
/// (politika `.atEnd`). Aplikace navíc může osu obnovit sama po změně dat.
struct DeadlineProvider: TimelineProvider {
    /// Kolik dní dopředu plánujeme záznamy (půlnoci + okamžiky termínů).
    private static let horizonDays = 7

    /// Vrátí zástupný záznam, který systém zobrazí, než má k dispozici skutečná data.
    ///
    /// Systém ho volá synchronně, např. při prvním vykreslení nebo v redigovaném stavu.
    ///
    /// - Parameter context: Kontext widgetu (rodina, velikost); zde se nepoužívá.
    /// - Returns: Ukázkový záznam `DeadlineEntry.sample()`.
    func placeholder(in context: Context) -> DeadlineEntry {
        .sample()
    }

    /// Dodá jeden záznam pro okamžité zobrazení, typicky v galerii widgetů.
    ///
    /// Systém metodu volá, když potřebuje rychle jediný stav widgetu (galerie, přechodné stavy).
    /// Načte přehled z App Group; v galerii (`context.isPreview`) bez uložených deadlinů vrátí ukázková data.
    ///
    /// - Parameters:
    ///   - context: Kontext widgetu; rozhoduje příznak `isPreview`.
    ///   - completion: Blok, kterému se předá výsledný záznam.
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

    /// Sestaví časovou osu záznamů pro průběžné zobrazování widgetu.
    ///
    /// Systém metodu volá po přidání widgetu, po skončení předchozí osy a po vynuceném
    /// obnovení z aplikace. Všechny záznamy sdílejí deadliny z přehledu v App Group a liší se
    /// jen okamžikem `date` podle `entryDates(now:deadlines:calendar:)`; politika je `.atEnd`.
    ///
    /// - Parameters:
    ///   - context: Kontext widgetu; zde se nepoužívá.
    ///   - completion: Blok, kterému se předá hotová časová osa.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
        let now = Date.now
        let deadlines = WidgetSnapshot.load()?.deadlines ?? []
        let entries = Self.entryDates(now: now, deadlines: deadlines).map {
            DeadlineEntry(date: $0, deadlines: deadlines)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Spočítá okamžiky záznamů časové osy.
    ///
    /// Zahrnuje „teď“, každou půlnoc následujících 7 dní a okamžik každého termínu
    /// v příštích 7 dnech (jen budoucí termíny). Duplicitní okamžiky se sloučí.
    ///
    /// - Parameters:
    ///   - now: Aktuální okamžik, první záznam osy.
    ///   - deadlines: Deadliny, jejichž termíny se mají do osy přidat.
    ///   - calendar: Kalendář pro výpočet půlnocí; výchozí je `.current`.
    /// - Returns: Vzestupně seřazené okamžiky bez duplicit.
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
