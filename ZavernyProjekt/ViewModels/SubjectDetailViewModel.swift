import Foundation
import Observation
import SwiftData

/// ViewModel detailu předmětu – rozdělení úkolů a akce nad nimi.
@Observable
final class SubjectDetailViewModel {
    private(set) var completionFeedback = 0

    /// Nesplněné úkoly od nejbližšího termínu
    func activeTasks(of subject: Subject) -> [ExamTask] {
        subject.taskList.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
    }

    /// Splněné úkoly od nejpozdějšího termínu
    func completedTasks(of subject: Subject) -> [ExamTask] {
        subject.taskList.filter(\.isCompleted).sorted { $0.dueDate > $1.dueDate }
    }

    func toggleCompletion(_ task: ExamTask) {
        TaskService.toggleCompletion(task)
        if task.isCompleted { completionFeedback += 1 }
    }

    func delete(_ task: ExamTask, in context: ModelContext) {
        TaskService.delete(task, in: context)
    }
}
