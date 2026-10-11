import SwiftUI
import SwiftData

/// Termínovník – chytrý plánovač zkoušek a deadlinů. Vstupní bod aplikace.
@main
struct TerminovnikApp: App {

    /// Aktuální úložiště SwiftData (skutečné, nebo ukázkové v paměti) – lze přepnout za běhu.
    /// Schéma obsahuje oba modely; vazbu Subject ↔ ExamTask SwiftData odvodí z @Relationship.
    @State private var dataController = DemoController.shared
    private var modelContainer: ModelContainer { dataController.container }

    /// Fáze scény – při návratu do popředí obnovíme data widgetu.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Účet STAG načteme hned při startu (včetně přesunu starších údajů do Klíčenky),
        // ne až při prvním otevření obrazovky, která ho potřebuje.
        _ = StagAccountStore.shared

        // Notifikace: banner i při otevřené aplikaci + akce „Splněno“ přímo z oznámení.
        // Musí proběhnout hned při startu, aby delegát zachytil akci i při spuštění na pozadí.
        // Akce „Splněno“ patří vždy ke skutečné připomínce → skutečné úložiště (v demu se připomínky neplánují).
        NotificationManager.shared.configure(modelContainer: PersistenceController.persistent)

        // Ukázkový režim: smyšlená data jen v paměti, žádná síť ani Klíčenka
        let modelContainer = DemoController.shared.container
        DemoController.shared.prepareAtLaunch()

        #if DEBUG
        // Pomůcka pro testování: argument -seedSampleData naplní prázdnou databázi ukázkovými daty.
        if CommandLine.arguments.contains("-seedSampleData") {
            SampleData.insertIfEmpty(into: modelContainer.mainContext)
        }
        #endif

        // Starší připomínky přeplánujeme, aby dostaly tlačítko „Splněno“.
        NotificationManager.shared.rescheduleAll(in: modelContainer.mainContext)
        // Spojení s Apple Watch – hodinky dostávají deadliny a rozvrh.
        WatchSync.shared.activate()
        // Deadliny odškrtnuté ve widgetu (záložní fronta) zpracujeme dřív, než se přehled přepíše.
        WidgetActionQueue.processPending(in: modelContainer.mainContext)
        #if ICLOUD_SYNC
        // Se synchronizací přes iCloud mohou STAG importy na dvou zařízeních vytvořit duplicity
        if !DemoMode.isActive { _ = try? BackupService.removeStagDuplicates(in: modelContainer.mainContext) }
        #endif
        // Widget dostane aktuální přehled hned po spuštění.
        WidgetSync.refresh(from: modelContainer.mainContext)
        // Připomínky hodin z uloženého rozvrhu (plánují se jen na pár dní dopředu).
        ClassReminderScheduler.shared.reschedule()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // DatePicker a formátování dat se řídí jazykem aplikace.
                .environment(\.locale, .czech)
                // onChange(of: scenePhase) se při studeném startu nevyvolá – obnovu spustíme i tady
                .task { appBecameActive() }
                // Obnova zálohy: soubor .terminovnik otevřený z aplikace Soubory nebo z Nastavení
                .backupRestoreHandler()
                // Vloží kontejner do prostředí → všechna View mají přístup k @Query a modelContext.
                // Po přepnutí ukázkového režimu se celý strom sestaví znovu nad novým úložištěm.
                .modelContainer(modelContainer)
                .id(dataController.generation)
        }
        // Po návratu do popředí (např. po odškrtnutí z oznámení nebo změně dne) obnovíme widget.
        // Kontrola termínů na pozadí – iOS ji spouští podle svého uvážení
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { appBecameActive() }
        }
    }

    /// Spuštění aplikace nebo návrat do popředí: obnova widgetu, rozvrhu, termínů a připomínek
    private func appBecameActive() {
        let context = modelContainer.mainContext
        WidgetActionQueue.processPending(in: context)
        WidgetSync.refresh(from: context)
        // Rozvrh ze STAGu obnovíme, pokud je starší než pár hodin (jen s přihlášeným účtem)
        Task { await TimetableStore.shared.refreshIfNeeded(context: context) }
        // Termíny zkoušek – nové termíny ohlásí oznámením hned po otevření
        Task { await ExamTermStore.shared.refreshIfNeeded(context: context) }
        // Známky – nová známka se ohlásí oznámením
        Task { await GradeStore.shared.refreshIfNeeded() }
        // Naplánujeme další kontrolu na pozadí
        BackgroundRefresh.schedule()
        // Připomínky hodin posuneme o další dny a Live Activity sladíme s aktuální hodinou
        ClassReminderScheduler.shared.reschedule()
        LiveActivityManager.shared.updateLessonActivity()
    }
}
