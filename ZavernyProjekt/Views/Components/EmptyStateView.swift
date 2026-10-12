import SwiftUI

/// Přívětivý prázdný stav: velký SF Symbol v barevných kruzích, nadpis, text a volitelná tlačítka.
///
/// Obsah dostává zvenku přes parametry; po zobrazení ikona jednou „poskočí“. Uživatel může klepnout
/// na hlavní tlačítko (`action`) a volitelné vedlejší tlačítko (`secondaryAction`). Používá se
/// na Přehledu, v Rozvrhu, Zkouškách, Známkách, seznamu a detailu předmětů.
struct EmptyStateView: View {
    /// Název SF Symbolu uprostřed kruhů.
    let symbol: String
    /// Nadpis prázdného stavu.
    let title: String
    /// Vysvětlující text pod nadpisem.
    let message: String
    /// Barva ikony a kruhů.
    let tint: Color
    /// Text hlavního tlačítka; `nil` = bez tlačítka.
    let actionTitle: String?
    /// SF Symbol hlavního tlačítka.
    let actionSymbol: String
    /// Akce hlavního tlačítka.
    let action: (() -> Void)?
    /// Text vedlejšího tlačítka; `nil` = bez tlačítka.
    let secondaryActionTitle: String?
    /// Akce vedlejšího tlačítka.
    let secondaryAction: (() -> Void)?

    /// Spouští jednorázovou „bounce“ animaci ikony po zobrazení.
    @State private var hasAppeared = false

    /// Vytvoří prázdný stav.
    /// - Parameters:
    ///   - symbol: název SF Symbolu
    ///   - title: nadpis
    ///   - message: vysvětlující text
    ///   - tint: barva ikony a kruhů
    ///   - actionTitle: text hlavního tlačítka (tlačítko se ukáže jen spolu s `action`)
    ///   - actionSymbol: SF Symbol hlavního tlačítka
    ///   - action: akce hlavního tlačítka
    ///   - secondaryActionTitle: text vedlejšího tlačítka (ukáže se jen spolu se `secondaryAction`)
    ///   - secondaryAction: akce vedlejšího tlačítka
    init(
        symbol: String,
        title: String,
        message: String,
        tint: Color = .accentColor,
        actionTitle: String? = nil,
        actionSymbol: String = "plus",
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.tint = tint
        self.actionTitle = actionTitle
        self.actionSymbol = actionSymbol
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    /// Svislý sloupec: ikona v kruzích, nadpis s textem a volitelná tlačítka.
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.08))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 108, height: 108)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: hasAppeared)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbol)
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .onAppear { hasAppeared = true }
    }
}

#Preview {
    EmptyStateView(
        symbol: "calendar.badge.plus",
        title: "Zatím žádné deadliny",
        message: "Přidej první zkoušku nebo úkol.",
        actionTitle: "Přidat deadline",
        action: {}
    )
}
