import Foundation
import Observation
import SwiftData

/// ViewModel formuláře pro přidání / úpravu deadlinu.
///
/// Drží rozpracované hodnoty úkolu odděleně od modelu, validuje je, informuje o plánované připomínce (`NotificationManager`) a ukládá či maže úkol přes `TaskService`. Používá ho formulář úkolu.
@Observable
final class TaskFormViewModel {
    /// Rozpracovaný název úkolu.
    var title: String
    /// Typ úkolu; u nového výchozí zkouška.
    var taskType: TaskType
    /// Termín úkolu; u nového za týden v 9:00.
    var dueDate: Date
    /// Poznámka k úkolu.
    var note: String
    /// Vybraný předmět (povinný).
    var selectedSubject: Subject?
    /// Zda je úkol splněný.
    var isCompleted: Bool
    /// Body nebo známka; prázdný text se uloží jako `nil`.
    var pointsOrGrade: String

    /// Upravovaný úkol; `nil` znamená vytváření nového.
    private let editedTask: ExamTask?

    /// Vytvoří ViewModel formuláře a předvyplní hodnoty z upravovaného úkolu.
    /// - Parameters:
    ///   - task: Upravovaný úkol, nebo `nil` pro nový.
    ///   - preselectedSubject: Předem vybraný předmět pro nový úkol.
    init(task: ExamTask? = nil, preselectedSubject: Subject? = nil) {
        editedTask = task
        title = task?.title ?? ""
        taskType = task?.taskType ?? .zkouska
        dueDate = task?.dueDate ?? Self.defaultDueDate()
        note = task?.note ?? ""
        selectedSubject = task?.subject ?? preselectedSubject
        isCompleted = task?.isCompleted ?? false
        pointsOrGrade = task?.pointsOrGrade ?? ""
    }

    /// Příznak, zda formulář upravuje existující úkol.
    var isEditing: Bool { editedTask != nil }

    /// Povinný je název a předmět.
    var isValid: Bool { !trimmedTitle.isEmpty && selectedSubject != nil }

    // MARK: - Informace o připomínce

    /// Naplánuje se pro aktuální hodnoty formuláře připomínka?
    var willScheduleReminder: Bool {
        guard !isCompleted, let fireDate = NotificationManager.reminderDate(for: dueDate) else { return false }
        return fireDate > .now
    }

    /// Text pod formulářem, kdy přijde notifikace (nebo proč nepřijde).
    var reminderInfo: String {
        if isCompleted { return String(localized: "Úkol je splněný, připomínka je vypnutá.") }
        if dueDate < .now { return String(localized: "Termín už proběhl.") }
        guard willScheduleReminder, let fireDate = NotificationManager.reminderDate(for: dueDate) else {
            return String(localized: "Termín je za méně než 24 hodin, připomínka se už nenaplánuje.")
        }
        return String(localized: "Připomínka: \(fireDate.deadlineLongFormatted)")
    }

    // MARK: - Uložení a smazání

    /// Vytvoří nový nebo upraví existující úkol, uloží ho a přeplánuje jeho připomínku.
    /// - Parameter context: SwiftData kontext, do kterého se úkol ukládá.
    /// - Returns: Uložený úkol.
    @discardableResult
    func save(in context: ModelContext) -> ExamTask {
        let task: ExamTask
        if let editedTask {
            task = editedTask
        } else {
            task = ExamTask(title: trimmedTitle, taskType: taskType, dueDate: dueDate)
            // Objekt nejdřív vložíme do kontextu, až pak nastavujeme vazbu na předmět.
            context.insert(task)
        }

        task.title = trimmedTitle
        task.taskType = taskType
        task.dueDate = dueDate
        task.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        task.isCompleted = isCompleted
        let grade = pointsOrGrade.trimmingCharacters(in: .whitespacesAndNewlines)
        task.pointsOrGrade = grade.isEmpty ? nil : grade
        task.subject = selectedSubject

        TaskService.save(context)
        // Po každé změně (nový termín, splnění…) připomínku přeplánujeme.
        NotificationManager.shared.updateReminder(for: task)
        return task
    }

    /// Smaže upravovaný úkol přes `TaskService`; u nového úkolu nic nedělá.
    /// - Parameter context: SwiftData kontext, ze kterého se úkol odstraní.
    func delete(in context: ModelContext) {
        guard let editedTask else { return }
        TaskService.delete(editedTask, in: context)
    }

    // MARK: - Pomocné

    /// Název bez úvodních a koncových bílých znaků.
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Výchozí termín nového úkolu: za týden v 9:00.
    /// - Returns: Datum za 7 dní v 9:00.
    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let inAWeek = calendar.date(byAdding: .day, value: 7, to: .now) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: inAWeek) ?? inAWeek
    }
}
