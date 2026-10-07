import SwiftUI

/// Úvodní obrazovka při prvním spuštění – představí aplikaci a nabídne import předmětů ze STAGu.
struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onImportFromStag: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AppLogoView(variant: colorScheme == .dark ? .dark : .light)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    .padding(.top, 48)

                Text("Termínovník")
                    .font(.largeTitle.bold())
                    .padding(.top, 20)
                Text("Chytrý plánovač zkoušek a deadlinů")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 24) {
                    FeatureRow(symbol: "building.columns.fill", color: .indigo,
                               title: "Tvoje předměty ze STAGu",
                               text: "Přihlas se školním účtem a načti si jen předměty, které máš zapsané.")
                    FeatureRow(symbol: "hourglass", color: .orange,
                               title: "Odpočet do termínu",
                               text: "Hned vidíš, co hoří dnes, zítra a tento týden.")
                    FeatureRow(symbol: "bell.badge.fill", color: .red,
                               title: "Připomínka den předem",
                               text: "Na žádnou zkoušku ani odevzdání projektu nezapomeneš.")
                }
                .padding(.top, 40)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Tlačítka zůstávají dole i na menších displejích
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onImportFromStag) {
                    Label("Načíst předměty ze STAGu", systemImage: "person.badge.key.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Pokračovat bez přihlášení", action: onSkip)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .background(Color(.systemBackground))
    }
}

/// Jeden řádek s výhodou aplikace
private struct FeatureRow: View {
    let symbol: String
    let color: Color
    /// LocalizedStringKey – literály z volání se přeloží ze String Catalogu
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView(onImportFromStag: {}, onSkip: {})
}
