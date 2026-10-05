import SwiftUI
import SwiftData

/// Kořenový pohled s pěti záložkami: Přehled deadlinů, Rozvrh, Zkoušky, Předměty a Nastavení.
/// Zvolená záložka je v `@AppStorage("selectedTab")` – jiné obrazovky na ni mohou přepnout
/// (např. Přehled nastaví „terms“ a otevře Zkoušky).
/// Při prvním spuštění (a dokud uživatel nemá žádný předmět) ukáže úvodní obrazovku.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Značka zvolené záložky: „dashboard“, „timetable“, „terms“, „subjects“, „settings“
    @AppStorage("selectedTab") private var selectedTab = "dashboard"
    @Query private var subjects: [Subject]
    @State private var isShowingStagImport = false

    /// Počet nově vypsaných termínů pro štítek na záložce Zkoušky
    private var newTermsCount: Int {
        ExamTermStore.shared.hasNewTerms ? ExamTermStore.shared.newTermIDs.count : 0
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Přehled", systemImage: "calendar.badge.clock") }
                .tag("dashboard")

            TimetableView()
                .tabItem { Label("Rozvrh", systemImage: "calendar.day.timeline.left") }
                .tag("timetable")

            ExamTermsView()
                .tabItem { Label("Zkoušky", systemImage: "graduationcap") }
                .tag("terms")
                .badge(newTermsCount)

            SubjectsListView()
                .tabItem { Label("Předměty", systemImage: "books.vertical.fill") }
                .tag("subjects")

            SettingsView()
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
                .tag("settings")
        }
        .fullScreenCover(isPresented: isShowingOnboarding) {
            OnboardingView(
                onImportFromStag: { isShowingStagImport = true },
                onSkip: { hasCompletedOnboarding = true }
            )
            .sheet(isPresented: $isShowingStagImport) {
                StagImportView { _ in hasCompletedOnboarding = true }
            }
        }
    }

    /// Úvodní obrazovka se ukáže, dokud ji uživatel neprojde a nemá žádné předměty
    private var isShowingOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding && subjects.isEmpty },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }
}

#Preview("S daty") {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}

#Preview("První spuštění") {
    ContentView()
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
