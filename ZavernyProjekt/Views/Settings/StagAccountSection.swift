import SwiftUI
import SwiftData

/// Sekce „Účet IS/STAG“ pro obrazovku Nastavení – vkládá se přímo do `Form`.
///
/// Připojeno: údaje o studentovi, aktualizace předmětů ze STAGu (bez nového přihlášení)
/// a odhlášení. Nepřipojeno: krátké vysvětlení a přihlášení přes `StagImportView`.
struct StagAccountSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: StagAccountViewModel
    @State private var showsLogin = false
    @State private var confirmsSignOut = false

    init() {
        _viewModel = State(initialValue: StagAccountViewModel())
    }

    /// Pro náhledy s připraveným stavem
    init(viewModel: StagAccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if DemoMode.isActive {
            demoSection
        } else {
            accountSection
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        // Hlavní sekce existuje v obou stavech, proto na její hlavičce visí sheet přihlášení:
        // po přihlášení se obsah přepne na „připojeno“, ale otevřený import se nezavře.
        Section {
            if let account = viewModel.account {
                accountRows(account)
            } else {
                disconnectedRows
            }
        } header: {
            Text("Účet IS/STAG")
                .sheet(isPresented: $showsLogin) {
                    StagImportView()
                }
        } footer: {
            if viewModel.isConnected {
                Text("Přihlášení platí až 90 dní, potom se stačí přihlásit znovu.")
            } else {
                Text("Heslo zadáváš přímo na stránce STAGu – aplikace ho nikdy neuvidí.")
            }
        }

        if viewModel.isConnected {
            actionsSection
        }
    }

    // MARK: - Připojený účet

    @ViewBuilder
    private func accountRows(_ account: StagAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.fullName.isEmpty ? account.stagUser : account.fullName)
                    .font(.headline)
                Label("Připojeno", systemImage: "checkmark.circle.fill")
                    .labelStyle(.compact)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)

        LabeledContent("Škola", value: account.resolvedSchool.name)
        LabeledContent("Osobní číslo", value: account.osCislo)

        if let faculty = account.faculty, !faculty.isEmpty {
            LabeledContent("Fakulta", value: faculty)
        }

        LabeledContent(
            "Připojeno od",
            value: account.connectedAt.formatted(.dateTime.day().month(.wide).year().locale(.czech))
        )

        // TimelineView – relativní čas („před 5 minutami“) se průběžně překresluje
        TimelineView(.periodic(from: .now, by: 30)) { context in
            LabeledContent("Naposledy aktualizováno", value: lastSyncText(account.lastSyncAt, now: context.date))
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await viewModel.sync(context: modelContext) }
            } label: {
                HStack {
                    Label("Aktualizovat předměty ze STAGu", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if viewModel.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isSyncing)

            statusRow

            Button(role: .destructive) {
                confirmsSignOut = true
            } label: {
                Label("Odhlásit ze STAGu", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .confirmationDialog("Odhlásit ze STAGu?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Odhlásit", role: .destructive) {
                    viewModel.signOut()
                }
            } message: {
                Text("Předměty a úkoly v aplikaci zůstanou. Pro další aktualizaci se budeš muset znovu přihlásit.")
            }
        } footer: {
            Text("Načte předměty zapsané v aktuálním semestru: nové přidá, u stávajících upraví název a kredity. Nic nemaže.")
        }
    }

    /// Výsledek poslední aktualizace nebo chyba
    @ViewBuilder
    private var statusRow: some View {
        switch viewModel.state {
        case .finished(let result):
            Label(result.summary, systemImage: result.total == 0 ? "info.circle.fill" : "checkmark.circle.fill")
                .labelStyle(.compact(spacing: 6))
                .font(.footnote)
                .foregroundStyle(result.total == 0 ? Color.secondary : Color.green)
        case .failed(let message):
            errorRow(message)
        case .idle, .syncing:
            EmptyView()
        }
    }

    // MARK: - Nepřipojeno

    @ViewBuilder
    private var disconnectedRows: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.secondary.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Nepřipojeno")
                    .font(.headline)
                Text("Přihlas se školním účtem a předměty, které máš zapsané ve STAGu, půjde kdykoli aktualizovat jedním klepnutím.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)

        // Např. vypršené přihlášení při poslední aktualizaci
        if case .failed(let message) = viewModel.state {
            errorRow(message)
        }

        Button {
            showsLogin = true
        } label: {
            Label("Přihlásit se do IS/STAG", systemImage: "person.badge.key")
        }

        Button {
            DemoController.shared.enter()
        } label: {
            Label("Vyzkoušet s ukázkovými daty", systemImage: "sparkles.rectangle.stack")
        }
    }

    // MARK: - Ukázkový režim

    private var demoSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ukázkový režim")
                        .font(.headline)
                    Text("Smyšlená data, bez připojení ke STAGu")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            Button(role: .destructive) {
                DemoController.shared.exit()
            } label: {
                Label("Ukončit ukázkový režim", systemImage: "xmark.circle")
            }
        } header: {
            Text("Účet IS/STAG")
        } footer: {
            Text("Změny v ukázkovém režimu se neukládají. Tvoje skutečná data, účet i připomínky zůstávají beze změny.")
        }
    }

    // MARK: - Pomocné

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .labelStyle(.compact(spacing: 6))
            .font(.footnote)
            .foregroundStyle(.red)
    }

    /// „před 5 minutami“, „včera“… nebo „Zatím nikdy“
    private func lastSyncText(_ date: Date?, now: Date) -> String {
        guard let date else { return String(localized: "Zatím nikdy") }
        if now.timeIntervalSince(date) < 60 { return String(localized: "právě teď") }
        return date.formatted(
            Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: .czech)
        )
    }
}

#if DEBUG
#Preview("Připojeno") {
    Form {
        StagAccountSection(viewModel: .previewConnected)
    }
    .modelContainer(SampleData.previewContainer)
}

#Preview("Nepřipojeno") {
    Form {
        StagAccountSection(viewModel: .previewDisconnected)
    }
    .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
#endif
