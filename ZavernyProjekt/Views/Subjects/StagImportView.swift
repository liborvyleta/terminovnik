import SwiftUI
import SwiftData
import AuthenticationServices

/// Import předmětů z IS/STAG UTB. Po přihlášení školním účtem načte jen předměty,
/// které má student zapsané, a nechá ho vybrat, které si přidá do aplikace.
/// Připojený účet si aplikace pamatuje, takže příště se předměty načtou rovnou.
struct StagImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// Systémová služba pro přihlášení přes web (ASWebAuthenticationSession)
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Query private var subjects: [Subject]

    @State private var viewModel: StagImportViewModel
    /// Zadání vlastní adresy školy
    @State private var isEnteringCustomSchool = false
    @State private var customSchoolAddress = ""
    @State private var customSchoolError: String?
    /// Zásady ochrany osobních údajů (odkaz pod přihlášením)
    @State private var isShowingPrivacyPolicy = false
    /// Volá se po úspěšném importu (např. úvodní obrazovka se pak zavře)
    private let onImported: ((Int) -> Void)?

    init(viewModel: StagImportViewModel = StagImportViewModel(), onImported: ((Int) -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoggedIn {
                    accountSection
                    statusSection
                    resultsSection
                } else {
                    schoolSection
                    loginSection
                    statusSection
                }
            }
            .navigationTitle("Import ze STAGu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                if viewModel.isLoggedIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(viewModel.selectedCount > 0 ? "Přidat (\(viewModel.selectedCount))" : "Přidat") {
                            Task {
                                let imported = await viewModel.importSelected(into: modelContext)
                                guard imported > 0 else { return }
                                onImported?(imported)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(viewModel.selectedCount == 0 || viewModel.isLoading)
                    }
                }
            }
            .task {
                viewModel.configure(existingSubjects: subjects)
                // Připojený účet → rovnou načte zapsané předměty, jinak jen aktuální semestr
                await viewModel.start()
            }
            .sheet(isPresented: $isShowingPrivacyPolicy) {
                NavigationStack {
                    PrivacyPolicyView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Hotovo") { isShowingPrivacyPolicy = false }
                            }
                        }
                }
            }
            .onChange(of: viewModel.semester) {
                // Během načítání semestr nastavuje sám ViewModel – nenačítáme podruhé
                guard viewModel.isLoggedIn, !viewModel.isLoading else { return }
                Task { await viewModel.loadMySubjects() }
            }
        }
    }

    // MARK: - Nepřihlášený stav

    /// Výběr školy – aplikace funguje se všemi školami, které používají IS/STAG
    private var schoolSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.school },
                set: { viewModel.selectSchool($0) }
            )) {
                ForEach(StagSchool.all) { school in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(school.name)
                        Text("\(school.shortName) · \(school.city)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(school)
                }
                if viewModel.school.isCustom {
                    Text(viewModel.school.name).tag(viewModel.school)
                }
            } label: {
                Label("Škola", systemImage: "building.columns")
                    .labelStyle(.compact(spacing: 8))
            }
            .pickerStyle(.navigationLink)
            .disabled(viewModel.isLoading)

            // Vlastní server: ukážeme celou adresu, ať je jasné, kam se uživatel přihlašuje (ochrana před phishingem)
            if viewModel.school.isCustom {
                LabeledContent {
                    Text(serverHost)
                        .textSelection(.enabled)
                } label: {
                    Label("Server", systemImage: "server.rack")
                        .labelStyle(.compact(spacing: 8))
                }
            }

            Button("Jiná škola – zadat adresu serveru", systemImage: "link.badge.plus") {
                customSchoolError = nil
                isEnteringCustomSchool = true
            }
            .disabled(viewModel.isLoading)
        } header: {
            Text("Tvoje škola")
        } footer: {
            Text("Aplikace funguje se školami, které používají IS/STAG. Adresu serveru najdeš v nápovědě IS/STAG své školy (obvykle stag-ws.nazevskoly.cz).")
        }
        .alert("Adresa serveru IS/STAG", isPresented: $isEnteringCustomSchool) {
            TextField("stag-ws.skola.cz", text: $customSchoolAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Ověřit a použít") {
                Task { customSchoolError = await viewModel.validateCustomSchool(address: customSchoolAddress) }
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Zadej adresu webových služeb IS/STAG své školy. Ověříme ji dřív, než se přihlásíš.\n\nPřihlašuj se jen na server, kterému důvěřuješ – zadáš na něm školní heslo.")
        }
        .alert("Server se nepodařilo ověřit", isPresented: Binding(
            get: { customSchoolError != nil },
            set: { if !$0 { customSchoolError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(customSchoolError ?? "")
        }
    }

    private var loginSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 6) {
                    Text("Tvoje předměty z IS/STAG")
                        .font(.title2.bold())
                    Text("Přihlas se školním účtem \(viewModel.school.shortName) a načteme jen předměty, které máš zapsané.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let periodTitle = viewModel.periodTitle {
                        Text(periodTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.center)

                Button {
                    Task { await viewModel.login(using: webAuthenticationSession) }
                } label: {
                    Label("Přihlásit se do IS/STAG", systemImage: "person.badge.key.fill")
                        .labelStyle(.compact(spacing: 8))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isLoading)

                if viewModel.school.isCustom {
                    Label {
                        Text("Přihlásíš se na serveru \(serverHost). Pokračuj, jen pokud mu důvěřuješ.")
                    } icon: {
                        Image(systemName: "exclamationmark.shield.fill")
                    }
                    .labelStyle(.compact(spacing: 6))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Přihlášení proběhne na zabezpečené stránce \(viewModel.school.shortName). Aplikace tvé heslo nevidí, dostane jen přístupový klíč, který se bezpečně uloží v Klíčence. Platí až 90 dní a odhlášením se smaže.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .labelStyle(.compact)

                Button {
                    isShowingPrivacyPolicy = true
                } label: {
                    Label("Zásady ochrany osobních údajů", systemImage: "hand.raised")
                        .labelStyle(.compact)
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }

    /// Celá adresa serveru zvolené školy (host a případně port), např. „stag-ws.skola.cz“
    private var serverHost: String { viewModel.school.displayHost }

    // MARK: - Přihlášený stav

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.studentName ?? String(localized: "Přihlášený student"))
                        .font(.headline)
                    Text(accountDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Odhlásit") {
                    withAnimation { viewModel.logout() }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }

            LabeledContent("Škola", value: viewModel.school.name)
                .font(.subheadline)

            Picker("Semestr", selection: $viewModel.semester) {
                Text("Zimní semestr").tag("ZS")
                Text("Letní semestr").tag("LS")
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isLoading)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let period = viewModel.period {
                    Text("Akademický rok \(period.academicYearTitle)")
                }
                Label {
                    Text("Účet zůstane připojený. Přístupový klíč je bezpečně uložený v Klíčence, platí až 90 dní a odhlášením se smaže. Heslo aplikace nevidí.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .labelStyle(.compact)
            }
        }
    }

    /// „Osobní číslo A23456 · FAI“
    private var accountDetail: String {
        let number = viewModel.osCislo ?? ""
        return [String(localized: "Osobní číslo \(number)"), viewModel.faculty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .loading(let message):
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if !viewModel.results.isEmpty {
            Section {
                ForEach(viewModel.results) { subject in
                    resultRow(for: subject)
                }
            } header: {
                HStack {
                    Text(viewModel.resultsTitle)
                    Spacer()
                    if !viewModel.importableResults.isEmpty {
                        Button(viewModel.allSelected ? "Zrušit výběr" : "Vybrat vše") {
                            viewModel.toggleSelectAll()
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            } footer: {
                Text("Barvu, kredity i název můžeš po importu upravit v detailu předmětu.")
            }
        }
    }

    private func resultRow(for subject: StagSubject) -> some View {
        let imported = viewModel.isAlreadyImported(subject)
        let selected = viewModel.selectedIDs.contains(subject.id)

        return Button {
            viewModel.toggleSelection(subject)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: imported ? "checkmark.circle" : (selected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(selected && !imported ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(subject.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(imported ? Color.secondary : Color.primary)
                    Text(detailText(for: subject, imported: imported))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(imported)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detailText(for subject: StagSubject, imported: Bool) -> String {
        var parts = [subject.zkratka]
        if let credits = subject.kreditu {
            parts.append(String(localized: "\(credits) kreditů"))
        }
        if imported {
            parts.append(String(localized: "už máš v aplikaci"))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Nepřihlášený") {
    StagImportView()
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}

#if DEBUG
#Preview("Přihlášený") {
    StagImportView(viewModel: .previewLoggedIn)
        .modelContainer(SampleData.previewContainer)
}
#endif
