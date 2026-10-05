import Foundation

// Pohodlné varianty sdíleného odpočtu pro SwiftData model ExamTask (jen v aplikaci).

extension DeadlineUrgency {
    init(task: ExamTask, now: Date = .now) {
        self.init(dueDate: task.dueDate, isCompleted: task.isCompleted, now: now)
    }
}

extension Countdown {
    static func text(for task: ExamTask, now: Date = .now) -> String {
        text(for: task.dueDate, isCompleted: task.isCompleted, now: now)
    }
}
