import SwiftUI
import SwiftData

/// Studijní výsledky ze STAGu: vážený průměr, získané kredity a známky po semestrech.
///
/// Otevírá se z karty v záložce Předměty (uvnitř jejího `NavigationStack`, proto vlastní stack nemá).
/// Řádek předmětu, který je i v aplikaci, vede na jeho detail.
struct GradesView: View {
    /// Předměty – kvůli barvám a odkazu na detail (změna barvy předmětu se hned projeví)
    @Query private var subjects: [Subject]

    @State private var viewModel: GradesViewModel
    @State private var isShowingLogin = false

    /// Ostrý režim – data z `GradeStore.shared`
    init() {
        _viewModel = State(initialValue: GradesViewModel())
    }

    /// Vstříknutý ViewModel – pro náhledy a snímky obrazovky (`GradesViewModel(previewGrades:)`)
    init(viewModel: GradesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Studijní výsledky")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingLogin) { StagImportView() }
            // Spustí se při otevření i hned po přihlášení do STAGu
            .task(id: viewModel.isConnected) {
                await viewModel.refreshIfNeeded()
            }
    }

    // MARK: - Stavy

    @ViewBuilder
    private var content: some View {
        switch viewModel.screenState {
        case .notConnected(let message):
            centered {
                EmptyStateView(
                    symbol: "graduationcap",
                    title: String(localized: "Známky ze STAGu"),
                    message: message ?? String(localized: "Přihlas se do IS/STAG a uvidíš známky ze zápočtů a zkoušek, získané kredity i vážený studijní průměr. Na nové známky tě hned upozorníme."),
                    tint: .green,
                    actionTitle: String(localized: "Přihlásit se do IS/STAG"),
                    actionSymbol: "person.crop.circle.badge.checkmark",
                    action: { isShowingLogin = true }
                )
            }

        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Načítám známky ze STAGu…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            centered {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "Známky se nepodařilo načíst"),
                    message: message,
                    tint: .orange,
                    actionTitle: String(localized: "Zkusit znovu"),
                    actionSymbol: "arrow.clockwise",
                    action: refresh
                )
            }

        case .empty:
            centered {
                EmptyStateView(
                    symbol: "rosette",
                    title: String(localized: "Zatím žádné známky"),
                    message: String(localized: "Jakmile ti vyučující zapíšou do STAGu zápočet nebo známku ze zkoušky, objeví se tady a hned tě upozorníme."),
                    tint: .teal,
                    actionTitle: String(localized: "Obnovit známky"),
                    actionSymbol: "arrow.clockwise",
                    action: refresh
                )
            }

        case .ready:
            gradesList
        }
    }

    /// Prázdný stav vystředěný ve scrollovatelné ploše (funguje i tažení dolů pro obnovení)
    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .containerRelativeFrame(.vertical)
        }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Seznam

    private var gradesList: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section { errorBanner(errorMessage) }
            }

            Section {
                GradeSummaryCard(summary: viewModel.summary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            ForEach(viewModel.semesters) { semester in
                Section {
                    ForEach(semester.grades) { grade in
                        row(for: grade)
                    }
                } header: {
                    semesterHeader(semester)
                }
            }

            Section {
            } footer: {
                VStack(spacing: 12) {
                    Text("Průměr je orientační – počítá se z klasifikovaných předmětů vážený kredity.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Překreslení každou minutu kvůli „aktualizováno před…“
                    TimelineView(.everyMinute) { context in
                        if let footer = viewModel.footerText(now: context.date) {
                            Label(footer, systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.compact)
                                .font(.caption2)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        .refreshable { await viewModel.refresh() }
    }

    /// Předmět, který je i v aplikaci, otevře svůj detail
    @ViewBuilder
    private func row(for grade: SubjectGrade) -> some View {
        let gradeRow = GradeRow(
            grade: grade,
            name: viewModel.subjectName(for: grade, subjects: subjects),
            tint: viewModel.tint(for: grade.code, subjects: subjects)
        )
        if let subject = viewModel.subject(for: grade.code, in: subjects) {
            NavigationLink(value: subject) { gradeRow }
        } else {
            gradeRow
        }
    }

    /// „ZS 2026/2027 ……… Ø 1,50 · 11 kreditů“
    private func semesterHeader(_ semester: GradeSemester) -> some View {
        let summary = semester.summary
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(semester.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let average = summary.weightedAverage {
                let text = GradesViewModel.averageText(average)
                Text(verbatim: "Ø \(text)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(GradesViewModel.averageLevel(average).color)
                    .accessibilityLabel(Text("Průměr \(text)"))
            }
            Text(GradesViewModel.semesterCreditsText(semester))
                .font(.caption)
        }
        .textCase(nil)
        .padding(.top, 6)
    }

    // MARK: - Pomocné pohledy

    /// Chyba při obnovení – starší známky zůstávají zobrazené
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Známky se nepodařilo aktualizovat")
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isConnected {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button("Obnovit známky", systemImage: "arrow.clockwise", action: refresh)
                }
            }
        }
    }

    private func refresh() {
        Task { await viewModel.refresh() }
    }
}

#Preview("Výsledky – světlý") {
    NavigationStack {
        GradesView(viewModel: GradesViewModel(previewGrades: SubjectGrade.samples))
    }
    .modelContainer(SampleData.previewContainer)
}

#Preview("Výsledky – tmavý") {
    NavigationStack {
        GradesView(viewModel: GradesViewModel(previewGrades: SubjectGrade.samples))
    }
    .modelContainer(SampleData.previewContainer)
    .preferredColorScheme(.dark)
}

#Preview("Bez známek") {
    NavigationStack {
        GradesView(viewModel: GradesViewModel(previewGrades: []))
    }
    .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}

#Preview("Nepřihlášený") {
    NavigationStack {
        GradesView(viewModel: GradesViewModel(previewGrades: nil))
    }
    .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
