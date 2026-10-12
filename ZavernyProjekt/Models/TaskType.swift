import Foundation

/// Typ studijní povinnosti.
///
/// Používá ho `ExamTask.taskType`. `String` rawValue + `Codable` zajišťuje, že SwiftData enum uloží jako stabilní text.
enum TaskType: String, Codable, CaseIterable, Identifiable {
    case zkouska
    case zapocet
    case projekt
    case ukol

    /// Identifikátor pro `ForEach` a výběry – stejný jako `rawValue`.
    var id: String { rawValue }

    /// Lokalizovaný název zobrazovaný v UI.
    var title: String {
        switch self {
        case .zkouska: String(localized: "Zkouška")
        case .zapocet: String(localized: "Zápočet")
        case .projekt: String(localized: "Projekt")
        case .ukol: String(localized: "Úkol")
        }
    }

    /// Název SF Symbolu, který typ vizuálně odliší v seznamech.
    var symbol: String {
        switch self {
        case .zkouska: "graduationcap.fill"
        case .zapocet: "checkmark.seal.fill"
        case .projekt: "hammer.fill"
        case .ukol: "doc.text.fill"
        }
    }
}
