import SwiftUI
import SwiftData

/// Termínovník – chytrý plánovač zkoušek a deadlinů. Vstupní bod aplikace.
@main
struct TerminovnikApp: App {

    /// Sdílený ModelContainer = jediné úložiště SwiftData pro celou aplikaci.
    /// Schéma obsahuje oba modely; vazbu Subject ↔ ExamTask SwiftData odvodí z @Relationship.
    let modelContainer: ModelContainer = PersistenceController.shared

    /// Fáze scény – při návratu do popředí obnovíme data widgetu.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Notifikace: banner i při otevřené aplikaci + akce „Splněno“ přímo z oznámení.
        // Musí proběhnout hned při startu, aby delegát zachytil akci i při spuštění na pozadí.
        NotificationManager.shared.configure(modelContainer: modelContainer)

        #if DEBUG
        // Pomůcka pro testování: argument -seedSampleData naplní prázdnou databázi ukázkovými daty.
        if CommandLine.arguments.contains("-seedSampleData") {
            SampleData.insertIfEmpty(into: modelContainer.mainContext)
        }
        #endif

        // Starší připomínky přeplánujeme, aby dostaly tlačítko „Splněno“.
        NotificationManager.shared.rescheduleAll(in: modelContainer.mainContext)
        // Widget dostane aktuální přehled hned po spuštění.
        WidgetSync.refresh(from: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // DatePicker a formátování procent se řídí českou lokalizací.
                .environment(\.locale, .czech)
        }
        // Vloží kontejner do prostředí → všechna View mají přístup k @Query a modelContext.
        .modelContainer(modelContainer)
        // Po návratu do popředí (např. po odškrtnutí z oznámení nebo změně dne) obnovíme widget.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                WidgetSync.refresh(from: modelContainer.mainContext)
            }
        }
    }
}
