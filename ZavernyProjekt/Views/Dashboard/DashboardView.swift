import SwiftUI
import SwiftData

/// Hlavní přehled – nadcházející deadliny seřazené od nejbližšího.
/// View drží `@Query` (živá data ze SwiftData), filtrování a akce deleguje na `DashboardViewModel`.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext

    /// Všechny úkoly seřazené podle termínu. @Query se sám překreslí při každé změně dat.
    @Query(sort: \ExamTask.dueDate) private var tasks: [ExamTask]
    /// Předměty – prázdný stav podle nich nabídne import ze STAGu
    @Query private var subjects: [Subject]

    @State private var viewModel = DashboardViewModel()
    @State private var isAddingTask = false
    @State private var taskToEdit: ExamTask?
    /// Úkol, pro který je otevřený editor události v Kalendáři
    @State private var taskForCalendar: ExamTask?
    @State private var isImportingFromStag = false
    /// Vybraná záložka – karta nových termínů přepíná na Zkoušky
    @AppStorage("selectedTab") private var selectedTab = "dashboard"

    /// Termíny ze STAGu (@Observable singleton – čtení v body se automaticky sleduje)
    private var termStore: ExamTermStore { .shared }

    /// Nově vypsané termíny, které si uživatel ještě neprohlédl
    private var newTerms: [ExamTerm] {
        guard termStore.hasNewTerms else { return [] }
        return termStore.availableTerms.filter { termStore.newTermIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Přehled")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Přidat deadline", systemImage: "plus") { isAddingTask = true }
                }
            }
            .sheet(isPresented: $isAddingTask) { TaskFormSheet() }
            .sheet(item: $taskToEdit) { task in TaskFormSheet(task: task) }
            .sheet(item: $taskForCalendar) { task in
                CalendarEventEditor(task: task).ignoresSafeArea()
            }
            .sheet(isPresented: $isImportingFromStag) { StagImportView() }
            .sensoryFeedback(.success, trigger: viewModel.completionFeedback)
        }
    }

    // MARK: - Seznam deadlinů

    private var taskList: some View {
        let sections = viewModel.sections(from: tasks)

        return List {
            // Souhrnné kartičky + segmentový přepínač
            Section {
                if !newTerms.isEmpty {
                    NewTermsCard(terms: newTerms) { selectedTab = "terms" }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                StatsHeaderView(stats: viewModel.stats(from: tasks))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                Picker("Filtr", selection: $viewModel.filter.animation(.snappy)) {
                    ForEach(DashboardFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            if sections.isEmpty {
                filteredEmptyState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.tasks) { task in
                            row(for: task)
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .searchable(text: $viewModel.searchText, prompt: "Hledat deadline nebo předmět")
    }

    /// Řádek s gesty: klepnutí = úprava, swipe doprava = splnit, swipe doleva = smazat,
    /// dlouhé podržení = kontextové menu (včetně přidání do Kalendáře)
    private func row(for task: ExamTask) -> some View {
        TaskRowView(task: task) { toggle(task) }
            .contentShape(Rectangle())
            .onTapGesture { taskToEdit = task }
            .swipeActions(edge: .leading) {
                Button {
                    toggle(task)
                } label: {
                    Label(
                        task.isCompleted ? "Obnovit" : "Splněno",
                        systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
                    )
                }
                .tint(task.isCompleted ? .orange : .green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    withAnimation { viewModel.delete(task, in: modelContext) }
                } label: {
                    Label("Smazat", systemImage: "trash")
                }
                Button {
                    taskToEdit = task
                } label: {
                    Label("Upravit", systemImage: "pencil")
                }
                .tint(.indigo)
            }
            .contextMenu {
                Button {
                    toggle(task)
                } label: {
                    Label(
                        task.isCompleted ? "Obnovit" : "Splněno",
                        systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
                    )
                }
                Button {
                    taskToEdit = task
                } label: {
                    Label("Upravit", systemImage: "pencil")
                }
                Button {
                    taskForCalendar = task
                } label: {
                    Label("Přidat do Kalendáře", systemImage: "calendar.badge.plus")
                }
                // Live Activity jen pro termín v nejbližších 8 hodinách
                if LiveActivityManager.shared.canStartExam(task) {
                    Button {
                        LiveActivityManager.shared.startExam(task)
                    } label: {
                        Label("Odpočet na zamčené obrazovce", systemImage: "timer")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    withAnimation { viewModel.delete(task, in: modelContext) }
                } label: {
                    Label("Smazat", systemImage: "trash")
                }
            }
    }

    private func toggle(_ task: ExamTask) {
        withAnimation(.snappy) { viewModel.toggleCompletion(task) }
    }

    // MARK: - Prázdné stavy

    /// Uživatel zatím nezadal žádný deadline. Bez předmětů nabídneme nejdřív import ze STAGu.
    private var emptyState: some View {
        VStack(spacing: 0) {
            if !newTerms.isEmpty {
                NewTermsCard(terms: newTerms) { selectedTab = "terms" }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            emptyStateContent
        }
    }

    private var emptyStateContent: some View {
        EmptyStateView(
            symbol: "calendar.badge.plus",
            title: "Zatím žádné deadliny",
            message: subjects.isEmpty
                ? "Načti si své předměty ze STAGu a přidej k nim první zkoušku nebo odevzdání. Den před termínem ti pošleme připomínku."
                : "Přidej první zkoušku, zápočet nebo projekt. Den před termínem ti pošleme připomínku.",
            actionTitle: "Přidat deadline",
            action: { isAddingTask = true },
            secondaryActionTitle: subjects.isEmpty ? "Načíst předměty ze STAGu" : nil,
            secondaryAction: { isImportingFromStag = true }
        )
        .frame(maxHeight: .infinity)
    }

    /// Filtr nebo vyhledávání nic nenašlo
    @ViewBuilder
    private var filteredEmptyState: some View {
        if viewModel.isSearching {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else if viewModel.filter == .completed {
            EmptyStateView(
                symbol: "tray",
                title: "Zatím nic splněného",
                message: "Odškrtni deadline klepnutím na kolečko a objeví se tady.",
                tint: .green
            )
        } else {
            EmptyStateView(
                symbol: "checkmark.seal.fill",
                title: "Máš hotovo!",
                message: "Žádné nadcházející deadliny. Užij si volno 🎉",
                tint: .green
            )
        }
    }
}

// MARK: - Nové termíny

/// Výrazná karta „Vypsány nové termíny“ – klepnutí otevře záložku Zkoušky.
private struct NewTermsCard: View {
    let terms: [ExamTerm]
    let action: () -> Void

    private var subjectCodes: String {
        var seen = Set<String>()
        return terms.map(\.subjectCode)
            .filter { seen.insert($0.uppercased()).inserted }
            .joined(separator: ", ")
    }

    private var countText: String {
        "\(terms.count) \(CzechPlural.form(terms.count, one: "nový termín", few: "nové termíny", many: "nových termínů"))"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .frame(width: 46, height: 46)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Vypsány nové termíny")
                        .font(.headline)
                    Text("\(countText) · \(subjectCodes)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.indigo, .indigo.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vypsány nové termíny: \(countText), předměty \(subjectCodes)")
        .accessibilityHint("Otevře záložku Zkoušky")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("S daty") {
    DashboardView()
        .modelContainer(SampleData.previewContainer)
}

#Preview("Prázdný") {
    DashboardView()
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
