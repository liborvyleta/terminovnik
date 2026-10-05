import Foundation
import Observation
import SwiftData

/// ViewModel formuláře pro přidání / úpravu deadlinu.
@Observable
final class TaskFormViewModel {
    var title: String
    var taskType: TaskType
    var dueDate: Date
    var note: String
    var selectedSubject: Subject?
    var isCompleted: Bool
    var pointsOrGrade: String

    /// Upravovaný úkol; `nil` znamená vytváření nového
    private let editedTask: ExamTask?

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

    var isEditing: Bool { editedTask != nil }

    /// Povinný je název a předmět
    var isValid: Bool { !trimmedTitle.isEmpty && selectedSubject != nil }

    // MARK: - Informace o připomínce

    /// Naplánuje se pro aktuální hodnoty formuláře připomínka?
    var willScheduleReminder: Bool {
        guard !isCompleted, let fireDate = NotificationManager.reminderDate(for: dueDate) else { return false }
        return fireDate > .now
    }

    /// Text pod formulářem, kdy přijde notifikace
    var reminderInfo: String {
        if isCompleted { return "Úkol je splněný, připomínka je vypnutá." }
        if dueDate < .now { return "Termín už proběhl." }
        guard willScheduleReminder, let fireDate = NotificationManager.reminderDate(for: dueDate) else {
            return "Termín je za méně než 24 hodin, připomínka se už nenaplánuje."
        }
        return "Připomínka: \(fireDate.deadlineLongFormatted)"
    }

    // MARK: - Uložení a smazání

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

    func delete(in context: ModelContext) {
        guard let editedTask else { return }
        TaskService.delete(editedTask, in: context)
    }

    // MARK: - Pomocné

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Výchozí termín nového úkolu: za týden v 9:00
    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let inAWeek = calendar.date(byAdding: .day, value: 7, to: .now) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: inAWeek) ?? inAWeek
    }
}
