import SwiftUI
import Observation
import SwiftData

/// ViewModel formuláře předmětu.
///
/// Drží rozpracované hodnoty (název, kód, barva, kredity) odděleně od modelu, takže „Zrušit“ nic nezmění – data se zapíšou až po stisku „Uložit“. Poskytuje také hodnoty pro živý náhled předmětu ve formuláři. Používá ho formulář pro přidání i úpravu předmětu.
@Observable
final class SubjectFormViewModel {
    /// Rozpracovaný název předmětu.
    var name: String
    /// Rozpracovaný kód předmětu (při uložení se převede na velká písmena).
    var code: String
    /// Barva předmětu v hex zápisu; u nového předmětu náhodná z palety.
    var hexColor: String
    /// Počet kreditů; u nového předmětu výchozí 5.
    var credits: Int

    /// Upravovaný předmět; `nil` znamená vytváření nového.
    private let editedSubject: Subject?

    /// Vytvoří ViewModel formuláře a předvyplní hodnoty z upravovaného předmětu.
    /// - Parameter subject: Upravovaný předmět, nebo `nil` pro nový.
    init(subject: Subject? = nil) {
        editedSubject = subject
        name = subject?.name ?? ""
        code = subject?.code ?? ""
        hexColor = subject?.hexColor ?? SubjectPalette.randomHex
        credits = subject?.credits ?? 5
    }

    /// Příznak, zda formulář upravuje existující předmět.
    var isEditing: Bool { editedSubject != nil }

    /// Název i kód jsou povinné.
    var isValid: Bool { !trimmedName.isEmpty && !trimmedCode.isEmpty }

    // MARK: - Živý náhled ve formuláři

    /// Barva pro živý náhled.
    var color: Color { Color(hex: hexColor) }
    /// Iniciály pro živý náhled; bez názvu i kódu „?“.
    var initials: String {
        let value = Subject.initials(name: trimmedName, code: trimmedCode)
        return value.isEmpty ? "?" : value
    }
    /// Název pro živý náhled; při prázdném poli zástupný text.
    var previewName: String { trimmedName.isEmpty ? String(localized: "Název předmětu") : trimmedName }
    /// Řádek s kódem a kredity pro živý náhled, např. „AP9PT · 5 kreditů“.
    var previewDetail: String {
        let code = trimmedCode.isEmpty ? String(localized: "KÓD") : trimmedCode.uppercased()
        let creditsText = String(localized: "\(credits) kreditů")
        return "\(code) · \(creditsText)"
    }

    // MARK: - Uložení

    /// Vytvoří nový nebo upraví existující předmět a vrátí ho (formulář úkolu ho pak rovnou vybere).
    ///
    /// Při úpravě přeplánuje připomínky úkolů předmětu, protože název je v textu notifikací.
    /// - Parameter context: SwiftData kontext, do kterého se předmět ukládá.
    /// - Returns: Uložený předmět.
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

    /// Název bez úvodních a koncových bílých znaků.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Kód bez úvodních a koncových bílých znaků.
    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }
}
