import Foundation

/// Typ studijní povinnosti.
/// `String` rawValue + `Codable` zajišťuje, že SwiftData enum uloží jako stabilní text.
enum TaskType: String, Codable, CaseIterable, Identifiable {
    case zkouska
    case zapocet
    case projekt
    case ukol

    var id: String { rawValue }

    /// Název zobrazovaný v UI
    var title: String {
        switch self {
        case .zkouska: String(localized: "Zkouška")
        case .zapocet: String(localized: "Zápočet")
        case .projekt: String(localized: "Projekt")
        case .ukol: String(localized: "Úkol")
        }
    }

    /// SF Symbol, který typ vizuálně odliší v seznamech
    var symbol: String {
        switch self {
        case .zkouska: "graduationcap.fill"
        case .zapocet: "checkmark.seal.fill"
        case .projekt: "hammer.fill"
        case .ukol: "doc.text.fill"
        }
    }
}
