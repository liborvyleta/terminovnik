import Foundation

/// Jedna část hodnocení předmětu – zápočet nebo zkouška.
nonisolated struct GradePart: Codable, Hashable {
    /// Výsledek tak, jak ho vrací STAG („A“, „1“, „Z“, „započteno“…)
    let result: String
    let date: Date?
    /// Pořadí pokusu (1 = řádný termín)
    let attempt: Int?
    let examiner: String?
    /// Body, pokud je zkoušející zadal
    let points: String?
}

/// Hodnocení předmětu v jednom akademickém roce a semestru (spojení služeb
/// znamky/getZnamkyByStudent a student/getStudentPredmetyAbsolvoval).
nonisolated struct SubjectGrade: Codable, Identifiable, Hashable {
    let code: String
    let department: String
    /// Začátek akademického roku („2026“ = 2026/2027)
    let year: String
    /// „ZS“ / „LS“
    let semester: String
    var name: String?
    var credits: Int?
    /// Zápočet / klasifikovaný zápočet
    var creditTest: GradePart?
    /// Zkouška
    var exam: GradePart?
    /// Výsledná známka předmětu (pokud ji STAG uvádí)
    var finalGrade: String?
    /// Předmět je absolvovaný
    var isPassed: Bool
    /// Předmět byl uznaný (např. z jiného studia)
    var isRecognized: Bool

    var id: String { "\(department)/\(code)/\(year)/\(semester)" }
}

// MARK: - Výklad známek

/// Kategorie známky – určuje barvu štítku
nonisolated enum GradeLevel: Hashable {
    case excellent, veryGood, good, sufficient, failed, passed, notPassed, unknown
}

nonisolated extension SubjectGrade {
    /// Známka, která se zobrazí jako hlavní (výsledná, jinak ze zkoušky, jinak ze zápočtu)
    var displayGrade: String? {
        [finalGrade, exam?.result, creditTest?.result]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// Číselná hodnota pro průměr (A = 1 … F = 4), nil u zápočtu bez klasifikace
    var numericGrade: Double? { displayGrade.flatMap(Self.numericValue) }

    var level: GradeLevel { displayGrade.map(Self.level) ?? .unknown }

    /// „ZS 2026/2027“
    var semesterTitle: String {
        let years = Int(year).map { "\($0)/\($0 + 1)" } ?? year
        switch semester {
        case "ZS": return String(localized: "ZS \(years)", comment: "Zimní semestr, např. „ZS 2026/2027“")
        case "LS": return String(localized: "LS \(years)", comment: "Letní semestr, např. „LS 2026/2027“")
        default: return "\(semester) \(years)"
        }
    }

    /// Řadicí klíč semestru (novější dřív): rok + ZS před LS téhož roku
    var semesterSortKey: Int { (Int(year) ?? 0) * 10 + (semester == "LS" ? 2 : 1) }

    static func numericValue(_ grade: String) -> Double? {
        let text = grade.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: ",", with: ".")
        switch text {
        // Stupnice ECTS (A–F) se slovními ekvivalenty, jak je používá IS/STAG
        case "A", "1", "VÝBORNĚ": return 1
        case "B", "1.5", "VELMI DOBŘE": return 1.5
        case "C", "2", "DOBŘE": return 2
        case "D", "2.5", "USPOKOJIVĚ": return 2.5
        case "E", "3", "DOSTATEČNĚ": return 3
        case "F", "FX", "4", "NEVYHOVĚL", "NEDOSTATEČNĚ": return 4
        default: return nil
        }
    }

    static func level(_ grade: String) -> GradeLevel {
        let text = grade.trimmingCharacters(in: .whitespaces).uppercased()
        if let value = numericValue(text) {
            switch value {
            case ..<1.25: return .excellent
            case ..<2.25: return .veryGood
            case ..<2.75: return .good
            case ..<3.5: return .sufficient
            default: return .failed
            }
        }
        if ["Z", "S", "ZAPOČTENO", "SPLNĚNO", "U", "UZNÁNO"].contains(text) { return .passed }
        if ["N", "NZ", "NEZAPOČTENO", "NESPLNĚNO"].contains(text) { return .notPassed }
        return .unknown
    }
}

// MARK: - Souhrny

/// Souhrn výsledků (celé studium nebo jeden semestr)
nonisolated struct GradeSummary: Hashable {
    /// Vážený studijní průměr podle kreditů (jen klasifikované předměty), nil = zatím žádná známka
    let weightedAverage: Double?
    /// Kredity za absolvované předměty
    let earnedCredits: Int
    /// Počet absolvovaných předmětů
    let passedCount: Int
    /// Počet předmětů celkem
    let totalCount: Int

    init(grades: [SubjectGrade]) {
        var weighted = 0.0
        var weights = 0
        for grade in grades {
            guard let value = grade.numericGrade, let credits = grade.credits, credits > 0 else { continue }
            weighted += value * Double(credits)
            weights += credits
        }
        weightedAverage = weights > 0 ? weighted / Double(weights) : nil
        earnedCredits = grades.filter(\.isPassed).reduce(0) { $0 + ($1.credits ?? 0) }
        passedCount = grades.filter(\.isPassed).count
        totalCount = grades.count
    }
}

/// Hodnocení jednoho semestru
nonisolated struct GradeSemester: Identifiable, Hashable {
    let id: String
    let title: String
    let grades: [SubjectGrade]
    var summary: GradeSummary { GradeSummary(grades: grades) }
}

nonisolated extension Array where Element == SubjectGrade {
    /// Seskupení po semestrech, nejnovější první; předměty podle kódu
    var bySemester: [GradeSemester] {
        Dictionary(grouping: self) { "\($0.year)-\($0.semester)" }
            .map { key, grades in
                let sorted = grades.sorted { $0.code < $1.code }
                return GradeSemester(id: key, title: sorted.first?.semesterTitle ?? key, grades: sorted)
            }
            .sorted { ($0.grades.first?.semesterSortKey ?? 0) > ($1.grades.first?.semesterSortKey ?? 0) }
    }
}

// MARK: - Ukázková data (náhledy)

nonisolated extension SubjectGrade {
    static var samples: [SubjectGrade] {
        func part(_ result: String, _ day: Int, _ month: Int, _ year: Int, examiner: String = "Ing. Jan Novák") -> GradePart {
            GradePart(result: result, date: Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)),
                      attempt: 1, examiner: examiner, points: nil)
        }
        return [
            SubjectGrade(code: "AP9PT", department: "AUIUI", year: "2026", semester: "ZS", name: "Pokročilé mobilní technologie",
                         credits: 4, creditTest: part("Z", 15, 12, 2026), exam: nil, finalGrade: nil, isPassed: false, isRecognized: false),
            SubjectGrade(code: "AP9DM", department: "AUIUI", year: "2026", semester: "ZS", name: "Datamining",
                         credits: 5, creditTest: nil, exam: nil, finalGrade: nil, isPassed: false, isRecognized: false),
            SubjectGrade(code: "AP7MT", department: "AUIUI", year: "2025", semester: "LS", name: "Mobilní technologie",
                         credits: 5, creditTest: part("Z", 20, 5, 2026), exam: part("A", 3, 6, 2026), finalGrade: "A", isPassed: true, isRecognized: false),
            SubjectGrade(code: "AP7AK", department: "AUIUI", year: "2025", semester: "LS", name: "Analýza a návrh komunikačních systémů",
                         credits: 4, creditTest: part("Z", 12, 5, 2026), exam: part("C", 10, 6, 2026, examiner: "doc. Ing. Eva Dvořáková, Ph.D."), finalGrade: "C", isPassed: true, isRecognized: false),
            SubjectGrade(code: "AP7SI", department: "AUIUI", year: "2025", semester: "ZS", name: "Softwarové inženýrství",
                         credits: 6, creditTest: part("Z", 10, 12, 2025), exam: part("B", 15, 1, 2026), finalGrade: "B", isPassed: true, isRecognized: false),
            SubjectGrade(code: "AP7AJ", department: "AUJ", year: "2025", semester: "ZS", name: "Angličtina pro IT",
                         credits: 2, creditTest: part("Z", 18, 12, 2025, examiner: "Mgr. Petr Svoboda"), exam: nil, finalGrade: "Z", isPassed: true, isRecognized: false)
        ]
    }
}
