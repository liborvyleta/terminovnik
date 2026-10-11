import SwiftUI
import Observation
import SwiftData

/// ViewModel formuláře předmětu. Drží rozpracované hodnoty odděleně od modelu,
/// takže „Zrušit“ nic nezmění – data se zapíšou až po stisku „Uložit“.
@Observable
final class SubjectFormViewModel {
    var name: String
    var code: String
    var hexColor: String
    var credits: Int

    private let editedSubject: Subject?

    init(subject: Subject? = nil) {
        editedSubject = subject
        name = subject?.name ?? ""
        code = subject?.code ?? ""
        hexColor = subject?.hexColor ?? SubjectPalette.randomHex
        credits = subject?.credits ?? 5
    }

    var isEditing: Bool { editedSubject != nil }

    /// Název i kód jsou povinné
    var isValid: Bool { !trimmedName.isEmpty && !trimmedCode.isEmpty }

    // MARK: - Živý náhled ve formuláři

    var color: Color { Color(hex: hexColor) }
    var initials: String {
        let value = Subject.initials(name: trimmedName, code: trimmedCode)
        return value.isEmpty ? "?" : value
    }
    var previewName: String { trimmedName.isEmpty ? String(localized: "Název předmětu") : trimmedName }
    var previewDetail: String {
        let code = trimmedCode.isEmpty ? String(localized: "KÓD") : trimmedCode.uppercased()
        let creditsText = String(localized: "\(credits) kreditů")
        return "\(code) · \(creditsText)"
    }

    // MARK: - Uložení

    /// Vytvoří nový nebo upraví existující předmět a vrátí ho (formulář úkolu ho pak rovnou vybere).
    @discardableResult
    func save(in context: ModelContext) -> Subject {
        let subject: Subject
        if let editedSubject {
            subject = editedSubject
            subject.name = trimmedName
            subject.code = trimmedCode.uppercased()
            subject.hexColor = hexColor
            subject.credits = credits
            // Název předmětu je v textu notifikací – přeplánujeme je s novým názvem.
            subject.taskList.forEach(NotificationManager.shared.updateReminder)
        } else {
            subject = Subject(name: trimmedName, code: trimmedCode.uppercased(), hexColor: hexColor, credits: credits)
            context.insert(subject)
        }
        TaskService.save(context)
        return subject
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }
}
