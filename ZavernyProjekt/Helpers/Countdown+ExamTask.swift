import Foundation

// Pohodlné varianty sdíleného odpočtu pro SwiftData model ExamTask (jen v aplikaci).

extension DeadlineUrgency {
    /// Určí naléhavost podle termínu a stavu splnění povinnosti.
    /// - Parameters:
    ///   - task: Povinnost, jejíž naléhavost se určuje.
    ///   - now: Referenční okamžik, výchozí je aktuální čas.
    init(task: ExamTask, now: Date = .now) {
        self.init(dueDate: task.dueDate, isCompleted: task.isCompleted, now: now)
    }
}

extension Countdown {
    /// Vrátí lidsky čitelný odpočet do termínu povinnosti („Dnes“, „Za 5 dní“, „Splněno“…).
    /// - Parameters:
    ///   - task: Povinnost, pro kterou se odpočet počítá.
    ///   - now: Referenční okamžik, výchozí je aktuální čas.
    /// - Returns: Lokalizovaný text odpočtu.
    static func text(for task: ExamTask, now: Date = .now) -> String {
        text(for: task.dueDate, isCompleted: task.isCompleted, now: now)
    }
}
