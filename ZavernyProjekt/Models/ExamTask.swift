import Foundation
import SwiftData

/// Jedna studijní povinnost s termínem: zkouška, zápočet, projekt nebo úkol.
@Model
final class ExamTask {
    /// Jedinečný identifikátor – použije se i jako ID lokální notifikace
    @Attribute(.unique) var id: UUID
    /// Název (např. „Zkouška – 1. termín“)
    var title: String
    /// Typ povinnosti
    var taskType: TaskType
    /// Datum a čas termínu
    var dueDate: Date
    /// Je povinnost splněná?
    var isCompleted: Bool
    /// Výsledek – body nebo známka (typicky se vyplní po splnění)
    var pointsOrGrade: String?
    /// Volitelná poznámka (místnost, pomůcky, požadavky…)
    var note: String
    /// Předmět, ke kterému povinnost patří. Inverzní strana vazby je `Subject.tasks`.
    var subject: Subject?

    init(
        id: UUID = UUID(),
        title: String,
        taskType: TaskType,
        dueDate: Date,
        isCompleted: Bool = false,
        pointsOrGrade: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.taskType = taskType
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.pointsOrGrade = pointsOrGrade
        self.note = note
    }
}

// MARK: - Odvozené vlastnosti

extension ExamTask {
    /// Termín už uplynul a povinnost není splněná
    var isOverdue: Bool { !isCompleted && dueDate < .now }

    /// Identifikátor lokální notifikace – díky němu jde připomínku kdykoli zrušit nebo přeplánovat
    var notificationID: String { "deadline-\(id.uuidString)" }
}
