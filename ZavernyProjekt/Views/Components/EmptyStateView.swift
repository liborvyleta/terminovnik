import SwiftUI

/// Přívětivý prázdný stav: velký SF Symbol v barevných kruzích, nadpis, text a volitelná tlačítka.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    let tint: Color
    let actionTitle: String?
    let actionSymbol: String
    let action: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    /// Spouští jednorázovou „bounce“ animaci ikony po zobrazení
    @State private var hasAppeared = false

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
