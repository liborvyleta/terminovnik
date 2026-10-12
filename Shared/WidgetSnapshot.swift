import Foundation

/// Sdílené úložiště aplikace a widgetu (App Group).
///
/// Identifikátor musí odpovídat oběma souborům .entitlements. Přes něj si aplikace a widget
/// předávají přehled deadlinů, rozvrh a frontu odškrtnutých deadlinů.
/// Soubor se kompiluje do aplikace, widgetu i hodinek.
nonisolated enum AppGroup {
    /// Identifikátor App Group.
    static let identifier = "group.cz.liborvyleta.terminovnik"

    /// Sdílené `UserDefaults` skupiny; `nil`, pokud skupina není dostupná (chybí entitlement).
    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }
}

/// Jeden deadline tak, jak ho potřebuje widget.
///
/// Widget nemá přístup k databázi SwiftData, proto dostává hodnoty zkopírované z `ExamTask`.
nonisolated struct WidgetDeadline: Codable, Identifiable, Hashable {
    /// Identifikátor úkolu (`ExamTask.id`).
    let id: UUID
    /// Název povinnosti.
    let title: String
    /// Kód předmětu.
    let subjectCode: String
    /// Název předmětu.
    let subjectName: String
    /// Barva předmětu „#RRGGBB“.
    let hexColor: String
    /// Lokalizovaný název typu („Zkouška“, „Zápočet“…).
    let typeTitle: String
    /// SF Symbol typu.
    let typeSymbol: String
    /// Datum a čas termínu.
    let dueDate: Date
}

/// Přehled nejbližších nesplněných deadlinů seřazených od nejbližšího (včetně těch po termínu).
///
/// Ukládá se jako JSON v App Group. Aplikace ho zapisuje po každé změně dat, widget ho jen čte.
nonisolated struct WidgetSnapshot: Codable {
    /// Deadliny seřazené od nejbližšího.
    var deadlines: [WidgetDeadline]
    /// Okamžik, kdy aplikace přehled vytvořila.
    var generatedAt: Date

    private static let storageKey = "widgetSnapshot.v1"

    /// Načte uložený přehled z App Group.
    /// - Returns: Přehled, nebo `nil`, pokud chybí nebo nejde dekódovat.
    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Uloží přehled do App Group jako JSON (při chybě kódování neudělá nic).
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults?.set(data, forKey: Self.storageKey)
    }
}
