import SwiftUI
import SwiftData

/// Studijní předmět (např. „Programování mobilních aplikací“, kód AP9PT).
///
/// SwiftData model. Předmět vlastní seznam svých úkolů (`tasks`, vazba 1:N na `ExamTask`
/// s inverzí `ExamTask.subject`) – pravidlo `.cascade` zajistí, že se při smazání předmětu
/// smažou i všechny jeho úkoly.
@Model
final class Subject {
    // Kompatibilita s CloudKit: žádné `@Attribute(.unique)`, výchozí hodnoty, volitelná vazba s inverzí.
    // Nic z toho nemění strukturu úložiště nad rámec lehké migrace (data zůstanou).

    /// Jedinečný identifikátor předmětu (jedinečnost hlídá aplikace).
    var id: UUID = UUID()
    /// Celý název předmětu.
    var name: String = ""
    /// Zkratka / kód předmětu (např. AP9PT).
    var code: String = ""
    /// Barva předmětu ve formátu „#RRGGBB“ (SwiftUI `Color` neumí SwiftData uložit přímo).
    var hexColor: String = "#007AFF"
    /// Počet kreditů.
    var credits: Int = 0

    /// Vazba 1:N na úkoly.
    ///
    /// `.cascade` = smazáním předmětu zmizí i všechny jeho úkoly.
    /// `inverse` propojuje vazbu s `ExamTask.subject`, SwiftData pak drží obě strany v souladu.
    @Relationship(deleteRule: .cascade, inverse: \ExamTask.subject)
    /// Volitelná kvůli CloudKitu; v kódu se používá `taskList`.
    var tasks: [ExamTask]? = []

    /// Čas poslední změny (viz `ExamTask.updatedAt`).
    var updatedAt: Date?

    /// Vytvoří nový předmět bez úkolů; `updatedAt` se nastaví na aktuální čas.
    /// - Parameters:
    ///   - id: Identifikátor předmětu, výchozí je nové UUID.
    ///   - name: Celý název předmětu.
    ///   - code: Kód předmětu.
    ///   - hexColor: Barva ve formátu „#RRGGBB“.
    ///   - credits: Počet kreditů.
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
    /// Úkoly předmětu (prázdné pole místo `nil`); zápis přepíše vazbu `tasks`.
    var taskList: [ExamTask] {
        get { tasks ?? [] }
        set { tasks = newValue }
    }

    /// Barva předmětu převedená z hex řetězce (při neplatné hodnotě šedá).
    var color: Color { Color(hex: hexColor) }

    /// Počet splněných úkolů.
    var completedCount: Int { taskList.filter(\.isCompleted).count }

    /// Počet nesplněných úkolů.
    var activeCount: Int { taskList.count - completedCount }

    /// Podíl splněných úkolů v rozsahu 0…1 (pro progress bar a kroužek); bez úkolů 0.
    var progress: Double {
        taskList.isEmpty ? 0 : Double(completedCount) / Double(taskList.count)
    }

    /// Nesplněný úkol s nejdřívějším termínem (i po termínu), nebo `nil`.
    var nextTask: ExamTask? {
        taskList.filter { !$0.isCompleted }.min { $0.dueDate < $1.dueDate }
    }

    /// Iniciály pro „avatar“ předmětu.
    var initials: String { Subject.initials(name: name, code: code) }

    /// Vytvoří iniciály z prvních dvou slov názvu, jako záloha první dva znaky kódu.
    ///
    /// Slova nezačínající písmenem se přeskakují. Statická, aby ji mohl použít i formulář ještě před vytvořením předmětu.
    /// - Parameters:
    ///   - name: Název předmětu.
    ///   - code: Kód předmětu.
    /// - Returns: Iniciály velkými písmeny (nejvýše dva znaky).
    static func initials(name: String, code: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        let result = letters.joined()
        return result.isEmpty ? String(code.prefix(2)).uppercased() : result
    }
}
