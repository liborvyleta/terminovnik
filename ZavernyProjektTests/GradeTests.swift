import Foundation
import Testing
@testable import ZavernyProjekt

/// Známky a studijní výsledky: výklad známek, souhrny, semestry, dekódování odpovědí STAGu
/// a spojení obou služeb (`GradeStore.merge`). Jen čistá logika – žádné `GradeStore.shared`,
/// App Group, Klíčenka ani síť.
@Suite("Známky a studijní výsledky")
struct GradeTests {

    // MARK: - Pomůcky

    private func part(_ result: String) -> GradePart {
        GradePart(result: result, date: nil, attempt: nil, examiner: nil, points: nil)
    }

    private func grade(
        _ code: String,
        department: String = "AUIUI",
        year: String = "2025",
        semester: String = "ZS",
        name: String? = nil,
        credits: Int? = nil,
        finalGrade: String? = nil,
        exam: String? = nil,
        creditTest: String? = nil,
        isPassed: Bool = false,
        isRecognized: Bool = false
    ) -> SubjectGrade {
        SubjectGrade(
            code: code, department: department, year: year, semester: semester,
            name: name, credits: credits,
            creditTest: creditTest.map(part), exam: exam.map(part), finalGrade: finalGrade,
            isPassed: isPassed, isRecognized: isRecognized
        )
    }

    private func isApprox(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }

    private func records(_ json: String) throws -> [StagGradeRecord] {
        try decodeJSON([StagGradeRecord].self, json)
    }

    private func passed(_ json: String) throws -> [StagPassedSubject] {
        try decodeJSON([StagPassedSubject].self, json)
    }

    // MARK: - 1. Číselná hodnota známky

    @Test("Číselná hodnota: písmena A–F, čísla, desetinná čárka i tečka, slovní, malá písmena a mezery", arguments: [
        ("A", 1.0), ("B", 1.5), ("C", 2.0), ("D", 2.5), ("E", 3.0), ("F", 4.0), ("FX", 4.0),
        ("1", 1.0), ("1,5", 1.5), ("1.5", 1.5), ("2", 2.0), ("2,5", 2.5), ("2.5", 2.5), ("3", 3.0), ("4", 4.0),
        ("výborně", 1.0), ("velmi dobře", 1.5), ("dobře", 2.0), ("uspokojivě", 2.5), ("dostatečně", 3.0), ("nedostatečně", 4.0), ("nevyhověl", 4.0),
        ("a", 1.0), ("fx", 4.0), (" b ", 1.5), ("  C", 2.0), (" 1,5 ", 1.5),
        ("Výborně", 1.0), ("VELMI DOBŘE", 1.5), (" Nedostatečně ", 4.0)
    ])
    func numericValue(grade: String, expected: Double) {
        #expect(SubjectGrade.numericValue(grade) == expected)
    }

    @Test("Zápočet, nesplnění a neznámé texty nemají číselnou hodnotu", arguments: [
        "Z", "S", "z", "N", "NZ", "U", "započteno", "nezapočteno", "splněno", "", "   ", "X", "5", "0", "3,5", "abc"
    ])
    func numericValueNil(grade: String) {
        #expect(SubjectGrade.numericValue(grade) == nil)
    }

    // MARK: - 1. Úroveň známky (barva štítku)

    @Test("Úroveň známky podle hodnoty i zápočtových textů", arguments: [
        ("A", GradeLevel.excellent), ("1", .excellent), ("výborně", .excellent), (" a ", .excellent),
        ("B", .veryGood), ("1,5", .veryGood), ("1.5", .veryGood), ("C", .veryGood), ("2", .veryGood), ("velmi dobře", .veryGood),
        ("D", .good), ("2,5", .good),
        ("E", .sufficient), ("3", .sufficient), ("dostatečně", .sufficient),
        ("F", .failed), ("FX", .failed), ("4", .failed), ("nedostatečně", .failed), ("f", .failed),
        ("Z", .passed), ("S", .passed), ("z", .passed), (" s ", .passed), ("započteno", .passed),
        ("Splněno", .passed), ("U", .passed), ("uznáno", .passed),
        ("N", .notPassed), ("NZ", .notPassed), ("nz", .notPassed), (" n ", .notPassed),
        ("nezapočteno", .notPassed), ("NESPLNĚNO", .notPassed),
        ("X", .unknown), ("", .unknown), ("abc", .unknown), ("5", .unknown), ("3,5", .unknown)
    ])
    func level(grade: String, expected: GradeLevel) {
        #expect(SubjectGrade.level(grade) == expected)
    }

    @Test("Zápočet „Z“ na předmětu: bez číselné hodnoty, úroveň passed")
    func creditOnlySubject() {
        let subject = grade("AP7AJ", creditTest: "Z")
        #expect(subject.numericGrade == nil)
        #expect(subject.level == .passed)

        let failed = grade("AP7AJ", creditTest: "NZ")
        #expect(failed.numericGrade == nil)
        #expect(failed.level == .notPassed)
    }

    @Test("Předmět bez jakékoli známky: úroveň unknown, bez hodnoty")
    func subjectWithoutGrade() {
        let subject = grade("AP9DM")
        #expect(subject.displayGrade == nil)
        #expect(subject.numericGrade == nil)
        #expect(subject.level == .unknown)
    }

    @Test("Slovní známky „dostatečně“ a „uspokojivě“ se rozpoznají")
    func missingVerbalGrades() {
        // Regrese: dříve numericValue znal jen „výborně / velmi dobře / dobře / nedostatečně“.
        // ECTS slovní ekvivalenty E = „dostatečně“ (3) a D = „uspokojivě“ (2,5) chyběly → .unknown a mimo průměr.
                    #expect(SubjectGrade.numericValue("dostatečně") != nil)
        #expect(SubjectGrade.level("dostatečně") != .unknown)
        #expect(SubjectGrade.numericValue("uspokojivě") != nil)
        #expect(SubjectGrade.level("uspokojivě") != .unknown)
    }

    // MARK: - 2. Zobrazovaná známka

    @Test("Priorita zobrazované známky: výsledná > zkouška > zápočet")
    func displayGradePriority() {
        #expect(grade("X", finalGrade: "B", exam: "A", creditTest: "Z").displayGrade == "B")
        #expect(grade("X", exam: "C", creditTest: "Z").displayGrade == "C")
        #expect(grade("X", creditTest: "Z").displayGrade == "Z")
        #expect(grade("X", finalGrade: "A", creditTest: "Z").displayGrade == "A")
    }

    @Test("Prázdné a jen mezerové známky se přeskočí, okolní mezery se oříznou")
    func displayGradeSkipsEmpty() {
        #expect(grade("X", finalGrade: "", exam: "D", creditTest: "Z").displayGrade == "D")
        #expect(grade("X", finalGrade: "   ", exam: "", creditTest: "Z").displayGrade == "Z")
        #expect(grade("X", finalGrade: "", exam: " ", creditTest: "").displayGrade == nil)
        #expect(grade("X", finalGrade: " A ").displayGrade == "A")
    }

    @Test("Číselná známka a úroveň vycházejí ze zobrazované známky")
    func numericGradeFollowsDisplayGrade() {
        let subject = grade("X", finalGrade: "", exam: "1,5", creditTest: "Z")
        #expect(subject.numericGrade == 1.5)
        #expect(subject.level == .veryGood)

        let finalWins = grade("X", finalGrade: "F", exam: "A")
        #expect(finalWins.numericGrade == 4)
        #expect(finalWins.level == .failed)
    }

    // MARK: - 3. Souhrn (vážený průměr, kredity)

    @Test("Vážený průměr podle kreditů: A×5 + C×4 + Z×2 → (1·5 + 2·4) / 9")
    func weightedAverageExample() {
        let summary = GradeSummary(grades: [
            grade("A1", credits: 5, finalGrade: "A", isPassed: true),
            grade("C1", credits: 4, exam: "C", isPassed: true),
            grade("Z1", credits: 2, creditTest: "Z", isPassed: true)
        ])
        #expect(isApprox(summary.weightedAverage, (1.0 * 5 + 2.0 * 4) / 9))
        #expect(summary.earnedCredits == 11)
        #expect(summary.passedCount == 3)
        #expect(summary.totalCount == 3)
    }

    @Test("Předměty bez kreditů nebo s 0 kredity se do průměru nepočítají")
    func averageIgnoresSubjectsWithoutCredits() {
        let summary = GradeSummary(grades: [
            grade("B6", credits: 6, finalGrade: "B", isPassed: true),
            grade("NIL", credits: nil, finalGrade: "F", isPassed: true),
            grade("ZERO", credits: 0, finalGrade: "F", isPassed: true)
        ])
        #expect(isApprox(summary.weightedAverage, 1.5))
        #expect(summary.earnedCredits == 6)
        #expect(summary.passedCount == 3)
    }

    @Test("Kredity a počet absolvovaných jen z isPassed; klasifikované F se do průměru počítá")
    func earnedCreditsOnlyFromPassed() {
        let summary = GradeSummary(grades: [
            grade("OK", credits: 5, finalGrade: "A", isPassed: true),
            grade("FAIL", credits: 4, exam: "F", isPassed: false),
            grade("OPEN", credits: 3, isPassed: false)
        ])
        #expect(summary.earnedCredits == 5)
        #expect(summary.passedCount == 1)
        #expect(summary.totalCount == 3)
        #expect(isApprox(summary.weightedAverage, (1.0 * 5 + 4.0 * 4) / 9))
    }

    @Test("Bez klasifikované známky je průměr nil")
    func averageNilWithoutGrades() {
        let empty = GradeSummary(grades: [])
        #expect(empty.weightedAverage == nil)
        #expect(empty.earnedCredits == 0)
        #expect(empty.passedCount == 0)
        #expect(empty.totalCount == 0)

        let creditsOnly = GradeSummary(grades: [
            grade("Z1", credits: 2, creditTest: "Z", isPassed: true),
            grade("NO", credits: 5)
        ])
        #expect(creditsOnly.weightedAverage == nil)
        #expect(creditsOnly.earnedCredits == 2)
        #expect(creditsOnly.passedCount == 1)
        #expect(creditsOnly.totalCount == 2)
    }

    // MARK: - 4. Semestry

    @Test("Název semestru „ZS 2025/2026“, nečíselný rok se nepřevádí")
    func semesterTitle() {
        #expect(grade("X", year: "2025", semester: "ZS").semesterTitle == "ZS 2025/2026")
        #expect(grade("X", year: "2024", semester: "LS").semesterTitle == "LS 2024/2025")
        #expect(grade("X", year: "", semester: "ZS").semesterTitle == "ZS ")
        #expect(grade("X", year: "neznámý", semester: "LS").semesterTitle == "LS neznámý")
    }

    @Test("Řadicí klíč: LS 2025 > ZS 2025 > LS 2024")
    func semesterSortKey() {
        let ls2025 = grade("X", year: "2025", semester: "LS").semesterSortKey
        let zs2025 = grade("X", year: "2025", semester: "ZS").semesterSortKey
        let ls2024 = grade("X", year: "2024", semester: "LS").semesterSortKey
        #expect(ls2025 > zs2025)
        #expect(zs2025 > ls2024)
    }

    @Test("Identifikátor hodnocení katedra/kód/rok/semestr")
    func gradeID() {
        #expect(grade("AP7MT", department: "AUIUI", year: "2025", semester: "LS").id == "AUIUI/AP7MT/2025/LS")
    }

    @Test("Seskupení po semestrech: nejnovější první, předměty podle kódu")
    func bySemesterGroupingAndOrder() throws {
        let grades = [
            grade("AP7ZZ", year: "2024", semester: "LS"),
            grade("AP7SI", year: "2025", semester: "ZS", credits: 6, finalGrade: "B", isPassed: true),
            grade("AP7MT", year: "2025", semester: "LS", credits: 5, finalGrade: "A", isPassed: true),
            grade("AP7AJ", year: "2025", semester: "ZS", credits: 2, creditTest: "Z", isPassed: true),
            grade("AP7AK", year: "2025", semester: "LS", credits: 4, exam: "C", isPassed: true),
            grade("AP7BB", year: "2025", semester: "ZS")
        ]
        let semesters = grades.bySemester
        #expect(semesters.map(\.id) == ["2025-LS", "2025-ZS", "2024-LS"])
        #expect(semesters.map(\.title) == ["LS 2025/2026", "ZS 2025/2026", "LS 2024/2025"])
        #expect(semesters[0].grades.map(\.code) == ["AP7AK", "AP7MT"])
        #expect(semesters[1].grades.map(\.code) == ["AP7AJ", "AP7BB", "AP7SI"])
        #expect(semesters[2].grades.map(\.code) == ["AP7ZZ"])

        // Souhrn jednoho semestru
        let summer = semesters[0].summary
        #expect(isApprox(summer.weightedAverage, (1.0 * 5 + 2.0 * 4) / 9))
        #expect(summer.earnedCredits == 9)
        let winter = semesters[1].summary
        #expect(isApprox(winter.weightedAverage, 1.5))
        #expect(winter.earnedCredits == 8)
        #expect(winter.passedCount == 2)
        #expect(winter.totalCount == 3)
        #expect(semesters[2].summary.weightedAverage == nil)
    }

    @Test("Prázdný seznam → žádné semestry")
    func bySemesterEmpty() {
        #expect([SubjectGrade]().bySemester.isEmpty)
    }

    @Test("Ukázková data: tři semestry, nejnovější ZS 2026/2027")
    func samplesGrouping() {
        let semesters = SubjectGrade.samples.bySemester
        #expect(semesters.map(\.title) == ["ZS 2026/2027", "LS 2025/2026", "ZS 2025/2026"])
        #expect(semesters.map { $0.grades.count } == [2, 2, 2])
    }

    @Test("SubjectGrade přežije zakódování a dekódování (snapshot v App Group)")
    func codableRoundTrip() throws {
        let original = SubjectGrade.samples
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([SubjectGrade].self, from: data)
        #expect(decoded == original)
    }

    // MARK: - 5. StagGradeRecord (znamky/getZnamkyByStudent)

    @Test("Záznam známek: zkouška i zápočet s datem, pokusem, zkoušejícím a body")
    func gradeRecordFull() throws {
        let record = try decodeJSON(StagGradeRecord.self, """
        {
          "katedra": "AUIUI", "zkratka": "AP7MT", "rok": "2025", "semestr": "LS",
          "zkHodnoceni": "A", "zkDatum": {"value": "3.6.2026"}, "zkPokus": "2", "zkBody": "92",
          "zkUcitJmeno": "Ing. Jan Novák",
          "zppzkHodnoceni": "Z", "zppzkDatum": "20.5.2026", "zppzkPokus": 1,
          "zppzkUcitJmeno": "Mgr. Petr Svoboda",
          "predmetUznany": "N", "stavAbsolvovani": "A"
        }
        """)
        #expect(record.katedra == "AUIUI")
        #expect(record.zkratka == "AP7MT")
        #expect(record.rok == "2025")
        #expect(record.semestr == "LS")
        #expect(record.predmetUznany == false)
        #expect(record.stavAbsolvovani == "A")

        let exam = try #require(record.exam)
        #expect(exam.result == "A")
        #expect(exam.date == makeDate(2026, 6, 3))
        #expect(exam.attempt == 2)
        #expect(exam.examiner == "Ing. Jan Novák")
        #expect(exam.points == "92")

        let credit = try #require(record.creditTest)
        #expect(credit.result == "Z")
        #expect(credit.date == makeDate(2026, 5, 20))
        #expect(credit.attempt == 1)
        #expect(credit.examiner == "Mgr. Petr Svoboda")
        #expect(credit.points == nil)
    }

    @Test("Záznam známek: čísla místo textu (rok, body, pokus)")
    func gradeRecordNumbers() throws {
        let record = try decodeJSON(StagGradeRecord.self, """
        {"katedra":"AUIUI","zkratka":"AP7SI","rok":2025,"semestr":"ZS",
         "zkHodnoceni":"B","zkDatum":"15.1.2026","zkPokus":3,"zkBody":85.5}
        """)
        #expect(record.rok == "2025")
        let exam = try #require(record.exam)
        #expect(exam.attempt == 3)
        #expect(exam.points == "85.5")
        #expect(exam.date == makeDate(2026, 1, 15))
        #expect(record.creditTest == nil)
    }

    @Test("Bez hodnocení (chybí, null, prázdné) zkouška ani zápočet nevznikne")
    func gradeRecordWithoutResult() throws {
        let missing = try decodeJSON(StagGradeRecord.self, """
        {"katedra":"AUIUI","zkratka":"AP9PT","rok":"2026","semestr":"ZS",
         "zkDatum":"3.6.2026","zkPokus":"1","zppzkDatum":{"value":"20.5.2026"}}
        """)
        #expect(missing.exam == nil)
        #expect(missing.creditTest == nil)

        let nullAndEmpty = try decodeJSON(StagGradeRecord.self, """
        {"zkratka":"AP9PT","zkHodnoceni":null,"zppzkHodnoceni":"   "}
        """)
        #expect(nullAndEmpty.exam == nil)
        #expect(nullAndEmpty.creditTest == nil)
    }

    @Test("Neplatné datum a pokus → nil, hodnocení zůstane")
    func gradeRecordInvalidDateAndAttempt() throws {
        let record = try decodeJSON(StagGradeRecord.self, """
        {"zkratka":"AP9PT","zkHodnoceni":" C ","zkDatum":"neuvedeno","zkPokus":"první"}
        """)
        let exam = try #require(record.exam)
        #expect(exam.result == "C")
        #expect(exam.date == nil)
        #expect(exam.attempt == nil)
        #expect(exam.examiner == nil)
        #expect(exam.points == nil)
    }

    @Test("Prázdný objekt se dekóduje bez chyby, vše nil")
    func gradeRecordEmptyObject() throws {
        let record = try decodeJSON(StagGradeRecord.self, "{}")
        #expect(record.zkratka == nil)
        #expect(record.exam == nil)
        #expect(record.creditTest == nil)
        #expect(record.predmetUznany == nil)
    }

    // MARK: - 6. StagPassedSubject (student/getStudentPredmetyAbsolvoval)

    @Test("Absolvovaný předmět: „A“, kredity jako číslo, známka a název")
    func passedSubjectFull() throws {
        let subject = try decodeJSON(StagPassedSubject.self, """
        {"katedra":"AUIUI","zkratka":"AP7MT","rok":"2025","semestr":"LS","absolvoval":"A",
         "pocetKreditu":5,"znamka":"A","nazevPredmetu":"Mobilní technologie","datum":{"value":"3.6.2026"}}
        """)
        #expect(subject.katedra == "AUIUI")
        #expect(subject.zkratka == "AP7MT")
        #expect(subject.rok == "2025")
        #expect(subject.semestr == "LS")
        #expect(subject.absolvoval == true)
        #expect(subject.pocetKreditu == 5)
        #expect(subject.znamka == "A")
        #expect(subject.nazevPredmetu == "Mobilní technologie")
        #expect(subject.datum == "3.6.2026")
    }

    @Test("Absolvoval: „A“, „N“, true, false, „ano“, chybějící", arguments: [
        (#""A""#, Optional(true)), (#""N""#, Optional(false)), ("true", Optional(true)), ("false", Optional(false)),
        (#""ano""#, Optional(true)), (#""ne""#, Optional(false)), ("null", nil)
    ] as [(String, Bool?)])
    func passedSubjectFlag(rawValue: String, expected: Bool?) throws {
        let subject = try decodeJSON(StagPassedSubject.self, #"{"zkratka":"X","absolvoval":"# + rawValue + "}")
        #expect(subject.absolvoval == expected)
    }

    @Test("Kredity: číslo, text, text s mezerami, null, nesmysl", arguments: [
        ("5", Optional(5)), (#""4""#, Optional(4)), (#"" 6 ""#, Optional(6)), ("null", nil), (#""pět""#, nil)
    ] as [(String, Int?)])
    func passedSubjectCredits(rawValue: String, expected: Int?) throws {
        let subject = try decodeJSON(StagPassedSubject.self, #"{"zkratka":"X","pocetKreditu":"# + rawValue + "}")
        #expect(subject.pocetKreditu == expected)
    }

    @Test("Chybějící absolvoval a kredity → nil")
    func passedSubjectMissing() throws {
        let subject = try decodeJSON(StagPassedSubject.self, #"{"zkratka":"X"}"#)
        #expect(subject.absolvoval == nil)
        #expect(subject.pocetKreditu == nil)
        #expect(subject.znamka == nil)
        #expect(subject.nazevPredmetu == nil)
    }

    // MARK: - 6. StagFlexible

    @Test("StagFlexible.text: ořez, prázdné → nil, čísla, obal {\"value\"}")
    func flexibleText() throws {
        func text(_ raw: String) throws -> String? { try decodeJSON(FlexibleProbe.self, #"{"value":"# + raw + "}").text }
        #expect(try text(#""  abc  ""#) == "abc")
        #expect(try text(#""""#) == nil)
        #expect(try text(#""   ""#) == nil)
        #expect(try text("42") == "42")
        #expect(try text("85.5") == "85.5")
        #expect(try text(#"{"value":"3.6.2026"}"#) == "3.6.2026")
        #expect(try text(#"{"value":null}"#) == nil)
        #expect(try text("null") == nil)
        #expect(try text("true") == nil)
        #expect(try text("[1, 2]") == nil)
        #expect(try decodeJSON(FlexibleProbe.self, "{}").text == nil)
    }

    @Test("StagFlexible.number: číslo, text, text s mezerami, obal, nesmysl")
    func flexibleNumber() throws {
        func number(_ raw: String) throws -> Int? { try decodeJSON(FlexibleProbe.self, #"{"value":"# + raw + "}").number }
        #expect(try number("5") == 5)
        #expect(try number(#""5""#) == 5)
        #expect(try number(#"" 7 ""#) == 7)
        #expect(try number(#"{"value":"8"}"#) == 8)
        #expect(try number(#""pět""#) == nil)
        #expect(try number("null") == nil)
        #expect(try decodeJSON(FlexibleProbe.self, "{}").number == nil)
    }

    @Test("StagFlexible.flag: Bool, „A“/„N“, „ano“, „1“, 1/0, „Y“", arguments: [
        ("true", Optional(true)), ("false", Optional(false)),
        (#""A""#, Optional(true)), (#""a""#, Optional(true)), (#""ANO""#, Optional(true)),
        (#""1""#, Optional(true)), ("1", Optional(true)), (#""Y""#, Optional(true)), (#""true""#, Optional(true)),
        (#""N""#, Optional(false)), (#""ne""#, Optional(false)), ("0", Optional(false)), (#""x""#, Optional(false)),
        ("null", nil), (#""""#, nil)
    ] as [(String, Bool?)])
    func flexibleFlag(rawValue: String, expected: Bool?) throws {
        let probe = try decodeJSON(FlexibleProbe.self, #"{"value":"# + rawValue + "}")
        #expect(probe.flag == expected)
    }

    @Test("StagFlexible.text: obal {\"value\"} s prázdným textem → nil")
    func flexibleBoxedEmptyText() throws {
        // Regrese: dříve StagFlexible.text vracel hodnotu z obalu {"value": …} bez ořezu a bez převodu
        // prázdného textu na nil (na rozdíl od prostého textu).
        let empty = try decodeJSON(FlexibleProbe.self, #"{"value":{"value":""}}"#)
        let padded = try decodeJSON(FlexibleProbe.self, #"{"value":{"value":" Z "}}"#)
                    #expect(empty.text == nil)
        #expect(padded.text == "Z")
    }

    // MARK: - 7. Spojení služeb (GradeStore.merge)

    @Test("Spojení podle katedry/kódu/roku/semestru bez ohledu na velikost písmen")
    func mergeJoinsCaseInsensitive() throws {
        let merged = GradeStore.merge(
            records: try records("""
            [{"katedra":"auiui","zkratka":"ap7mt","rok":"2025","semestr":"ls",
              "zkHodnoceni":"A","zkDatum":"3.6.2026","zkPokus":"1",
              "zppzkHodnoceni":"Z","zppzkDatum":"20.5.2026"}]
            """),
            passed: try passed("""
            [{"katedra":"AUIUI","zkratka":"AP7MT","rok":"2025","semestr":"LS","absolvoval":"A",
              "pocetKreditu":5,"znamka":"A","nazevPredmetu":"Mobilní technologie"}]
            """)
        )
        #expect(merged.count == 1)
        let subject = try #require(merged.first)
        // Identita z přehledu předmětů (velká písmena), známky ze záznamu
        #expect(subject.id == "AUIUI/AP7MT/2025/LS")
        #expect(subject.name == "Mobilní technologie")
        #expect(subject.credits == 5)
        #expect(subject.finalGrade == "A")
        #expect(subject.exam?.result == "A")
        #expect(subject.exam?.date == makeDate(2026, 6, 3))
        #expect(subject.exam?.attempt == 1)
        #expect(subject.creditTest?.result == "Z")
        #expect(subject.isPassed)
        #expect(!subject.isRecognized)
    }

    @Test("Záznam bez protějšku v přehledu → položka bez názvu a kreditů")
    func mergeRecordWithoutPassed() throws {
        let merged = GradeStore.merge(
            records: try records("""
            [{"katedra":"AUIUI","zkratka":"AP9PT","rok":"2026","semestr":"ZS","zppzkHodnoceni":"Z"}]
            """),
            passed: []
        )
        let subject = try #require(merged.first)
        #expect(merged.count == 1)
        #expect(subject.id == "AUIUI/AP9PT/2026/ZS")
        #expect(subject.name == nil)
        #expect(subject.credits == nil)
        #expect(subject.finalGrade == nil)
        #expect(subject.exam == nil)
        #expect(subject.creditTest?.result == "Z")
        #expect(!subject.isPassed)
        #expect(!subject.isRecognized)
        #expect(subject.displayGrade == "Z")
    }

    @Test("Uznaný předmět: predmetUznany „A“ / „ano“ → isRecognized, „N“ a chybějící ne", arguments: [
        (#","predmetUznany":"A""#, true), (#","predmetUznany":"ano""#, true), (#","predmetUznany":"1""#, true),
        (#","predmetUznany":"N""#, false), ("", false)
    ])
    func mergeRecognized(extra: String, expected: Bool) throws {
        let merged = GradeStore.merge(
            records: try records(#"[{"katedra":"AUIUI","zkratka":"AP7AJ","rok":"2024","semestr":"ZS","zppzkHodnoceni":"U""# + extra + "}]"),
            passed: []
        )
        #expect(merged.first?.isRecognized == expected)
    }

    @Test("stavAbsolvovani „A“ / „S“ → isPassed i bez přehledu předmětů; „N“ absolvování nezruší")
    func mergePassedState() throws {
        func merged(_ state: String, passedFlag: String?) throws -> SubjectGrade? {
            let passedJSON = passedFlag.map {
                #"[{"katedra":"AUIUI","zkratka":"AP7SI","rok":"2025","semestr":"ZS","absolvoval":"\#($0)"}]"#
            } ?? "[]"
            return GradeStore.merge(
                records: try records(#"[{"katedra":"AUIUI","zkratka":"AP7SI","rok":"2025","semestr":"ZS","zkHodnoceni":"B","stavAbsolvovani":"\#(state)"}]"#),
                passed: try passed(passedJSON)
            ).first
        }
        #expect(try merged("A", passedFlag: nil)?.isPassed == true)
        #expect(try merged("a", passedFlag: nil)?.isPassed == true)
        #expect(try merged("S", passedFlag: nil)?.isPassed == true)
        #expect(try merged("N", passedFlag: nil)?.isPassed == false)
        #expect(try merged("N", passedFlag: "A")?.isPassed == true)
        #expect(try merged("A", passedFlag: "N")?.isPassed == true)
    }

    @Test("Předmět jen v přehledu zůstane s výslednou známkou")
    func mergePassedOnly() throws {
        let merged = GradeStore.merge(
            records: try records("""
            [{"katedra":"AUIUI","zkratka":"AP7MT","rok":"2025","semestr":"LS","zkHodnoceni":"A"}]
            """),
            passed: try passed("""
            [{"katedra":"AUIUI","zkratka":"AP7MT","rok":"2025","semestr":"LS","absolvoval":"A","pocetKreditu":5,"znamka":"A"},
             {"katedra":"AUJ","zkratka":"AP7AJ","rok":"2024","semestr":"ZS","absolvoval":true,"pocetKreditu":"2",
              "znamka":"Z","nazevPredmetu":"Angličtina"}]
            """)
        )
        #expect(merged.count == 2)
        let english = try #require(merged.first { $0.code == "AP7AJ" })
        #expect(english.id == "AUJ/AP7AJ/2024/ZS")
        #expect(english.finalGrade == "Z")
        #expect(english.name == "Angličtina")
        #expect(english.credits == 2)
        #expect(english.isPassed)
        #expect(english.exam == nil)
        #expect(english.creditTest == nil)
        #expect(!english.isRecognized)
        #expect(english.level == .passed)
    }

    @Test("Opakovaný předmět v jiném roce zůstane jako samostatná položka")
    func mergeKeepsDifferentYears() throws {
        let merged = GradeStore.merge(
            records: try records("""
            [{"katedra":"AUIUI","zkratka":"AP7SI","rok":"2024","semestr":"ZS","zkHodnoceni":"F"},
             {"katedra":"AUIUI","zkratka":"AP7SI","rok":"2025","semestr":"ZS","zkHodnoceni":"B","stavAbsolvovani":"A"}]
            """),
            passed: []
        )
        #expect(merged.count == 2)
        let byYear = Dictionary(uniqueKeysWithValues: merged.map { ($0.year, $0) })
        #expect(byYear["2024"]?.exam?.result == "F")
        #expect(byYear["2024"]?.isPassed == false)
        #expect(byYear["2025"]?.exam?.result == "B")
        #expect(byYear["2025"]?.isPassed == true)
    }

    @Test("Položky bez zkratky se přeskočí, prázdné vstupy → prázdný výsledek")
    func mergeSkipsMissingCode() throws {
        #expect(GradeStore.merge(records: [], passed: []).isEmpty)
        let merged = GradeStore.merge(
            records: try records(#"[{"katedra":"AUIUI","rok":"2025","semestr":"ZS","zkHodnoceni":"A"}]"#),
            passed: try passed(#"[{"katedra":"AUIUI","rok":"2025","semestr":"ZS","znamka":"A"}]"#)
        )
        #expect(merged.isEmpty)
    }

    @Test("Záznam bez hodnocení nesmaže nic z přehledu předmětů")
    func mergeRecordWithoutResultKeepsPassedData() throws {
        let merged = GradeStore.merge(
            records: try records(#"[{"katedra":"AUIUI","zkratka":"AP9DM","rok":"2026","semestr":"ZS"}]"#),
            passed: try passed(#"[{"katedra":"AUIUI","zkratka":"AP9DM","rok":"2026","semestr":"ZS","pocetKreditu":5,"nazevPredmetu":"Datamining"}]"#)
        )
        let subject = try #require(merged.first)
        #expect(merged.count == 1)
        #expect(subject.name == "Datamining")
        #expect(subject.credits == 5)
        #expect(subject.exam == nil)
        #expect(subject.creditTest == nil)
        #expect(subject.displayGrade == nil)
        #expect(!subject.isPassed)
    }

    @Test("predmetUznany jako JSON true → uznaný předmět")
    func mergeRecognizedBoolean() throws {
        // Regrese: dříve StagGradeRecord četl predmetUznany přes StagFlexible.text, který JSON Bool neumí
        // (vrátí nil) – „TRUE“ v seznamu v GradeStore.merge tak pokryje jen text "true", ne true.
        let merged = GradeStore.merge(
            records: try records(#"[{"katedra":"AUIUI","zkratka":"AP7AJ","rok":"2024","semestr":"ZS","predmetUznany":true}]"#),
            passed: []
        )
                    #expect(merged.first?.isRecognized == true)
    }

    @Test("Celý řetězec: spojení → semestry → souhrn")
    func mergeToSummary() throws {
        let merged = GradeStore.merge(
            records: try records("""
            [{"katedra":"AUIUI","zkratka":"AP7MT","rok":"2025","semestr":"LS","zkHodnoceni":"A","zppzkHodnoceni":"Z","stavAbsolvovani":"A"},
             {"katedra":"AUIUI","zkratka":"AP7AK","rok":"2025","semestr":"LS","zkHodnoceni":"C","zppzkHodnoceni":"Z","stavAbsolvovani":"A"},
             {"katedra":"AUJ","zkratka":"AP7AJ","rok":"2025","semestr":"LS","zppzkHodnoceni":"Z","stavAbsolvovani":"A"},
             {"katedra":"AUIUI","zkratka":"AP9PT","rok":"2026","semestr":"ZS","zppzkHodnoceni":"Z"}]
            """),
            passed: try passed("""
            [{"katedra":"AUIUI","zkratka":"AP7MT","rok":"2025","semestr":"LS","absolvoval":"A","pocetKreditu":5},
             {"katedra":"AUIUI","zkratka":"AP7AK","rok":"2025","semestr":"LS","absolvoval":"A","pocetKreditu":"4"},
             {"katedra":"AUJ","zkratka":"AP7AJ","rok":"2025","semestr":"LS","absolvoval":"A","pocetKreditu":2},
             {"katedra":"AUIUI","zkratka":"AP9PT","rok":"2026","semestr":"ZS","absolvoval":"N","pocetKreditu":4}]
            """)
        )
        let overall = GradeSummary(grades: merged)
        #expect(isApprox(overall.weightedAverage, (1.0 * 5 + 2.0 * 4) / 9))
        #expect(overall.earnedCredits == 11)
        #expect(overall.passedCount == 3)
        #expect(overall.totalCount == 4)

        let semesters = merged.bySemester
        #expect(semesters.map(\.title) == ["ZS 2026/2027", "LS 2025/2026"])
        #expect(semesters[1].grades.map(\.code) == ["AP7AJ", "AP7AK", "AP7MT"])
        #expect(semesters[0].summary.weightedAverage == nil)
        #expect(semesters[0].summary.earnedCredits == 0)
    }
}

/// Testovací obal pro `StagFlexible` – čte jediný klíč „value“ všemi třemi způsoby.
private nonisolated struct FlexibleProbe: Decodable {
    let text: String?
    let number: Int?
    let flag: Bool?

    private enum CodingKeys: String, CodingKey { case value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = StagFlexible.text(c, .value)
        number = StagFlexible.number(c, .value)
        flag = StagFlexible.flag(c, .value)
    }
}
