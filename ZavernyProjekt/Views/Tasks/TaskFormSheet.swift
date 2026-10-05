import SwiftUI
import SwiftData

/// Formulář pro přidání nebo úpravu deadlinu:
/// předmět, název, typ, termín s časem, poznámka (a při úpravě i stav a hodnocení).
struct TaskFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var viewModel: TaskFormViewModel
    @State private var isAddingSubject = false
    @State private var isConfirmingDelete = false
    /// Brání dvojitému uložení, než se vyřeší dialog s povolením notifikací
    @State private var isSaving = false
    @State private var isAddingToCalendar = false

    /// - Parameters:
    ///   - task: upravovaný úkol, `nil` = nový
    ///   - preselectedSubject: předvybraný předmět (při přidávání z detailu předmětu)
    init(task: ExamTask? = nil, preselectedSubject: Subject? = nil) {
        _viewModel = State(initialValue: TaskFormViewModel(task: task, preselectedSubject: preselectedSubject))
    }

    var body: some View {
        NavigationStack {
            Form {
                subjectSection
                detailsSection
                reminderSection
                noteSection
                calendarSection
                if viewModel.isEditing {
                    resultSection
                    deleteSection
                }
            }
            .navigationTitle(viewModel.isEditing ? "Upravit deadline" : "Nový deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") {
                        isSaving = true
                        Task {
                            // O povolení notifikací žádáme v kontextu – při ukládání deadlinu
                            // (doporučení Apple HIG). Systém se zeptá jen poprvé, pak hned vrátí stav.
                            await NotificationManager.shared.requestAuthorization()
                            viewModel.save(in: modelContext)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isValid || isSaving)
                }
            }
            .sheet(isPresented: $isAddingSubject) {
                // Nově vytvořený předmět se ve formuláři rovnou vybere
                SubjectFormSheet { newSubject in viewModel.selectedSubject = newSubject }
            }
            .sheet(isPresented: $isAddingToCalendar) {
                // Předvyplní se aktuální (i neuložené) hodnoty z formuláře
                CalendarEventEditor(
                    taskType: viewModel.taskType,
                    subject: viewModel.selectedSubject,
                    taskTitle: viewModel.title,
                    dueDate: viewModel.dueDate,
                    note: viewModel.note
                )
                .ignoresSafeArea()
            }
            .confirmationDialog("Smazat deadline?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Smazat", role: .destructive) {
                    viewModel.delete(in: modelContext)
                    dismiss()
                }
            } message: {
                Text("Tuto akci nelze vrátit.")
            }
        }
    }

    // MARK: - Sekce formuláře

    private var subjectSection: some View {
        Section {
            if subjects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Zatím nemáš žádný předmět", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Každý deadline patří k předmětu. Vytvoř si nejdřív předmět.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Picker("Předmět", selection: $viewModel.selectedSubject) {
                    Text("Nevybráno").tag(Subject?.none)
                    ForEach(subjects) { subject in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(subject.color)
                                .frame(width: 12, height: 12)
                            Text(subject.name)
                            Text(subject.code)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(subject))
                    }
                }
                // Výběr na samostatné obrazovce – zobrazí i barevné tečky předmětů
                .pickerStyle(.navigationLink)
            }

            Button("Nový předmět", systemImage: "plus.circle") { isAddingSubject = true }
        } header: {
            Text("Předmět")
        }
    }

    private var detailsSection: some View {
        Section("Deadline") {
            TextField("Název (např. Zkouška – 1. termín)", text: $viewModel.title)

            Picker("Typ", selection: $viewModel.taskType) {
                ForEach(TaskType.allCases) { type in
                    Label(type.title, systemImage: type.symbol).tag(type)
                }
            }

            DatePicker("Termín", selection: $viewModel.dueDate, displayedComponents: [.date, .hourAndMinute])
        }
    }

    private var reminderSection: some View {
        Section {
            Label(
                viewModel.reminderInfo,
                systemImage: viewModel.willScheduleReminder ? "bell.badge.fill" : "bell.slash"
            )
            .font(.subheadline)
            .foregroundStyle(viewModel.willScheduleReminder ? Color.primary : Color.secondary)
        } header: {
            Text("Připomínka")
        } footer: {
            Text("Lokální notifikace přijde 1 den před termínem.")
        }
    }

    private var noteSection: some View {
        Section("Poznámka") {
            TextField("Místnost, pomůcky, požadavky…", text: $viewModel.note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var calendarSection: some View {
        Section {
            Button("Přidat do Kalendáře", systemImage: "calendar.badge.plus") {
                isAddingToCalendar = true
            }
            .disabled(!viewModel.isValid)
        } footer: {
            Text("Otevře systémový editor události s předvyplněným termínem. Aplikace nepotřebuje přístup ke kalendáři.")
        }
    }

    private var resultSection: some View {
        Section("Stav a hodnocení") {
            Toggle("Splněno", isOn: $viewModel.isCompleted.animation())
            TextField("Body / známka (např. 85 b, A)", text: $viewModel.pointsOrGrade)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Smazat deadline", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        }
    }
}

#Preview("Nový") {
    TaskFormSheet()
        .modelContainer(SampleData.previewContainer)
}
