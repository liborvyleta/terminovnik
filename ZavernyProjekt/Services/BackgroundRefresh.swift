import Foundation
import BackgroundTasks
import SwiftData

/// Kontrola termínů a rozvrhu na pozadí (Background App Refresh).
///
/// iOS úlohu spouští podle svého uvážení (podle používání aplikace, baterie a sítě) – typicky
/// několikrát denně, nikoli v přesný čas. Okamžitá upozornění by vyžadovala vlastní server s push notifikacemi.
/// Úlohu registruje aplikace při startu; samotná práce obnoví ``ExamTermStore``, ``GradeStore``
/// a ``TimetableStore`` nad hlavním kontextem ``PersistenceController/shared``.
enum BackgroundRefresh {
    /// Musí odpovídat položce BGTaskSchedulerPermittedIdentifiers v Info.plist
    nonisolated static let taskIdentifier = "cz.liborvyleta.terminovnik.refresh"

    /// Požádá iOS o další kontrolu nejdříve za 20 minut.
    ///
    /// Selhání odeslání požadavku (např. v simulátoru nebo bez povoleného Background App Refresh)
    /// se jen vypíše do konzole.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Background refresh: naplánování selhalo – \(error.localizedDescription)")
        }
    }

    /// Samotná práce na pozadí: termíny a známky (s upozorněním na nové) a rozvrh.
    ///
    /// Asynchronně postupně obnoví termíny, známky a rozvrh (ten jen pokud je zastaralý).
    /// Nejdřív vždy naplánuje další běh pomocí ``schedule()``.
    /// - Note: V ukázkovém režimu nebo bez přihlášení do IS/STAG se nic nenačítá ani neukládá.
    static func run() async {
        schedule() // hned naplánujeme další běh
        // Ukázkový režim: na pozadí se nic nenačítá ani neukládá
        guard !DemoMode.isActive, StagAccountStore.shared.isConnected else { return }
        let context = PersistenceController.shared.mainContext
        await ExamTermStore.shared.refresh(context: context)
        await GradeStore.shared.refresh()
        await TimetableStore.shared.refreshIfNeeded(context: context)
    }
}
