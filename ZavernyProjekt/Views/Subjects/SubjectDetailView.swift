import SwiftUI
import SwiftData

/// Detail předmětu.
///
/// Zobrazuje hlavičku s kroužkem postupu, hodnocení ze STAGu (`GradeStore`),
/// aktivní a splněné úkoly, termíny zkoušek ze STAGu (`ExamTermStore`)
/// s odkazem na záložku Zkoušky. Umožňuje přidat deadline, upravit předmět
/// a u úkolů je splnit, upravit, smazat nebo přidat do Kalendáře. Logiku
/// deleguje na `SubjectDetailViewModel`. Otevírá se ze `SubjectsListView`.
struct SubjectDetailView: View {
    /// SwiftData kontext pro mazání úkolů.
    @Environment(\.modelContext) private var modelContext

    /// Zobrazovaný předmět.
    let subject: Subject

    /// ViewModel s tříděním úkolů, jejich plněním a mazáním.
    @State private var viewModel = SubjectDetailViewModel()
    /// Zda je otevřený formulář nového deadlinu.
    @State private var isAddingTask = false
    /// Zda je otevřený formulář úpravy předmětu.
    @State private var isEditingSubject = false
    /// Úkol otevřený v editačním formuláři.
    @State private var taskToEdit: ExamTask?
    /// Úkol, pro který je otevřený editor události v Kalendáři.
    @State private var taskForCalendar: ExamTask?
    /// Vybraná záložka – odkaz „Všechny termíny“ přepne na Zkoušky.
    @AppStorage("selectedTab") private var selectedTab = "dashboard"

    /// Seznam s hlavičkou, hodnocením, prázdným stavem, aktivními úkoly, termíny a splněnými úkoly.
    var body: some View {
        let active = viewModel.activeTasks(of: subject)
        let completed = viewModel.completedTasks(of: subject)
        // Termíny ze STAGu (@Observable singleton – změny se v body sledují)
        let examTerms = subject.code.isEmpty ? [] : ExamTermStore.shared.terms(forSubject: subject.code)
        // Hodnocení ze STAGu (nejnovější zápis předmětu)
        let grade = subject.code.isEmpty ? nil : GradeStore.shared.grade(forSubjectCode: subject.code)

        List {
            Section {
                SubjectHeaderView(subject: subject)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let grade {
                gradeSection(grade)
            }

            if subject.taskList.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: String(localized: "Žádné úkoly"),
                    message: String(localized: "Přidej k tomuto předmětu zkoušku, zápočet nebo projekt."),
                    tint: subject.color,
                    actionTitle: String(localized: "Přidat deadline"),
                    action: { isAddingTask = true }
                )
                .listRowBackground(Color.clear)
            }

            if !active.isEmpty {
                Section("Aktivní (\(active.count))") {
                    ForEach(active) { task in row(for: task) }
                }
            }

            if !examTerms.isEmpty {
                Section {
                    ForEach(examTerms) { term in
                        ExamTermRow(term: term)
                    }
                    Button {
                        selectedTab = "terms"
                    } label: {
                        Label("Všechny termíny", systemImage: "graduationcap")
                    }
                } header: {
                    Text("Termíny zkoušek")
                }
            }

            if !completed.isEmpty {
                Section("Splněné (\(completed.count))") {
                    ForEach(completed) { task in row(for: task) }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(subject.code.isEmpty ? subject.name : subject.code)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Upravit předmět", systemImage: "pencil") { isEditingSubject = true }
                Button("Přidat deadline", systemImage: "plus") { isAddingTask = true }
            }
        }
        .sheet(isPresented: $isAddingTask) { TaskFormSheet(preselectedSubject: subject) }
        .sheet(item: $taskToEdit) { task in TaskFormSheet(task: task) }
        .sheet(item: $taskForCalendar) { task in
            CalendarEventEditor(task: task).ignoresSafeArea()
        }
        .sheet(isPresented: $isEditingSubject) { SubjectFormSheet(subject: subject) }
        .sensoryFeedback(.success, trigger: viewModel.completionFeedback)
    }

    /// Sekce „Hodnocení“: velká známka, zápočet a zkouška (jen části, které STAG uvádí).
    /// - Parameter grade: Hodnocení předmětu ze STAGu.
    /// - Returns: Sekce s hodnocením.
    private func gradeSection(_ grade: SubjectGrade) -> some View {
        Section {
            SubjectGradeSummaryRow(grade: grade)
            if let creditTest = grade.creditTest {
                GradePartDetailRow(title: "Zápočet", symbol: "checkmark.seal.fill", part: creditTest)
            }
            if let exam = grade.exam {
                GradePartDetailRow(title: "Zkouška", symbol: "graduationcap.fill", part: exam)
            }
        } header: {
            Text("Hodnocení")
        }
    }

    /// Řádek úkolu s gesty.
    ///
    /// Klepnutí = úprava, swipe doleva = smazat, dlouhé podržení = kontextové
    /// menu (splnit/obnovit, upravit, přidat do Kalendáře, smazat).
    /// - Parameter task: Zobrazovaný úkol.
    /// - Returns: Řádek úkolu s připojenými akcemi.
    private func row(for task: ExamTask) -> some View {
        TaskRowView(task: task, showsSubject: false) { toggle(task) }
        .contentShape(Rectangle())
        .onTapGesture { taskToEdit = task }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation { viewModel.delete(task, in: modelContext) }
            } label: {
                Label("Smazat", systemImage: "trash")
            }
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
            Divider()
            Button(role: .destructive) {
                withAnimation { viewModel.delete(task, in: modelContext) }
            } label: {
                Label("Smazat", systemImage: "trash")
            }
        }
    }

    /// Animovaně přepne stav splnění úkolu.
    /// - Parameter task: Úkol, jehož stav se přepíná.
    private func toggle(_ task: ExamTask) {
        withAnimation(.snappy) { viewModel.toggleCompletion(task) }
    }
}

/// Řádek termínu zkoušky ze STAGu.
///
/// Zobrazuje datum a čas, typ, příznak opravného termínu, místnost,
/// obsazenost a stav zápisu (zapsáno / zrušeno). Používá se
/// v sekci termínů `SubjectDetailView`.
private struct ExamTermRow: View {
    /// Zobrazovaný termín zkoušky.
    let term: ExamTerm

    /// Začátek termínu, případně doplněný o čas konce.
    private var timeText: String {
        guard let end = term.end else { return term.start.deadlineFormatted }
        return "\(term.start.deadlineFormatted)–\(end.formatted(.dateTime.hour().minute().locale(.czech)))"
    }

    /// Řádek s časem a stavem, pod ním typ, místnost a obsazenost.
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeText)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(term.isCancelled)
                Spacer(minLength: 8)
                if term.isCancelled {
                    Label("Zrušeno", systemImage: "xmark.circle.fill")
                        .labelStyle(.compact)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if term.isRegistered {
                    Label("Zapsáno", systemImage: "checkmark.circle.fill")
                        .labelStyle(.compact)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 12) {
                Label(term.typeName, systemImage: term.taskType.symbol)
                    .labelStyle(.compact)
                if term.isRetake {
                    Text("opravný")
                        .foregroundStyle(.orange)
                }
                if let room = term.room, !room.isEmpty {
                    Label(room, systemImage: "mappin.and.ellipse")
                        .labelStyle(.compact)
                }
                if let occupied = term.occupied, let capacity = term.capacity {
                    Label("\(occupied)/\(capacity)", systemImage: "person.2.fill")
                        .labelStyle(.compact)
                        .foregroundStyle(term.isFull ? .red : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Hlavička detailu předmětu.
///
/// Zobrazuje kroužek postupu, štítek, název, kredity, počty aktivních
/// a splněných úkolů a nejbližší deadline s odpočtem. Používá se
/// jako první sekce `SubjectDetailView`.
private struct SubjectHeaderView: View {
    /// Zobrazovaný předmět.
    let subject: Subject

    /// Karta s kroužkem a názvem, počty úkolů a případně nejbližším deadlinem.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ProgressRingView(progress: subject.progress, color: subject.color)
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 6) {
                    SubjectTag(subject: subject)
                    Text(subject.name)
                        .font(.title3.bold())
                        .lineLimit(3)
                    Text("\(subject.credits) kreditů")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 16) {
                Label("\(subject.activeCount) aktivní", systemImage: "circle")
                Label("\(subject.completedCount) splněné", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .labelStyle(.compact)

            if let next = subject.nextTask {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: next.taskType.symbol)
                        .foregroundStyle(subject.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nejbližší deadline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(next.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    CountdownBadge(task: next)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        SubjectDetailView(subject: SampleData.previewSubject)
    }
    .modelContainer(SampleData.previewContainer)
}
