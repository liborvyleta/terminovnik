import Foundation
import SwiftData
import Testing
@testable import ZavernyProjekt

/// Formulář deadlinu: výchozí hodnoty, validace a informace o připomínce.
///
/// `save(in:)` a `delete(in:)` se záměrně netestují: kromě zápisu do kontextu volají
/// `NotificationManager.shared.updateReminder` (naplánuje skutečnou notifikaci) a přes `TaskService.save`
/// i `WidgetSync.refresh`, který přepíše data widgetu v App Group uživatele.
@MainActor
@Suite("Formulář deadlinu")
struct TaskFormViewModelTests {
    let container: ModelContainer
    let context: ModelContext
    let subject: Subject

    init() throws {
        container = try makeInMemoryContainer()
        context = container.mainContext
        subject = Subject(name: "Pokročilé mobilní technologie", code: "AP9PT", hexColor: "#3E63DD", credits: 5)
        context.insert(subject)
    }

    // MARK: - Výchozí hodnoty

    @Test("Nový úkol: prázdný formulář, zkouška, termín za týden v 9:00")
    func newTaskDefaults() {
        let viewModel = TaskFormViewModel()
        #expect(!viewModel.isEditing)
        #expect(viewModel.title.isEmpty)
        #expect(viewModel.taskType == .zkouska)
        #expect(viewModel.note.isEmpty)
        #expect(viewModel.selectedSubject == nil)
        #expect(!viewModel.isCompleted)
        #expect(viewModel.pointsOrGrade.isEmpty)

        let calendar = Calendar.current
        #expect(viewModel.dueDate.calendarDays(from: .now) == 7)
        #expect(calendar.component(.hour, from: viewModel.dueDate) == 9)
        #expect(calendar.component(.minute, from: viewModel.dueDate) == 0)
    }

    @Test("Předvybraný předmět se nastaví")
    func preselectedSubject() {
        let viewModel = TaskFormViewModel(preselectedSubject: subject)
        #expect(viewModel.selectedSubject === subject)
        #expect(!viewModel.isEditing)
    }

    @Test("Úprava existujícího úkolu předvyplní formulář")
    func editingPrefills() {
        let due = makeDate(2027, 1, 14, 9, 0)
        let task = ExamTask(title: "Zkouška – 1. termín", taskType: .zapocet, dueDate: due,
                            isCompleted: true, pointsOrGrade: "A", note: "Učebna 52/202")
        context.insert(task)
        task.subject = subject

        let viewModel = TaskFormViewModel(task: task)
        #expect(viewModel.isEditing)
        #expect(viewModel.title == "Zkouška – 1. termín")
        #expect(viewModel.taskType == .zapocet)
        #expect(viewModel.dueDate == due)
        #expect(viewModel.note == "Učebna 52/202")
        #expect(viewModel.isCompleted)
        #expect(viewModel.pointsOrGrade == "A")
        #expect(viewModel.selectedSubject === subject)
        #expect(viewModel.isValid)
    }

    @Test("Předmět úkolu má přednost před předvybraným")
    func taskSubjectWins() {
        let other = Subject(name: "Datamining", code: "AP9DM", hexColor: "#12A594")
        context.insert(other)
        let task = ExamTask(title: "Test", taskType: .ukol, dueDate: .now)
        context.insert(task)
        task.subject = subject

        let viewModel = TaskFormViewModel(task: task, preselectedSubject: other)
        #expect(viewModel.selectedSubject === subject)
    }

    // MARK: - Validace

    @Test("Povinný je název (bez mezer) i předmět")
    func validation() {
        let viewModel = TaskFormViewModel()
        #expect(!viewModel.isValid)

        viewModel.title = "Zkouška"
        #expect(!viewModel.isValid, "Bez předmětu nesmí jít uložit")

        viewModel.selectedSubject = subject
        #expect(viewModel.isValid)

        viewModel.title = "   \n\t"
        #expect(!viewModel.isValid, "Název jen z mezer je prázdný")

        viewModel.title = "  Projekt  "
        #expect(viewModel.isValid)

        viewModel.selectedSubject = nil
        #expect(!viewModel.isValid)
    }

    // MARK: - Připomínka

    @Test("Splněný úkol připomínku nemá")
    func reminderCompleted() {
        let viewModel = TaskFormViewModel()
        viewModel.dueDate = Date.now.addingTimeInterval(5 * 86_400)
        viewModel.isCompleted = true
        #expect(!viewModel.willScheduleReminder)
        #expect(viewModel.reminderInfo == "Úkol je splněný, připomínka je vypnutá.")
    }

    @Test("Termín v minulosti")
    func reminderPast() {
        let viewModel = TaskFormViewModel()
        viewModel.dueDate = Date.now.addingTimeInterval(-3_600)
        #expect(!viewModel.willScheduleReminder)
        #expect(viewModel.reminderInfo == "Termín už proběhl.")
    }

    @Test("Termín za méně než 24 hodin – připomínka už se nenaplánuje")
    func reminderTooSoon() {
        let viewModel = TaskFormViewModel()
        viewModel.dueDate = Date.now.addingTimeInterval(12 * 3_600)
        #expect(!viewModel.willScheduleReminder)
        #expect(viewModel.reminderInfo == "Termín je za méně než 24 hodin, připomínka se už nenaplánuje.")
    }

    @Test("Termín za 3 dny – připomínka den předem")
    func reminderScheduled() throws {
        let viewModel = TaskFormViewModel()
        let due = Date.now.addingTimeInterval(3 * 86_400)
        viewModel.dueDate = due
        #expect(viewModel.willScheduleReminder)
        #expect(viewModel.reminderInfo.hasPrefix("Připomínka: "))

        let fireDate = try #require(NotificationManager.reminderDate(for: due))
        #expect(fireDate.calendarDays(from: due) == -1)
        #expect(Calendar.current.dateComponents([.hour, .minute], from: fireDate)
                == Calendar.current.dateComponents([.hour, .minute], from: due))
        #expect(viewModel.reminderInfo == "Připomínka: \(fireDate.deadlineLongFormatted)")
    }
}
