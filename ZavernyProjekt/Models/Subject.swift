import SwiftUI
import SwiftData

/// Studijní předmět (např. „Programování mobilních aplikací“, kód AP9PT).
/// Předmět vlastní seznam svých úkolů – při jeho smazání se smažou i úkoly.
@Model
final class Subject {
    // Kompatibilita s CloudKit: žádné `@Attribute(.unique)`, výchozí hodnoty, volitelná vazba s inverzí.
    // Nic z toho nemění strukturu úložiště nad rámec lehké migrace (data zůstanou).

    /// Jedinečný identifikátor předmětu (jedinečnost hlídá aplikace)
    var id: UUID = UUID()
    /// Celý název předmětu
    var name: String = ""
    /// Zkratka / kód předmětu (např. AP9PT)
    var code: String = ""
    /// Barva předmětu ve formátu „#RRGGBB“ (SwiftUI `Color` neumí SwiftData uložit přímo)
    var hexColor: String = "#007AFF"
    /// Počet kreditů
    var credits: Int = 0

    /// Vazba 1:N na úkoly.
    /// `.cascade` = smazáním předmětu zmizí i všechny jeho úkoly.
    /// `inverse` propojuje vazbu s `ExamTask.subject`, SwiftData pak drží obě strany v souladu.
    @Relationship(deleteRule: .cascade, inverse: \ExamTask.subject)
    /// Volitelná kvůli CloudKitu; v kódu se používá `taskList`.
    var tasks: [ExamTask]? = []

    /// Čas poslední změny (viz `ExamTask.updatedAt`)
    var updatedAt: Date?

    init(id: UUID = UUID(), name: String, code: String, hexColor: String, credits: Int = 0) {
        self.id = id
        self.name = name
        self.code = code
        self.hexColor = hexColor
        self.credits = credits
        self.updatedAt = .now
    }
}

// MARK: - Odvozené vlastnosti (neukládají se do databáze)

extension Subject {
    /// Úkoly předmětu (prázdné pole místo nil)
    var taskList: [ExamTask] {
        get { tasks ?? [] }
        set { tasks = newValue }
    }

    /// Barva předmětu převedená z hex řetězce
    var color: Color { Color(hex: hexColor) }

    /// Počet splněných úkolů
    var completedCount: Int { taskList.filter(\.isCompleted).count }

    /// Počet nesplněných úkolů
    var activeCount: Int { taskList.count - completedCount }

    /// Podíl splněných úkolů v rozsahu 0…1 (pro progress bar a kroužek)
    var progress: Double {
        taskList.isEmpty ? 0 : Double(completedCount) / Double(taskList.count)
    }

    /// Nejbližší nesplněný úkol
    var nextTask: ExamTask? {
        taskList.filter { !$0.isCompleted }.min { $0.dueDate < $1.dueDate }
    }

    /// Iniciály pro „avatar“ předmětu
    var initials: String { Subject.initials(name: name, code: code) }

    /// Iniciály z prvních dvou slov názvu, jako záloha první dva znaky kódu.
    /// Statická, aby ji mohl použít i formulář ještě před vytvořením předmětu.
    static func initials(name: String, code: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        let result = letters.joined()
        return result.isEmpty ? String(code.prefix(2)).uppercased() : result
    }
}
