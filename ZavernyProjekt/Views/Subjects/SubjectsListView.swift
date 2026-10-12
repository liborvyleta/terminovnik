import SwiftUI
import SwiftData

/// Seznam předmětů v kartách.
///
/// Předměty čte přes `@Query` seřazené podle názvu, nad nimi zobrazuje
/// souhrnné statistiky a vstup do studijních výsledků. Klepnutí otevře
/// detail, dlouhý stisk nabídne úpravu a smazání (s potvrzením). Z toolbaru
/// lze předmět přidat ručně nebo importovat ze STAGu. Stav sheetů drží
/// `SubjectsViewModel`. Jedna ze záložek hlavní navigace.
struct SubjectsListView: View {
    /// SwiftData kontext pro mazání předmětů.
    @Environment(\.modelContext) private var modelContext
    /// Všechny předměty seřazené podle názvu.
    @Query(sort: \Subject.name) private var subjects: [Subject]
    /// ViewModel se stavem sheetů, mazáním a statistikami.
    @State private var viewModel = SubjectsViewModel()

    /// Prázdný stav nebo seznam karet, s navigací do detailu, sheety a dialogem smazání.
    var body: some View {
        NavigationStack {
            Group {
                if subjects.isEmpty {
                    emptyState
                } else {
                    subjectList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Předměty")
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailView(subject: subject)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Import ze STAGu", systemImage: "square.and.arrow.down") { viewModel.isImportingFromStag = true }
                    Button("Přidat předmět", systemImage: "plus") { viewModel.isAddingSubject = true }
                }
            }
            .sheet(isPresented: $viewModel.isAddingSubject) { SubjectFormSheet() }
            .sheet(isPresented: $viewModel.isImportingFromStag) { StagImportView() }
            .sheet(item: $viewModel.subjectToEdit) { subject in SubjectFormSheet(subject: subject) }
            .confirmationDialog(
                "Smazat předmět?",
                isPresented: $viewModel.isConfirmingDelete,
                titleVisibility: .visible,
                presenting: viewModel.subjectToDelete
            ) { subject in
                Button("Smazat \(subject.name)", role: .destructive) {
                    withAnimation { viewModel.delete(subject, in: modelContext) }
                }
            } message: { subject in
                let count = subject.taskList.count
                Text("Spolu s předmětem se smaže i \(count) úkolů. Akci nelze vrátit.")
            }
        }
    }

    // MARK: - Obsah

    /// Statistiky, vstup do výsledků a karty předmětů s kontextovým menu.
    private var subjectList: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    StatCard(value: subjects.count, title: String(localized: "Předměty"), symbol: "books.vertical.circle.fill", color: .accentColor)
                    StatCard(value: viewModel.totalCredits(of: subjects), title: String(localized: "Kredity"), symbol: "star.circle.fill", color: .purple)
                    StatCard(value: viewModel.activeTaskCount(of: subjects), title: String(localized: "Aktivní úkoly"), symbol: "flag.circle.fill", color: .orange)
                }

                gradesEntry

                LazyVStack(spacing: 14) {
                    ForEach(subjects) { subject in
                        NavigationLink(value: subject) {
                            SubjectCardView(subject: subject)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Upravit", systemImage: "pencil") { viewModel.subjectToEdit = subject }
                            Button("Smazat", systemImage: "trash", role: .destructive) { viewModel.subjectToDelete = subject }
                        }
                    }
                }
            }
            .padding()
        }
    }

    /// Karta „Studijní výsledky“ – jen s připojeným účtem STAG nebo uloženými známkami.
    @ViewBuilder
    private var gradesEntry: some View {
        let store = GradeStore.shared
        if StagAccountStore.shared.isConnected || store.hasGrades {
            NavigationLink {
                GradesView()
            } label: {
                GradesEntryCard(summary: store.overallSummary, hasGrades: store.hasGrades)
            }
            .buttonStyle(.plain)
        }
    }

    /// Prázdný stav s importem ze STAGu a ručním přidáním předmětu.
    private var emptyState: some View {
        EmptyStateView(
            symbol: "books.vertical",
            title: String(localized: "Žádné předměty"),
            message: String(localized: "Naimportuj si předměty ze STAGu, nebo je přidej ručně. Ke každému pak můžeš zadávat zkoušky a úkoly."),
            actionTitle: String(localized: "Importovat ze STAGu"),
            actionSymbol: "square.and.arrow.down",
            action: { viewModel.isImportingFromStag = true },
            secondaryActionTitle: String(localized: "Přidat předmět ručně"),
            secondaryAction: { viewModel.isAddingSubject = true }
        )
        .frame(maxHeight: .infinity)
    }
}

#Preview("S daty") {
    SubjectsListView()
        .modelContainer(SampleData.previewContainer)
}

#Preview("Prázdný") {
    SubjectsListView()
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
