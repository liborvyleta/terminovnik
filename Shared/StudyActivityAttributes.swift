import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity pro probíhající / nadcházející hodinu nebo zkoušku.
///
/// Sdíleno aplikací (spouští ji) a widgetem (kreslí zamčenou obrazovku a Dynamic Island).
nonisolated struct StudyActivityAttributes: ActivityAttributes {
    /// Druh sledované události.
    enum Kind: String, Codable, Hashable {
        /// Hodina z rozvrhu (přednáška, cvičení…)
        case lesson
        /// Zkouška nebo jiný deadline z aplikace
        case exam
    }

    /// Měnitelná část – aplikace ji může aktualizovat.
    struct ContentState: Codable, Hashable {
        /// Začátek hodiny / termín zkoušky.
        var start: Date
        /// Konec hodiny; u deadlinu bez délky stejný jako `start`.
        var end: Date
        /// Místnost („52/202“) nebo poznámka.
        var location: String?
    }

    /// Druh události – hodina, nebo zkouška.
    var kind: Kind
    /// Kód předmětu, např. „AP9PT“.
    var subjectCode: String
    /// Název předmětu nebo zkoušky.
    var title: String
    /// Typ: „Cvičení“, „Přednáška“, „Zkouška“, „Projekt“…
    var typeName: String
    /// Barva předmětu „#RRGGBB“.
    var hexColor: String
}
#endif
