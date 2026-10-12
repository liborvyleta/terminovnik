import SwiftUI
import SwiftData

/// Záložka Zkoušky – termíny zkoušek a zápočtů z IS/STAG.
///
/// Nahoře přepínač Zapsané / Vypsané. Zapsané termíny ukazují odpočet a do kdy se lze odhlásit,
/// vypsané jsou seskupené po předmětech s obsazeností a oknem přihlašování. Nově vypsané termíny
/// mají štítek „Nový“, který zmizí po opuštění záložky.
///
/// Data bere z `ExamTermsViewModel` (ostře z `ExamTermStore.shared`), názvy a barvy předmětů
/// z `@Query` nad `Subject`. Uživatel může termíny obnovit, otevřít detail, zapsat se nebo
/// odhlásit z kontextové nabídky a přihlásit se do STAGu. Používá se jako záložka v `ContentView`.
struct ExamTermsView: View {
    /// Kontext SwiftData pro obnovení termínů a změny zápisu.
    @Environment(\.modelContext) private var modelContext
    /// Předměty – kvůli názvům a barvám (změna barvy předmětu se hned projeví).
    @Query private var subjects: [Subject]

    /// ViewModel se stavem obrazovky, termíny a přepínačem segmentu.
    @State private var viewModel: ExamTermsViewModel
    /// Termín otevřený v detailu (sheet).
    @State private var selectedTerm: ExamTerm?
    /// Zda je otevřený sheet přihlášení do STAGu.
    @State private var isShowingLogin = false
    /// Zápis/odhlášení z kontextové nabídky – čeká na potvrzení v dialogu.
    @State private var registrationRequest: ExamTermRegistrationRequest?

    /// Vytvoří záložku v ostrém režimu s daty z `ExamTermStore.shared`.
    init() {
        _viewModel = State(initialValue: ExamTermsViewModel())
    }

    /// Vytvoří záložku se vstříknutým ViewModelem – pro náhledy a snímky obrazovky.
    /// - Parameter viewModel: ViewModel, např. `ExamTermsViewModel(previewTerms:)`.
    init(viewModel: ExamTermsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    /// Obsah podle stavu v `NavigationStack` s detailem termínu, tokem zápisu,
    /// přihlášením do STAGu a obnovením při otevření nebo po přihlášení.
    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Zkoušky")
                // Přepínač je připnutý nahoře, velký nadpis by se s ním překrýval
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(item: $selectedTerm) { term in
                    ExamTermDetailView(
                        term: term,
                        subjectName: viewModel.subjectName(for: term.subjectCode, subjects: subjects),
                        tint: viewModel.tint(for: term.subjectCode, subjects: subjects),
                        isNew: viewModel.isNew(term),
                        viewModel: viewModel
                    )
                }
                .examTermRegistrationFlow($registrationRequest, viewModel: viewModel)
                .sheet(isPresented: $isShowingLogin) { StagImportView() }
                // Spustí se při otevření i hned po přihlášení do STAGu
                .task(id: viewModel.isConnected) {
                    await viewModel.refreshIfNeeded(context: modelContext)
                }
                .onDisappear { viewModel.markAllSeen() }
                .sensoryFeedback(.selection, trigger: viewModel.segment)
        }
    }

    // MARK: - Stavy

    /// Obsah podle stavu obrazovky: nepřihlášeno, načítání, chyba, prázdno nebo seznam termínů.
    @ViewBuilder
    private var content: some View {
        switch viewModel.screenState {
        case .notConnected(let message):
            centered {
                EmptyStateView(
                    symbol: "graduationcap",
                    title: String(localized: "Termíny zkoušek ze STAGu"),
                    message: message ?? String(localized: "Přihlas se do IS/STAG a uvidíš vypsané termíny zkoušek a zápočtů – s obsazeností, místností i do kdy se můžeš přihlásit. Na nové termíny tě hned upozorníme."),
                    tint: .purple,
                    actionTitle: String(localized: "Přihlásit se do IS/STAG"),
                    actionSymbol: "person.crop.circle.badge.checkmark",
                    action: { isShowingLogin = true }
                )
            }

        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Načítám termíny ze STAGu…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            centered {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "Termíny se nepodařilo načíst"),
                    message: message,
                    tint: .orange,
                    actionTitle: String(localized: "Zkusit znovu"),
                    actionSymbol: "arrow.clockwise",
                    action: refresh
                )
            }

        case .empty:
            centered {
                noTermsState(actionTitle: String(localized: "Obnovit termíny"))
            }

        case .ready:
            termsList
        }
    }

    /// Prázdný stav vystředěný ve scrollovatelné ploše (funguje i tažení dolů pro obnovení).
    /// - Parameter content: Obsah zobrazený uprostřed.
    /// - Returns: Scrollovatelný pohled s obsahem na výšku plochy.
    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .containerRelativeFrame(.vertical)
        }
        .refreshable { await viewModel.refresh(context: modelContext) }
    }

    /// Prázdný stav „Zatím žádné vypsané termíny“.
    /// - Parameter actionTitle: Titulek tlačítka pro obnovení; `nil` tlačítko skryje.
    /// - Returns: Pohled prázdného stavu.
    private func noTermsState(actionTitle: String?) -> some View {
        EmptyStateView(
            symbol: "calendar.badge.clock",
            title: String(localized: "Zatím žádné vypsané termíny"),
            message: String(localized: "Jakmile je vyučující vypíšou, objeví se tady a hned tě upozorníme."),
            tint: .teal,
            actionTitle: actionTitle,
            actionSymbol: "arrow.clockwise",
            action: actionTitle == nil ? nil : { refresh() }
        )
    }

    // MARK: - Seznam

    /// Seznam termínů obnovovaný každou minutu s připnutým přepínačem a tažením pro obnovení.
    private var termsList: some View {
        // Překreslení každou minutu: odpočty, okna přihlašování, „aktualizováno před…“
        TimelineView(.everyMinute) { context in
            List {
                listContent(now: context.date)
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .animation(.snappy, value: viewModel.segment)
            .refreshable { await viewModel.refresh(context: modelContext) }
            .safeAreaInset(edge: .top, spacing: 0) { segmentBar }
        }
    }

    /// Obsah seznamu: chybový banner, sekce zvoleného segmentu a patička s časem aktualizace.
    /// - Parameter now: Aktuální čas pro odpočty a texty.
    @ViewBuilder
    private func listContent(now: Date) -> some View {
        if let errorMessage = viewModel.errorMessage {
            Section { errorBanner(errorMessage) }
        }

        if viewModel.segment == .registered {
            registeredSections(now: now)
        } else {
            availableSections(now: now)
        }

        if let footer = viewModel.footerText(now: now) {
            Section {
                footerLabel(footer)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// Připnutý přepínač Zapsané / Vypsané.
    private var segmentBar: some View {
        @Bindable var viewModel = viewModel
        return Picker("Termíny", selection: $viewModel.segment.animation(.snappy)) {
            ForEach(ExamTermsSegment.allCases) { segment in
                Text(segmentTitle(segment)).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    /// Titulek segmentu s počtem termínů, např. „Zapsané (2)“, „Vypsané (5)“.
    /// - Parameter segment: Segment, pro který se titulek skládá.
    /// - Returns: Název segmentu, s počtem v závorce, je-li nenulový.
    private func segmentTitle(_ segment: ExamTermsSegment) -> String {
        let count = segment == .registered ? viewModel.registeredTerms.count : viewModel.availableTerms.count
        return count > 0 ? "\(segment.title) (\(count))" : segment.title
    }

    // MARK: - Zapsané

    /// Sekce zapsaných termínů: karta nejbližšího, seznam dalších a vysvětlující patička,
    /// případně prázdný stav s odkazem na vypsané termíny.
    /// - Parameter now: Aktuální čas pro odpočty.
    @ViewBuilder
    private func registeredSections(now: Date) -> some View {
        let registered = viewModel.registeredTerms

        if let first = registered.first {
            Section {
                Button { selectedTerm = first } label: {
                    ExamTermHeroCard(
                        term: first,
                        subjectName: viewModel.subjectName(for: first.subjectCode, subjects: subjects),
                        tint: viewModel.tint(for: first.subjectCode, subjects: subjects),
                        now: now
                    )
                }
                .buttonStyle(.plain)
                .contextMenu { registrationMenu(for: first) }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if registered.count > 1 {
                Section {
                    ForEach(registered.dropFirst()) { term in
                        Button { selectedTerm = term } label: {
                            ExamTermRegisteredRow(
                                term: term,
                                subjectName: viewModel.subjectName(for: term.subjectCode, subjects: subjects),
                                tint: viewModel.tint(for: term.subjectCode, subjects: subjects),
                                now: now
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu { registrationMenu(for: term) }
                    }
                } header: {
                    HStack {
                        Text("Další zapsané")
                        Spacer()
                        Text(ExamTermsViewModel.termCountText(registered.count - 1))
                    }
                }
            }

            Section {
            } footer: {
                Text("Ke každému zapsanému termínu máš v Přehledu zkoušku s připomínkou den předem. Odhlásit se můžeš v detailu termínu nebo podržením řádku.")
            }
        } else {
            Section {
                EmptyStateView(
                    symbol: "checkmark.seal",
                    title: String(localized: "Zatím nemáš zapsaný termín"),
                    message: viewModel.availableTerms.isEmpty
                        ? String(localized: "Až se na termín zapíšeš ve STAGu, objeví se tady i s odpočtem a připomínkou.")
                        : String(localized: "Vyber si z vypsaných termínů a zapiš se – tady pak uvidíš odpočet a dostaneš připomínku."),
                    tint: .green,
                    actionTitle: viewModel.availableTerms.isEmpty ? nil : String(localized: "Zobrazit vypsané termíny"),
                    actionSymbol: "list.bullet.rectangle",
                    action: viewModel.availableTerms.isEmpty ? nil : { withAnimation(.snappy) { viewModel.segment = .available } }
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Vypsané

    /// Sekce vypsaných termínů seskupené po předmětech, případně prázdný stav.
    /// - Parameter now: Aktuální čas pro okna přihlašování.
    @ViewBuilder
    private func availableSections(now: Date) -> some View {
        let groups = viewModel.availableGroups

        if groups.isEmpty {
            Section {
                noTermsState(actionTitle: nil)
                    .listRowBackground(Color.clear)
            }
        } else {
            ForEach(groups) { group in
                let tint = viewModel.tint(for: group.subjectCode, subjects: subjects)
                Section {
                    ForEach(group.terms) { term in
                        Button { selectedTerm = term } label: {
                            ExamTermAvailableRow(term: term, tint: tint, isNew: viewModel.isNew(term), now: now)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { registrationMenu(for: term) }
                    }
                } header: {
                    subjectHeader(group, tint: tint)
                }
            }

            Section {
            } footer: {
                Text("Zapsat se můžeš v detailu termínu nebo podržením řádku. Na nově vypsané termíny tě upozorníme.")
            }
        }
    }

    /// Hlavička předmětu: štítek kódu, název a počet termínů.
    /// - Parameters:
    ///   - group: Skupina termínů jednoho předmětu.
    ///   - tint: Barva předmětu.
    /// - Returns: Pohled hlavičky sekce.
    private func subjectHeader(_ group: ExamTermGroup, tint: Color) -> some View {
        HStack(spacing: 8) {
            TimetableCodeTag(code: group.subjectCode, tint: tint)
            if let name = viewModel.subjectName(for: group.subjectCode, subjects: subjects) {
                Text(name)
                    .lineLimit(1)
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            Text(ExamTermsViewModel.termCountText(group.terms.count))
                .textCase(nil)
                .font(.caption)
        }
        .padding(.top, 6)
    }

    // MARK: - Pomocné pohledy

    /// Chyba při obnovení – starší termíny zůstávají zobrazené.
    /// - Parameter message: Text chyby.
    /// - Returns: Banner s tlačítkem pro opakování.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Termíny se nepodařilo aktualizovat")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Zkusit znovu", action: refresh)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isLoading)
        }
    }

    /// Patička seznamu s ikonou obnovení (např. kdy byla data aktualizována).
    /// - Parameter text: Zobrazený text.
    /// - Returns: Vystředěný popisek.
    private func footerLabel(_ text: String) -> some View {
        Label(text, systemImage: "arrow.triangle.2.circlepath")
            .labelStyle(.compact)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Toolbar

    /// Tlačítko obnovení v toolbaru (jen po přihlášení); během načítání nebo zápisu indikátor průběhu.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isConnected {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading || viewModel.pendingRegistration != nil {
                    ProgressView()
                } else {
                    Button("Obnovit termíny", systemImage: "arrow.clockwise", action: refresh)
                }
            }
        }
    }

    /// Kontextová nabídka řádku: zápis / odhlášení / fronta (provede se až po potvrzení).
    /// - Parameter term: Termín, ke kterému nabídka patří.
    /// - Returns: Položka nabídky `ExamTermRegistrationMenuItem`.
    private func registrationMenu(for term: ExamTerm) -> some View {
        ExamTermRegistrationMenuItem(
            term: term,
            subjectName: viewModel.subjectName(for: term.subjectCode, subjects: subjects),
            viewModel: viewModel,
            request: $registrationRequest
        )
    }

    /// Asynchronně obnoví termíny ze STAGu.
    private func refresh() {
        Task { await viewModel.refresh(context: modelContext) }
    }
}

#Preview("Zkoušky – světlý") {
    ExamTermsView(viewModel: ExamTermsViewModel(previewTerms: ExamTerm.samples, newTermIDs: ["t4", "t5"]))
        .modelContainer(SampleData.previewContainer)
}

#Preview("Zkoušky – tmavý") {
    ExamTermsView(viewModel: ExamTermsViewModel(previewTerms: ExamTerm.samples, newTermIDs: ["t4"]))
        .modelContainer(SampleData.previewContainer)
        .preferredColorScheme(.dark)
}

#Preview("Bez termínů") {
    ExamTermsView(viewModel: ExamTermsViewModel(previewTerms: []))
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}

#Preview("Nepřihlášený") {
    ExamTermsView(viewModel: ExamTermsViewModel(previewTerms: nil))
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
