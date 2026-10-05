import Foundation

/// Sdílené úložiště aplikace a widgetu. Identifikátor musí odpovídat oběma souborům .entitlements.
nonisolated enum AppGroup {
    static let identifier = "group.devplaceholder.OXGLLP23.zkouskovnik"

    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }
}

/// Jeden deadline tak, jak ho potřebuje widget (widget nemá přístup k databázi SwiftData).
nonisolated struct WidgetDeadline: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let subjectCode: String
    let subjectName: String
    /// Barva předmětu „#RRGGBB“
    let hexColor: String
    /// Český název typu („Zkouška“, „Zápočet“…)
    let typeTitle: String
    /// SF Symbol typu
    let typeSymbol: String
    let dueDate: Date
}

/// Přehled nejbližších nesplněných deadlinů seřazených od nejbližšího (včetně těch po termínu).
/// Aplikace ho zapisuje po každé změně dat, widget ho jen čte.
nonisolated struct WidgetSnapshot: Codable {
    var deadlines: [WidgetDeadline]
    var generatedAt: Date

    private static let storageKey = "widgetSnapshot.v1"

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults?.set(data, forKey: Self.storageKey)
    }
}
