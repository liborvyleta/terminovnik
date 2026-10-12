import SwiftUI
import Testing
import UIKit
@testable import ZavernyProjekt

/// Testy převodu hex řetězce na barvu a palety barev předmětů.
///
/// Ověřují `Color(hex:)` včetně záložní šedé pro neplatný vstup, unikátnost barev a jejich názvů
/// pro VoiceOver, cyklení indexu přes paletu a výběr náhodné barvy.
@Suite("Barvy a paleta předmětů")
struct ColorPaletteTests {
    /// Složky barvy v rozsahu 0–1 pro porovnání s tolerancí.
    ///
    /// Slouží k porovnání vyřešené barvy s očekávanými hodnotami RGB.
    private struct RGBA: Equatable {
        let red: Double, green: Double, blue: Double, alpha: Double

        /// Porovná dvě barvy po složkách s tolerancí.
        ///
        /// - Parameters:
        ///   - other: Barva, se kterou se porovnává.
        ///   - tolerance: Maximální povolený rozdíl každé složky, výchozí 0,003.
        /// - Returns: `true`, pokud se všechny složky liší méně než o toleranci.
        func isClose(to other: RGBA, tolerance: Double = 0.003) -> Bool {
            abs(red - other.red) < tolerance && abs(green - other.green) < tolerance
                && abs(blue - other.blue) < tolerance && abs(alpha - other.alpha) < tolerance
        }
    }

    /// Rozloží SwiftUI barvu na složky RGBA ve světlém režimu.
    ///
    /// - Parameter color: Barva k rozložení.
    /// - Returns: Složky barvy v rozsahu 0–1.
    private func components(_ color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(red: r, green: g, blue: b, alpha: a)
    }

    /// Převede složky 0–255 na očekávanou neprůhlednou barvu.
    ///
    /// - Parameters:
    ///   - red: Červená složka 0–255.
    ///   - green: Zelená složka 0–255.
    ///   - blue: Modrá složka 0–255.
    /// - Returns: Složky v rozsahu 0–1 s alfou 1.
    private func expected(_ red: Int, _ green: Int, _ blue: Int) -> RGBA {
        RGBA(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1)
    }

    @Test("Platný hex s mřížkou, bez ní, malými písmeny i s mezerami")
    func validHex() {
        let indigo = expected(0x3E, 0x63, 0xDD)
        #expect(components(Color(hex: "#3E63DD")).isClose(to: indigo))
        #expect(components(Color(hex: "3E63DD")).isClose(to: indigo))
        #expect(components(Color(hex: "#3e63dd")).isClose(to: indigo))
        #expect(components(Color(hex: "  #3E63DD\n")).isClose(to: indigo))
        #expect(components(Color(hex: "#000000")).isClose(to: expected(0, 0, 0)))
        #expect(components(Color(hex: "#FFFFFF")).isClose(to: expected(255, 255, 255)))
        #expect(components(Color(hex: "#FF0000")).isClose(to: expected(255, 0, 0)))
    }

    @Test(
        "Neplatný vstup nespadne a vrátí šedou",
        arguments: ["", "#", "#FFF", "FFF", "#GGGGGG", "#12345678", "zelená", "##123456", "#12 456", "0x3E63DD"]
    )
    func invalidHexFallsBackToGray(_ input: String) {
        #expect(components(Color(hex: input)).isClose(to: components(.gray)))
    }

    @Test("Paleta má 12 unikátních barev ve tvaru #RRGGBB")
    func paletteEntries() {
        let entries = SubjectPalette.entries
        #expect(entries.count == 12)
        #expect(Set(entries.map(\.hex)).count == entries.count)
        #expect(Set(entries.map(\.id)).count == entries.count)
        for entry in entries {
            #expect(entry.hex.count == 7, "\(entry.hex)")
            #expect(entry.hex.first == "#")
            #expect(UInt64(entry.hex.dropFirst(), radix: 16) != nil, "\(entry.hex) není platný hex")
            #expect(!entry.name.isEmpty)
            // Barva z palety se nesmí rozpadnout na záložní šedou
            #expect(components(Color(hex: entry.hex)) != components(.gray))
        }
    }

    @Test("Názvy barev pro VoiceOver jsou unikátní")
    func paletteNamesUnique() {
        let names = SubjectPalette.entries.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("hex(index) cyklí přes paletu")
    func paletteIndexWraps() {
        let entries = SubjectPalette.entries
        #expect(SubjectPalette.hex(0) == entries[0].hex)
        #expect(SubjectPalette.hex(11) == entries[11].hex)
        #expect(SubjectPalette.hex(12) == entries[0].hex)
        #expect(SubjectPalette.hex(25) == entries[1].hex)
    }

    @Test("Náhodná barva je vždy z palety")
    func randomHexFromPalette() {
        let allowed = Set(SubjectPalette.entries.map(\.hex))
        for _ in 0..<50 {
            #expect(allowed.contains(SubjectPalette.randomHex))
        }
    }
}
