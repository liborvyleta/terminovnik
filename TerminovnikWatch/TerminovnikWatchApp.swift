import SwiftUI

/// Vstupní bod aplikace Termínovník pro Apple Watch.
///
/// Zobrazuje další hodinu, dnešní rozvrh a nejbližší deadliny. Data posílá aplikace
/// na iPhonu přes WatchConnectivity; přijímá je sdílený ``WatchStore``, jehož relaci
/// aplikace aktivuje při startu.
@main
struct TerminovnikWatchApp: App {
    /// Vytvoří aplikaci a aktivuje WatchConnectivity sdíleného ``WatchStore``.
    init() {
        WatchStore.shared.activate()
    }

    /// Scéna s kořenovou obrazovkou ``WatchRootView`` v jazyce aplikace.
    var body: some Scene {
        WindowGroup {
            WatchRootView(store: .shared)
                .environment(\.locale, .app)
        }
    }
}

/// Kořenová obrazovka aplikace pro Apple Watch.
///
/// Pokud ``WatchStore`` nemá žádná data přijatá z iPhonu, zobrazí výzvu k otevření
/// aplikace na iPhonu. Jinak zobrazí tři stránky přepínané swipem doleva a doprava:
/// další hodinu, dnešní rozvrh a deadliny.
struct WatchRootView: View {
    /// Zdroj dat přijatých z iPhonu.
    let store: WatchStore
    /// Index aktuálně zobrazené stránky.
    @State private var page = Self.initialPage

    /// Index výchozí stránky (0 = další hodina, 1 = dnes, 2 = deadliny).
    ///
    /// V konfiguraci Debug ji lze zvolit argumentem `-page next|today|deadlines`, jinak je to 0.
    private static var initialPage: Int {
        #if DEBUG
        switch DemoLaunch.page {
        case "today": return 1
        case "deadlines": return 2
        default: return 0
        }
        #else
        return 0
        #endif
    }

    /// Obsah obrazovky: výzva k otevření iPhonu, nebo stránkovaný `TabView`.
    var body: some View {
        NavigationStack {
            if store.isEmpty {
                ContentUnavailableView {
                    Label("Termínovník", systemImage: "iphone.gen3")
                } description: {
                    Text("Otevři Termínovník na iPhonu a přihlas se do STAGu.")
                }
            } else {
                TabView(selection: $page) {
                    NextLessonView(store: store)
                        .navigationTitle(Text("Další hodina"))
                        .tag(0)
                    TodayScheduleView(store: store)
                        .navigationTitle(Text("Dnes"))
                        .tag(1)
                    DeadlinesView(store: store)
                        .navigationTitle(Text("Deadliny"))
                        .tag(2)
                }
                // Stránky se přepínají swipem doleva a doprava; korunka posouvá obsah stránky
                .tabViewStyle(.page)
            }
        }
    }
}

#Preview("S daty") {
    WatchRootView(store: WatchStore(timetable: .sample, deadlines: WidgetDeadline.watchSamples))
}

#Preview("Prázdný stav") {
    WatchRootView(store: WatchStore(timetable: nil, deadlines: [], updatedAt: nil))
}
