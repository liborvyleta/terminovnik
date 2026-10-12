// Interaktivní widget „Nejbližší deadliny“ (iOS 17 `Button(intent:)`).
// Soubor se kompiluje do aplikace, widgetu i hodinek – na watchOS je celý vynechaný.
#if os(iOS)
import AppIntents
import Foundation
import WidgetKit
#if !WIDGET_EXTENSION
import SwiftData
#endif

/// „Označit jako splněné“ – tlačítko u deadlinu v interaktivním widgetu na ploše.
///
/// Díky `LiveActivityIntent` systém spustí `perform()` v procesu APLIKACE (v případě potřeby ji
/// probudí na pozadí), takže intent může zapsat přímo do SwiftData – widget k databázi přístup nemá.
/// Ve widgetu se tak tělo `perform()` za normálních okolností vůbec nevolá; kdyby přesto běželo
/// v rozšíření, použije se záložní fronta v App Group (viz `PendingDeadlineCompletions`).
struct CompleteDeadlineIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Označit deadline jako splněný"
    static let description = IntentDescription("Označí deadline jako splněný přímo z widgetu na ploše.")
    /// Akce jen pro tlačítko widgetu – nenabízí se ve Zkratkách ani ve Spotlightu.
    static let isDiscoverable: Bool = false
    static let openAppWhenRun: Bool = false

    /// UUID úkolu (`ExamTask.id`) jako text – widget zná jen `WidgetDeadline.id`.
    @Parameter(title: "ID deadlinu")
    var taskID: String

    /// Prázdný inicializátor vyžadovaný protokolem `AppIntent`.
    init() {}

    /// Vytvoří akci pro deadline zadaný textovým ID.
    /// - Parameter taskID: UUID úkolu jako text.
    init(taskID: String) {
        self.taskID = taskID
    }

    /// Vytvoří akci pro deadline zadaný UUID.
    /// - Parameter deadlineID: Identifikátor úkolu (`WidgetDeadline.id`).
    init(deadlineID: UUID) {
        self.taskID = deadlineID.uuidString
    }

    /// Označí deadline jako splněný.
    ///
    /// V aplikaci zapíše změnu do SwiftData a obnoví widget; v ukázkovém režimu nebo v rozšíření
    /// widgetu zařadí ID do záložní fronty a deadline jen skryje z uloženého přehledu.
    /// - Returns: Prázdný výsledek.
    @MainActor
    func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        // Záloha pro případ, že by systém intent spustil v rozšíření widgetu:
        // ID uložíme do fronty (aplikace ji zpracuje při spuštění) a deadline hned skryjeme z přehledu.
        PendingDeadlineCompletions.enqueue(taskID)
        if let uuid = UUID(uuidString: taskID) {
            WidgetSnapshot.removeDeadline(id: uuid)
        }
        WidgetCenter.shared.reloadAllTimelines()
        #else
        // Ukázkový režim: widget ukazuje skutečné deadliny, ale aplikace běží nad demo daty →
        // odškrtnutí se zařadí do fronty a zpracuje se nad skutečnou databází po ukončení dema.
        if DemoMode.isActive {
            PendingDeadlineCompletions.enqueue(taskID)
            if let uuid = UUID(uuidString: taskID) {
                WidgetSnapshot.removeDeadline(id: uuid)
            }
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        let context = PersistenceController.shared.mainContext
        if Self.markCompleted(taskID: taskID, in: context) {
            TaskService.save(context) // uloží, přepíše přehled widgetu a zavolá reloadAllTimelines
        }
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
extension CompleteDeadlineIntent {
    /// Označí úkol jako splněný a zruší jeho připomínku. Neukládá – to udělá volající.
    /// - Parameters:
    ///   - taskID: UUID úkolu jako text.
    ///   - context: Kontext, ve kterém se úkol hledá.
    /// - Returns: `true`, pokud se úkol našel a změnil (byl nesplněný).
    @MainActor
    static func markCompleted(taskID: String, in context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: taskID) else { return false }

        var descriptor = FetchDescriptor<ExamTask>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        guard let task = try? context.fetch(descriptor).first, !task.isCompleted else { return false }

        task.isCompleted = true
        NotificationManager.shared.cancelReminder(for: task)
        return true
    }
}
#endif

// MARK: - Záložní fronta v App Group

/// ID deadlinů označených ve widgetu, které ještě aplikace nezapsala do databáze.
///
/// Ukládá se v App Group (`AppGroup.defaults`), takže ji sdílí aplikace i widget. Plní se jen tehdy, když intent běží v rozšíření widgetu; vyprazdňuje ji aplikace
/// (`WidgetActionQueue.processPending`).
nonisolated enum PendingDeadlineCompletions {
    private static let storageKey = "widgetPendingCompletions.v1"

    /// Čekající ID (bez duplicit, v pořadí přidání); prázdné, pokud App Group není dostupná.
    static var pending: [String] {
        AppGroup.defaults?.stringArray(forKey: storageKey) ?? []
    }

    /// Přidá ID do fronty, pokud v ní ještě není.
    /// - Parameter taskID: UUID úkolu jako text.
    static func enqueue(_ taskID: String) {
        var ids = pending
        guard !ids.contains(taskID) else { return }
        ids.append(taskID)
        AppGroup.defaults?.set(ids, forKey: storageKey)
    }

    /// Vrátí čekající ID a frontu vyprázdní.
    /// - Returns: ID v pořadí přidání.
    static func drain() -> [String] {
        let ids = pending
        if !ids.isEmpty {
            AppGroup.defaults?.removeObject(forKey: storageKey)
        }
        return ids
    }
}

nonisolated extension WidgetSnapshot {
    /// Odebere deadline z uloženého přehledu (okamžitá odezva widgetu bez přístupu k databázi).
    ///
    /// Přehled se uloží jen tehdy, když se deadline v něm opravdu našel.
    /// - Parameter id: Identifikátor odebíraného deadlinu.
    static func removeDeadline(id: UUID) {
        guard var snapshot = load() else { return }
        let count = snapshot.deadlines.count
        snapshot.deadlines.removeAll { $0.id == id }
        guard snapshot.deadlines.count != count else { return }
        snapshot.save()
    }
}
#endif
