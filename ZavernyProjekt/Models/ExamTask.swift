import Foundation
import SwiftData

/// Jedna studijní povinnost s termínem: zkouška, zápočet, projekt nebo úkol.
@Model
final class ExamTask {
    // Kompatibilita s CloudKit: žádné `@Attribute(.unique)`, každá vlastnost má výchozí hodnotu
    // nebo je volitelná. Výchozí hodnoty nemění schéma úložiště → lehká migrace projde bez ztráty dat.

    /// Jedinečný identifikátor – použije se i jako ID lokální notifikace.
    /// Jedinečnost hlídá aplikace (UUID), ne databázové omezení – to CloudKit nepodporuje.
    var id: UUID = UUID()
    /// Název (např. „Zkouška – 1. termín“)
    var title: String = ""
    /// Typ povinnosti
    var taskType: TaskType = TaskType.ukol
    /// Datum a čas termínu
    var dueDate: Date = Date.now
    /// Je povinnost splněná?
    var isCompleted: Bool = false
    /// Výsledek – body nebo známka (typicky se vyplní po splnění)
    var pointsOrGrade: String?
    /// Volitelná poznámka (místnost, pomůcky, požadavky…)
    var note: String = ""
    /// Předmět, ke kterému povinnost patří. Inverzní strana vazby je `Subject.tasks`.
    var subject: Subject?
    /// ID termínu ve STAGu (termIdno), pokud úkol vznikl ze zapsaného termínu zkoušky.
    /// Volitelná vlastnost – SwiftData databázi zmigruje automaticky.
    var stagTermID: String?
    /// Čas poslední změny – při slučování zálohy (a synchronizaci) vyhrává novější verze.
    /// Volitelné (nil u starších záznamů) → lehká migrace SwiftData. Nastavuje `TaskService.save`.
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        taskType: TaskType,
        dueDate: Date,
        isCompleted: Bool = false,
        pointsOrGrade: String? = nil,
        note: String = "",
        stagTermID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.taskType = taskType
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.pointsOrGrade = pointsOrGrade
        self.note = note
        self.stagTermID = stagTermID
        self.updatedAt = .now
    }
}

// MARK: - Odvozené vlastnosti

extension ExamTask {
    /// Termín už uplynul a povinnost není splněná
    var isOverdue: Bool { !isCompleted && dueDate < .now }

    /// Identifikátor lokální notifikace – díky němu jde připomínku kdykoli zrušit nebo přeplánovat
    var notificationID: String { "deadline-\(id.uuidString)" }
}
