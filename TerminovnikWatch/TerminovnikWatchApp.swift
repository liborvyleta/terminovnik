import SwiftUI

/// Termínovník pro Apple Watch – další hodina, dnešní rozvrh a nejbližší deadliny.
/// Data posílá aplikace na iPhonu přes WatchConnectivity (`WatchStore`).
@main
struct TerminovnikWatchApp: App {
    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: .shared)
                .environment(\.locale, .app)
        }
    }
}

/// Kořenová obrazovka: svislé stránky (watchOS 10), nebo výzva k otevření aplikace na iPhonu.
struct WatchRootView: View {
    let store: WatchStore
    @State private var page = Self.initialPage

    /// Výchozí stránka; v Debug ji lze zvolit argumentem `-page next|today|deadlines`
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
