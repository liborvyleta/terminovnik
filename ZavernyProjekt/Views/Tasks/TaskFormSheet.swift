import SwiftUI
import SwiftData

/// Formulář pro přidání nebo úpravu deadlinu.
///
/// Obsahuje předmět, název, typ, termín s časem, informaci o připomínce, poznámku, přidání
/// do Kalendáře a při úpravě i stav, hodnocení a smazání. Předměty čte přes `@Query`, stav a uložení
/// řeší `TaskFormViewModel`. Uživatel může uložit, zrušit, vytvořit nový předmět, otevřít editor
/// události v Kalendáři a smazat deadline. Otevírá se jako sheet z Přehledu a z detailu předmětu.
struct TaskFormSheet: View {
    /// Akce pro zavření sheetu.
    @Environment(\.dismiss) private var dismiss
    /// Kontext SwiftData pro uložení a smazání.
    @Environment(\.modelContext) private var modelContext
    /// Předměty seřazené podle názvu pro výběr.
    @Query(sort: \Subject.name) private var subjects: [Subject]

    /// ViewModel s hodnotami formuláře, validací a ukládáním.
    @State private var viewModel: TaskFormViewModel
    /// Zobrazení formuláře nového předmětu.
    @State private var isAddingSubject = false
    /// Zobrazení potvrzení smazání.
    @State private var isConfirmingDelete = false
    /// Brání dvojitému uložení, než se vyřeší dialog s povolením notifikací.
    @State private var isSaving = false
    /// Zobrazení editoru události v Kalendáři.
    @State private var isAddingToCalendar = false

    /// Vytvoří formulář pro nový nebo upravovaný deadline.
    /// - Parameters:
    ///   - task: upravovaný úkol, `nil` = nový
    ///   - preselectedSubject: předvybraný předmět (při přidávání z detailu předmětu)
    init(task: ExamTask? = nil, preselectedSubject: Subject? = nil) {
        _viewModel = State(initialValue: TaskFormViewModel(task: task, preselectedSubject: preselectedSubject))
    }

    /// Formulář se sekcemi v navigaci; tlačítka Zrušit/Uložit (uložení po žádosti o notifikace),
    /// sheety pro nový předmět a Kalendář a potvrzovací dialog smazání.
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

    /// Výběr předmětu (nebo upozornění, že žádný neexistuje) a tlačítko „Nový předmět“.
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

    /// Název, typ a termín deadlinu.
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

    /// Informace, zda a kdy přijde připomínka.
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

    /// Víceřádková poznámka.
    private var noteSection: some View {
        Section("Poznámka") {
            TextField("Místnost, pomůcky, požadavky…", text: $viewModel.note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    /// Tlačítko pro otevření editoru události v Kalendáři (jen u platného formuláře).
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

    /// Přepínač splnění a pole pro body či známku (jen při úpravě).
    private var resultSection: some View {
        Section("Stav a hodnocení") {
            Toggle("Splněno", isOn: $viewModel.isCompleted.animation())
            TextField("Body / známka (např. 85 b, A)", text: $viewModel.pointsOrGrade)
        }
    }

    /// Tlačítko pro smazání deadlinu s potvrzením (jen při úpravě).
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
