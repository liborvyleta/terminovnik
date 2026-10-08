import Foundation
import BackgroundTasks
import SwiftData

/// Kontrola termínů a rozvrhu na pozadí (Background App Refresh).
///
/// iOS úlohu spouští podle svého uvážení (podle používání aplikace, baterie a sítě) – typicky
/// několikrát denně, nikoli v přesný čas. Okamžitá upozornění by vyžadovala vlastní server s push notifikacemi.
enum BackgroundRefresh {
    /// Musí odpovídat položce BGTaskSchedulerPermittedIdentifiers v Info.plist
    nonisolated static let taskIdentifier = "cz.liborvyleta.terminovnik.refresh"

    /// Požádá iOS o další kontrolu nejdříve za 20 minut
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Background refresh: naplánování selhalo – \(error.localizedDescription)")
        }
    }

    /// Samotná práce na pozadí: termíny (s upozorněním na nové) a rozvrh
    static func run() async {
        schedule() // hned naplánujeme další běh
        guard StagAccountStore.shared.isConnected else { return }
        let context = PersistenceController.shared.mainContext
        await ExamTermStore.shared.refresh(context: context)
        await GradeStore.shared.refresh()
        await TimetableStore.shared.refreshIfNeeded(context: context)
    }
}
