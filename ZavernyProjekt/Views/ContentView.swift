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
        // Ukázkový režim: nenápadný pruh viditelný na všech záložkách
        .demoBanner(isActive: DemoMode.isActive)
        .fullScreenCover(isPresented: isShowingOnboarding) {
            OnboardingView(
                onImportFromStag: { isShowingStagImport = true },
                onSkip: { hasCompletedOnboarding = true },
                onTryDemo: { DemoController.shared.enter() }
            )
            .sheet(isPresented: $isShowingStagImport) {
                StagImportView { _ in hasCompletedOnboarding = true }
            }
        }
    }

    /// Úvodní obrazovka se ukáže, dokud ji uživatel neprojde a nemá žádné předměty
    private var isShowingOnboarding: Binding<Bool> {
        Binding(
            // V ukázkovém režimu se úvodní obrazovka neukazuje (příznak dokončení se nemění,
            // takže po ukončení dema se uživatel bez dat vrátí na úvodní obrazovku)
            get: { !hasCompletedOnboarding && subjects.isEmpty && !DemoMode.isActive },
            set: { if !$0 && !DemoMode.isActive { hasCompletedOnboarding = true } }
        )
    }
}

/// Pruh „Ukázkový režim“ s tlačítkem pro ukončení
private extension View {
    /// Na iOS 26 pruh nad lištou záložek (systémové místo, nic nepřekryje),
    /// na starších verzích nahoře nad obsahem.
    @ViewBuilder
    func demoBanner(isActive: Bool) -> some View {
        if !isActive {
            self
        } else if #available(iOS 26.0, *) {
            tabViewBottomAccessory { DemoBanner(usesBar: false) }
        } else {
            safeAreaInset(edge: .top, spacing: 0) { DemoBanner(usesBar: true) }
        }
    }
}

struct DemoBanner: View {
    /// Vlastní pozadí jen mimo lištu záložek (ta má na iOS 26 své sklo)
    var usesBar = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .foregroundStyle(.orange)
            Text("Ukázkový režim – smyšlená data")
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button("Ukončit") {
                DemoController.shared.exit()
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(usesBar ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
        .accessibilityElement(children: .contain)
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
