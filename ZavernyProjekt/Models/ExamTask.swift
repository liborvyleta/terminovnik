import Foundation
import SwiftData

/// Jedna studijní povinnost s termínem: zkouška, zápočet, projekt nebo úkol.
///
/// SwiftData model. Patří volitelně k jednomu předmětu (`subject`); inverzní stranou vazby je
/// `Subject.tasks` s pravidlem `.cascade`, takže smazáním předmětu zmizí i jeho povinnosti.
/// Smazání povinnosti předmět neovlivní. Může vzniknout ručně, ze Siri/Zkratek
/// (`AddDeadlineIntent`) nebo ze zapsaného termínu zkoušky ve STAGu (`stagTermID`).
@Model
final class ExamTask {
    // Kompatibilita s CloudKit: žádné `@Attribute(.unique)`, každá vlastnost má výchozí hodnotu
    // nebo je volitelná. Výchozí hodnoty nemění schéma úložiště → lehká migrace projde bez ztráty dat.

    /// Jedinečný identifikátor – je i součástí ID lokální notifikace (`notificationID`).
    ///
    /// Jedinečnost hlídá aplikace (UUID), ne databázové omezení – to CloudKit nepodporuje.
    var id: UUID = UUID()
    /// Název povinnosti (např. „Zkouška – 1. termín“).
    var title: String = ""
    /// Typ povinnosti; ukládá se jako text (`TaskType.rawValue`).
    var taskType: TaskType = TaskType.ukol
    /// Datum a čas termínu.
    var dueDate: Date = Date.now
    /// Příznak, že je povinnost splněná.
    var isCompleted: Bool = false
    /// Výsledek – body nebo známka jako volný text (typicky se vyplní po splnění).
    var pointsOrGrade: String?
    /// Volitelná poznámka (místnost, pomůcky, požadavky…); prázdný řetězec = bez poznámky.
    var note: String = ""
    /// Předmět, ke kterému povinnost patří. Inverzní strana vazby je `Subject.tasks`.
    var subject: Subject?
    /// ID termínu ve STAGu (pole `termIdno`), pokud úkol vznikl ze zapsaného termínu zkoušky.
    ///
    /// Volitelná vlastnost – SwiftData databázi zmigruje automaticky.
    var stagTermID: String?
    /// Čas poslední změny – při slučování zálohy (a synchronizaci) vyhrává novější verze.
    ///
    /// Volitelné (nil u starších záznamů) → lehká migrace SwiftData. Nastavuje `TaskService.save`.
    var updatedAt: Date?

    /// Vytvoří novou povinnost; `updatedAt` se nastaví na aktuální čas.
    ///
    /// Předmět se navazuje až po vložení do kontextu (`task.subject = …`).
    /// - Parameters:
    ///   - id: Identifikátor povinnosti, výchozí je nové UUID.
    ///   - title: Název povinnosti.
    ///   - taskType: Typ povinnosti.
    ///   - dueDate: Datum a čas termínu.
    ///   - isCompleted: Zda je povinnost už splněná.
    ///   - pointsOrGrade: Výsledek – body nebo známka.
    ///   - note: Poznámka.
    ///   - stagTermID: ID termínu ve STAGu, pokud povinnost vznikla z termínu zkoušky.
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
    /// Příznak, že termín už uplynul a povinnost není splněná.
    var isOverdue: Bool { !isCompleted && dueDate < .now }

    /// Identifikátor lokální notifikace ve tvaru `deadline-<UUID>`.
    ///
    /// Díky němu jde připomínku kdykoli zrušit nebo přeplánovat.
    var notificationID: String { "deadline-\(id.uuidString)" }
}
