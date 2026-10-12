import Foundation
import Observation
import SwiftData

/// ViewModel detailu předmětu – rozdělení úkolů a akce nad nimi.
///
/// Z úkolů předaného předmětu sestavuje seznam nesplněných a splněných úkolů a přes `TaskService` přepíná jejich splnění a maže je. Používá ho obrazovka detailu předmětu.
@Observable
final class SubjectDetailViewModel {
    /// Zvýší se při každém splnění – View na změnu reaguje haptickou odezvou.
    private(set) var completionFeedback = 0

    /// Nesplněné úkoly od nejbližšího termínu.
    /// - Parameter subject: Předmět, jehož úkoly se vybírají.
    /// - Returns: Seřazené nesplněné úkoly.
    func activeTasks(of subject: Subject) -> [ExamTask] {
        subject.taskList.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
    }

    /// Splněné úkoly od nejpozdějšího termínu.
    /// - Parameter subject: Předmět, jehož úkoly se vybírají.
    /// - Returns: Seřazené splněné úkoly.
    func completedTasks(of subject: Subject) -> [ExamTask] {
        subject.taskList.filter(\.isCompleted).sorted { $0.dueDate > $1.dueDate }
    }

    /// Přepne stav splnění úkolu přes `TaskService`; při splnění zvýší ``completionFeedback``.
    /// - Parameter task: Úkol, jehož stav se mění.
    func toggleCompletion(_ task: ExamTask) {
        TaskService.toggleCompletion(task)
        if task.isCompleted { completionFeedback += 1 }
    }

    /// Smaže úkol přes `TaskService`.
    /// - Parameters:
    ///   - task: Úkol ke smazání.
    ///   - context: SwiftData kontext, ze kterého se úkol odstraní.
    func delete(_ task: ExamTask, in context: ModelContext) {
        TaskService.delete(task, in: context)
    }
}
