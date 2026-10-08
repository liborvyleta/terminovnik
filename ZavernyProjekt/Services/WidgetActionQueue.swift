import Foundation
import SwiftData

/// Zpracování akcí z widgetu, které nemohly proběhnout přímo v aplikaci.
///
/// Tlačítko „Označit jako splněné“ (`CompleteDeadlineIntent`) běží díky `LiveActivityIntent`
/// normálně v procesu aplikace a zapisuje rovnou do SwiftData. Kdyby ho systém přesto spustil
/// v rozšíření widgetu, uloží ID do fronty v App Group – tady se fronta dožene.
/// Volat při spuštění aplikace a při návratu do popředí, PŘED `WidgetSync.refresh`
/// (jinak by obnova přehledu vrátila do widgetu deadline, který uživatel už odškrtl).
enum WidgetActionQueue {
    static func processPending() {
        processPending(in: PersistenceController.shared.mainContext)
    }

    static func processPending(in context: ModelContext) {
        let ids = PendingDeadlineCompletions.drain()
        guard !ids.isEmpty else { return }

        var changed = false
        for id in ids where CompleteDeadlineIntent.markCompleted(taskID: id, in: context) {
            changed = true
        }
        if changed {
            TaskService.save(context) // uloží a aktualizuje widget
        }
    }
}
