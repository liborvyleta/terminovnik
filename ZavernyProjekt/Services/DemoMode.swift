import Foundation
import SwiftData
import Observation

/// Ukázkový režim se smyšlenými daty – pro vyzkoušení bez školního účtu (i pro App Review).
///
/// Zapíná se tlačítkem „Vyzkoušet s ukázkovými daty“ (trvalý příznak v UserDefaults),
/// v DEBUG buildu také argumentem `-demo` (screenshoty, spolu s `-tab` a `-timetableMode`).
///
/// V demu se nic nezapisuje do skutečné databáze, App Group, Klíčenky ani do plánovaných oznámení –
/// každé takové místo se ptá na `DemoMode.isActive`.
nonisolated enum DemoMode {
    /// Klíč trvalého příznaku v `UserDefaults.standard`
    static let defaultsKey = "demoModeActive"

    /// Běží aplikace v ukázkovém režimu?
    /// Režim pro pořizování snímků obrazovky (argument `-screenshots`, jen Debug): skryje banner ukázkového režimu.
    static var hidesBanner: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-screenshots")
        #else
        false
        #endif
    }

    static var isActive: Bool {
        isActive(defaults: .standard, arguments: ProcessInfo.processInfo.arguments)
    }

    /// Čistá funkce pro testy: příznak v daném úložišti, nebo (jen DEBUG) argument `-demo`
    static func isActive(defaults: UserDefaults, arguments: [String]) -> Bool {
        if defaults.bool(forKey: defaultsKey) { return true }
        #if DEBUG
        if arguments.contains("-demo") { return true }
        #endif
        return false
    }

    /// Nastaví trvalý příznak (sám o sobě nic nepřepíná – použij `DemoController`)
    static func setFlag(_ active: Bool, defaults: UserDefaults = .standard) {
        if active {
            defaults.set(true, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    #if DEBUG
    /// Hodnota argumentu za daným přepínačem (např. `-tab terms` → „terms“)
    static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    #endif
}

/// Přepínání mezi skutečnými daty a ukázkovým režimem za běhu (bez restartu aplikace).
///
/// Kořenová scéna používá `container` a `generation` (`.modelContainer` + `.id`), takže se po přepnutí
/// celý strom pohledů sestaví znovu nad správným úložištěm.
@Observable
final class DemoController {
    static let shared = DemoController()

    /// Aktuální úložiště SwiftData (skutečné, nebo demo v paměti)
    private(set) var container: ModelContainer
    /// Zvýší se při každém přepnutí → `.id(generation)` znovu vytvoří celý strom
    private(set) var generation = 0

    var isActive: Bool { DemoMode.isActive }

    private init() {
        container = PersistenceController.shared
    }

    /// Při startu aplikace v demu naplní demo úložiště a STAG úložiště
    func prepareAtLaunch() {
        guard DemoMode.isActive else { return }
        DemoData.prepare(container: container)
    }

    /// Zapne ukázkový režim. Skutečná data, Klíčenka i naplánované připomínky zůstanou beze změny.
    func enter() {
        guard !DemoMode.isActive else { return }
        // Živou aktivitu skutečné hodiny ukončíme – v demu by neodpovídala; po ukončení dema se obnoví
        LiveActivityManager.shared.endAll()
        DemoMode.setFlag(true)
        PersistenceController.resetDemoContainer()
        container = PersistenceController.shared
        DemoData.prepare(container: container)
        generation += 1
    }

    /// Ukončí ukázkový režim: zahodí demo data a vrátí skutečný účet, cache a připomínky.
    func exit() {
        guard DemoMode.isActive else { return }
        DemoMode.setFlag(false)
        // Pokud běží s argumentem -demo (DEBUG), příznak nestačí – režim zůstane zapnutý
        guard !DemoMode.isActive else { return }

        PersistenceController.resetDemoContainer()
        container = PersistenceController.shared

        // Skutečný účet z Klíčenky a skutečná cache z App Group
        StagAccountStore.shared.reloadAfterDemo()
        TimetableStore.shared.reloadAfterDemo()
        ExamTermStore.shared.reloadAfterDemo()
        GradeStore.shared.reloadAfterDemo()
        BuildingStore.shared.reloadAfterDemo()

        // Připomínky, widget, hodinky a živá aktivita podle skutečných dat
        let context = container.mainContext
        NotificationManager.shared.rescheduleAll(in: context)
        ClassReminderScheduler.shared.reschedule()
        WidgetActionQueue.processPending(in: context)
        WidgetSync.refresh(from: context)
        LiveActivityManager.shared.updateLessonActivity()
        generation += 1
    }
}
