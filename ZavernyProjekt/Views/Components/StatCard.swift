import SwiftUI

/// Malá souhrnná kartička s číslem (např. „3 · Po termínu“).
///
/// Zobrazuje symbol, hodnotu a popisek; data dostává zvenku. Nemá akce; používá se v hlavičce
/// Přehledu (`StatsHeaderView`) a v seznamu předmětů.
struct StatCard: View {
    /// Zobrazené číslo.
    let value: Int
    /// Popisek pod číslem.
    let title: String
    /// SF Symbol kartičky.
    let symbol: String
    /// Barva symbolu.
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.title.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
