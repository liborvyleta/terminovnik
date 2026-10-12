import SwiftUI

// MARK: - Barvy a texty úrovní známek

/// Barvy a symboly úrovní známek pro štítky.
extension GradeLevel {
    /// Barva štítku. Odstíny z palety předmětů – mají kontrast s bílým textem
    /// a čitelné jsou i jako barevný text na světlém i tmavém pozadí.
    var color: Color {
        switch self {
        case .excellent, .passed: Color(hex: "#30A46C")   // zelená
        case .veryGood: Color(hex: "#12A594")             // mátová / tyrkysová
        case .good: Color(hex: "#0090FF")                 // modrá
        case .sufficient: Color(hex: "#F76B15")           // oranžová
        case .failed, .notPassed: Color(hex: "#E5484D")   // červená
        case .unknown: Color(hex: "#8B8D98")              // šedá
        }
    }

    /// Symbol místo textu – zápočet splněn / nesplněn (`nil` = zobrazí se text).
    var symbol: String? {
        switch self {
        case .passed: "checkmark"
        case .notPassed: "xmark"
        default: nil
        }
    }

    /// Úroveň podle číselné hodnoty (známka nebo průměr): 1 výborně … 4 nevyhověl.
    /// - Parameter value: číselná známka nebo průměr.
    /// - Returns: odpovídající úroveň známky.
    nonisolated static func forNumericValue(_ value: Double) -> GradeLevel {
        switch value {
        case ..<1.25: .excellent
        case ..<2.25: .veryGood
        case ..<2.75: .good
        case ..<3.5: .sufficient
        default: .failed
        }
    }
}

/// Slovní hodnocení známek pro VoiceOver a texty.
extension SubjectGrade {
    /// Slovní hodnocení známky: „Výborně“, „Velmi dobře“, „Započteno“…
    /// - Parameter grade: známka ze STAGu (písmeno, číslo nebo zápočet).
    /// - Returns: slovní hodnocení, nebo `nil` u neznámé známky.
    static func verbalText(_ grade: String) -> String? {
        if let value = numericValue(grade) { return verbalText(value: value) }
        switch level(grade) {
        case .passed: return String(localized: "Započteno", comment: "Slovní hodnocení zápočtu Z")
        case .notPassed: return String(localized: "Nezapočteno", comment: "Slovní hodnocení nesplněného zápočtu")
        default: return nil
        }
    }

    /// Slovní hodnocení číselné hodnoty (známky i průměru): 1 „Výborně“ … 4 „Nedostatečně“.
    /// - Parameter value: číselná známka nebo průměr.
    /// - Returns: slovní hodnocení.
    static func verbalText(value: Double) -> String {
        switch value {
        case ..<1.25: String(localized: "Výborně", comment: "Slovní hodnocení známky A / 1")
        case ..<1.75: String(localized: "Velmi dobře", comment: "Slovní hodnocení známky B / 1,5")
        case ..<2.25: String(localized: "Dobře", comment: "Slovní hodnocení známky C / 2")
        case ..<2.75: String(localized: "Uspokojivě", comment: "Slovní hodnocení známky D / 2,5")
        case ..<3.5: String(localized: "Dostatečně", comment: "Slovní hodnocení známky E / 3")
        default: String(localized: "Nedostatečně", comment: "Slovní hodnocení známky F / 4")
        }
    }
}

// MARK: - Štítek známky

/// Barevný štítek známky („A“, „1“, zelená fajfka u „Z“).
///
/// Zobrazuje text známky (nebo symbol u zápočtu) v barvě podle `GradeLevel`; data dostává zvenku
/// (`SubjectGrade`, `GradePart` nebo přímo text a úroveň). Nemá akce. Velikost `.small` je jemně
/// podbarvený štítek do karet a řádků (karta předmětu, komponenty známek), `.large` výrazný plný
/// čtverec do detailu předmětu.
struct GradeBadge: View {
    /// Velikost štítku.
    enum Size {
        case small
        case large
    }

    /// Zobrazená známka; `nil` = zatím bez hodnocení (šedá pomlčka).
    let text: String?
    /// Úroveň známky určující barvu a případný symbol.
    let level: GradeLevel
    /// Velikost štítku (výchozí malý).
    var size: Size = .small

    /// Vytvoří štítek z textu a úrovně.
    /// - Parameters:
    ///   - text: zobrazená známka, `nil` = bez hodnocení
    ///   - level: úroveň známky
    ///   - size: velikost štítku
    init(text: String?, level: GradeLevel, size: Size = .small) {
        self.text = text
        self.level = level
        self.size = size
    }

    /// Hlavní známka předmětu (výsledná, jinak ze zkoušky, jinak ze zápočtu).
    /// - Parameters:
    ///   - grade: hodnocení předmětu
    ///   - size: velikost štítku
    init(grade: SubjectGrade, size: Size = .small) {
        self.init(text: grade.displayGrade, level: grade.level, size: size)
    }

    /// Výsledek jedné části hodnocení (zápočet / zkouška).
    /// - Parameters:
    ///   - part: část hodnocení s výsledkem
    ///   - size: velikost štítku
    init(part: GradePart, size: Size = .small) {
        self.init(text: part.result, level: SubjectGrade.level(part.result), size: size)
    }

    /// Barva podle úrovně známky.
    private var color: Color { level.color }

    /// Malý nebo velký štítek sloučený pro VoiceOver do jednoho prvku se slovním popisem.
    var body: some View {
        Group {
            switch size {
            case .small: smallBadge
            case .large: largeBadge
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Malý

    /// Jemně podbarvený štítek s barevným textem a obrysem.
    private var smallBadge: some View {
        content(fontSize: 15, symbolSize: 13)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(minWidth: 30, minHeight: 30)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            }
            .fixedSize()
    }

    // MARK: - Velký

    /// Plný čtverec s přechodem, bílým textem a stínem.
    private var largeBadge: some View {
        content(fontSize: 34, symbolSize: 30)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minWidth: 72, minHeight: 72)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: color.opacity(0.35), radius: 10, y: 5)
            .fixedSize()
    }

    /// Obsah štítku: symbol (u zápočtu), jinak zaoblený text známky.
    /// - Parameters:
    ///   - fontSize: velikost písma textu
    ///   - symbolSize: velikost symbolu
    /// - Returns: symbol nebo text známky.
    @ViewBuilder
    private func content(fontSize: CGFloat, symbolSize: CGFloat) -> some View {
        if let symbol = level.symbol {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .heavy))
        } else {
            Text(verbatim: displayText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// Slovní výsledky („výborně“) ukážeme číslem („1“), ostatní dlouhé zkrátíme – štítek má zůstat malý.
    private var displayText: String {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return "–" }
        guard text.count > 3 else { return text }
        if let value = SubjectGrade.numericValue(text) {
            return value.formatted(.number.precision(.fractionLength(0...1)).locale(.czech))
        }
        return String(text.prefix(3))
    }

    /// Popis pro VoiceOver: známka a její slovní hodnocení, případně „Zatím bez hodnocení“.
    private var accessibilityText: String {
        guard let text, !text.isEmpty else { return String(localized: "Zatím bez hodnocení") }
        if let verbal = SubjectGrade.verbalText(text) {
            return String(localized: "Známka \(text), \(verbal)", comment: "VoiceOver: známka a její slovní hodnocení")
        }
        return String(localized: "Známka \(text)", comment: "VoiceOver: známka")
    }
}

#Preview("Štítky známek") {
    VStack(spacing: 20) {
        HStack(spacing: 10) {
            GradeBadge(text: "A", level: .excellent)
            GradeBadge(text: "B", level: .veryGood)
            GradeBadge(text: "D", level: .good)
            GradeBadge(text: "E", level: .sufficient)
            GradeBadge(text: "F", level: .failed)
            GradeBadge(text: "Z", level: .passed)
            GradeBadge(text: "N", level: .notPassed)
            GradeBadge(text: nil, level: .unknown)
        }
        HStack(spacing: 14) {
            GradeBadge(text: "A", level: .excellent, size: .large)
            GradeBadge(text: "C", level: .veryGood, size: .large)
            GradeBadge(text: "Z", level: .passed, size: .large)
            GradeBadge(text: "F", level: .failed, size: .large)
        }
    }
    .padding()
}
