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

    var body: some View {
        NavigationStack {
            if store.isEmpty {
                ContentUnavailableView {
                    Label("Termínovník", systemImage: "iphone.gen3")
                } description: {
                    Text("Otevři Termínovník na iPhonu a přihlas se do STAGu.")
                }
            } else {
                TabView {
                    NextLessonView(store: store)
                        .navigationTitle(Text("Další hodina"))
                    TodayScheduleView(store: store)
                        .navigationTitle(Text("Dnes"))
                    DeadlinesView(store: store)
                        .navigationTitle(Text("Deadliny"))
                }
                .tabViewStyle(.verticalPage)
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
