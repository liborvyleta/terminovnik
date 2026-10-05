import SwiftUI
import SwiftData

/// Kořenový pohled se třemi záložkami: Přehled deadlinů, Předměty a Nastavení.
/// Při prvním spuštění (a dokud uživatel nemá žádný předmět) ukáže úvodní obrazovku.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var subjects: [Subject]
    @State private var isShowingStagImport = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Přehled", systemImage: "calendar.badge.clock") }

            SubjectsListView()
                .tabItem { Label("Předměty", systemImage: "books.vertical.fill") }

            SettingsView()
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
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
