import SwiftUI
import SwiftData

/// Detail předmětu: kroužek s postupem, souhrn a seznam všech úkolů předmětu.
struct SubjectDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let subject: Subject

    @State private var viewModel = SubjectDetailViewModel()
    @State private var isAddingTask = false
    @State private var isEditingSubject = false
    @State private var taskToEdit: ExamTask?
    /// Úkol, pro který je otevřený editor události v Kalendáři
    @State private var taskForCalendar: ExamTask?

    var body: some View {
        let active = viewModel.activeTasks(of: subject)
        let completed = viewModel.completedTasks(of: subject)

        List {
            Section {
                SubjectHeaderView(subject: subject)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if subject.tasks.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "Žádné úkoly",
                    message: "Přidej k tomuto předmětu zkoušku, zápočet nebo projekt.",
                    tint: subject.color,
                    actionTitle: "Přidat deadline",
                    action: { isAddingTask = true }
                )
                .listRowBackground(Color.clear)
            }

            if !active.isEmpty {
                Section("Aktivní (\(active.count))") {
                    ForEach(active) { task in row(for: task) }
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

    /// Řádek s gesty: klepnutí = úprava, swipe doleva = smazat, dlouhé podržení = kontextové menu
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

    private func toggle(_ task: ExamTask) {
        withAnimation(.snappy) { viewModel.toggleCompletion(task) }
    }
}

/// Hlavička detailu: kroužek postupu, název, kredity a nejbližší deadline.
private struct SubjectHeaderView: View {
    let subject: Subject

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
                    Text("\(subject.credits) \(CzechPlural.credits(subject.credits))")
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
