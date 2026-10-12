import SwiftUI

/// Tři souhrnné kartičky v horní části Dashboardu.
///
/// Zobrazuje počet aktivních deadlinů, deadlinů do 7 dní a po termínu z `DashboardStats`
/// (počítá `DashboardViewModel`). Nemá akce; používá se v `DashboardView`.
struct StatsHeaderView: View {
    /// Souhrnné počty deadlinů.
    let stats: DashboardStats

    var body: some View {
        HStack(spacing: 10) {
            StatCard(value: stats.active, title: String(localized: "Aktivní"), symbol: "list.bullet.circle.fill", color: .accentColor)
            StatCard(value: stats.thisWeek, title: String(localized: "Do 7 dní"), symbol: "hourglass.circle.fill", color: .orange)
            StatCard(value: stats.overdue, title: String(localized: "Po termínu"), symbol: "exclamationmark.circle.fill", color: .red)
        }
    }
}
