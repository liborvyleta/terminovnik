import SwiftUI
import SwiftData

/// Kořenový pohled s pěti záložkami: Přehled deadlinů, Rozvrh, Zkoušky, Předměty a Nastavení.
///
/// Zvolená záložka je v `@AppStorage("selectedTab")` – jiné obrazovky na ni mohou přepnout
/// (např. Přehled nastaví „terms“ a otevře Zkoušky). Štítek Zkoušek ukazuje počet nových termínů
/// z `ExamTermStore`. Při prvním spuštění (a dokud uživatel nemá žádný předmět a neběží demo)
/// ukáže úvodní obrazovku s importem ze STAGu, přeskočením a ukázkovým režimem. V ukázkovém
/// režimu zobrazí pruh `DemoBanner`. Je kořenem okna aplikace.
struct ContentView: View {
    /// Příznak, že uživatel prošel úvodní obrazovkou.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Značka zvolené záložky: „dashboard“, „timetable“, „terms“, „subjects“, „settings“.
    @AppStorage("selectedTab") private var selectedTab = "dashboard"
    /// Předměty – bez nich se ukazuje úvodní obrazovka.
    @Query private var subjects: [Subject]
    /// Zobrazení importu ze STAGu nad úvodní obrazovkou.
    @State private var isShowingStagImport = false

    /// Počet nově vypsaných termínů pro štítek na záložce Zkoušky.
    private var newTermsCount: Int {
        ExamTermStore.shared.hasNewTerms ? ExamTermStore.shared.newTermIDs.count : 0
    }

    /// `TabView` s pěti záložkami, pruhem ukázkového režimu a úvodní obrazovkou přes celou obrazovku.
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
        .demoBanner(isActive: DemoMode.isActive && !DemoMode.hidesBanner)
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

    /// Úvodní obrazovka se ukáže, dokud ji uživatel neprojde, nemá žádné předměty a neběží demo.
    private var isShowingOnboarding: Binding<Bool> {
        Binding(
            // V ukázkovém režimu se úvodní obrazovka neukazuje (příznak dokončení se nemění,
            // takže po ukončení dema se uživatel bez dat vrátí na úvodní obrazovku)
            get: { !hasCompletedOnboarding && subjects.isEmpty && !DemoMode.isActive },
            set: { if !$0 && !DemoMode.isActive { hasCompletedOnboarding = true } }
        )
    }
}

/// Pruh „Ukázkový režim“ s tlačítkem pro ukončení.
private extension View {
    /// Přidá pruh ukázkového režimu. Na iOS 26 nad lištou záložek (systémové místo, nic nepřekryje),
    /// na starších verzích nahoře nad obsahem.
    /// - Parameter isActive: zda se má pruh zobrazit.
    /// - Returns: pohled s pruhem, nebo beze změny.
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

/// Pruh „Ukázkový režim – smyšlená data“ s tlačítkem „Ukončit“.
///
/// Klepnutím na „Ukončit“ uživatel opustí ukázkový režim (`DemoController.shared.exit()`).
/// Používá se v `ContentView` přes modifikátor `demoBanner(isActive:)`.
struct DemoBanner: View {
    /// Vlastní pozadí jen mimo lištu záložek (ta má na iOS 26 své sklo).
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
