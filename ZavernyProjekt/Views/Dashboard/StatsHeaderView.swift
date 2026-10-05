import SwiftUI

/// Tři souhrnné kartičky v horní části Dashboardu.
struct StatsHeaderView: View {
    let stats: DashboardStats

    var body: some View {
        HStack(spacing: 10) {
            StatCard(value: stats.active, title: "Aktivní", symbol: "list.bullet.circle.fill", color: .accentColor)
            StatCard(value: stats.thisWeek, title: "Do 7 dní", symbol: "hourglass.circle.fill", color: .orange)
            StatCard(value: stats.overdue, title: "Po termínu", symbol: "exclamationmark.circle.fill", color: .red)
        }
    }
}
