import SwiftUI

extension Color {
    /// Vytvoří barvu z hex řetězce ve tvaru „#RRGGBB“ nebo „RRGGBB“.
    /// Při neplatném vstupu vrátí šedou, aby aplikace nikdy nespadla.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .gray
            return
        }

        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Paleta barev pro předměty. Všechny odstíny mají dostatečný kontrast s bílým textem
/// a dobře vypadají ve světlém i tmavém režimu.
enum SubjectPalette {
    struct Entry: Identifiable {
        let hex: String
        let name: String
        var id: String { hex }
    }

    static let entries: [Entry] = [
        Entry(hex: "#E5484D", name: "Červená"),
        Entry(hex: "#F76B15", name: "Oranžová"),
        Entry(hex: "#B8860B", name: "Zlatá"),
        Entry(hex: "#30A46C", name: "Zelená"),
        Entry(hex: "#12A594", name: "Tyrkysová"),
        Entry(hex: "#00A2C7", name: "Azurová"),
        Entry(hex: "#0090FF", name: "Modrá"),
        Entry(hex: "#3E63DD", name: "Indigová"),
        Entry(hex: "#8E4EC6", name: "Fialová"),
        Entry(hex: "#D6409F", name: "Růžová"),
        Entry(hex: "#A0632E", name: "Hnědá"),
        Entry(hex: "#687076", name: "Šedá")
    ]

    /// Náhodná barva pro nový předmět
    static var randomHex: String { entries.randomElement()?.hex ?? "#3E63DD" }

    /// Hex barvy podle indexu v paletě (pro ukázková data)
    static func hex(_ index: Int) -> String { entries[index % entries.count].hex }
}
