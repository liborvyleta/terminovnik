import Foundation
import Testing
@testable import ZavernyProjekt

/// Testy dekódování odpovědí webových služeb IS/STAG.
///
/// Pracují bez sítě – odpovědi jsou JSON fixture zapsané přímo v textu testů.
@Suite("STAG – parsování odpovědí")
struct StagParsingTests {
    let calendar = TestCalendar.prague

    // MARK: - StagSubject

    @Test("Předmět s kredity jako číslo a rokem jako číslo")
    func subjectNumericCredits() throws {
        let subject = try decodeJSON(StagSubject.self, """
        {"katedra":"AUIUI","zkratka":"AP9PT","nazev":"Pokročilé mobilní technologie","kreditu":5,"rok":2026}
        """)
        #expect(subject.kreditu == 5)
        #expect(subject.rok == "2026")
        #expect(subject.id == "AUIUI/AP9PT")
        #expect(subject.displayName == "Pokročilé mobilní technologie")
    }

    @Test("Předmět s kredity jako text, null i nesmysl")
    func subjectTextCredits() throws {
        let text = try decodeJSON(StagSubject.self, #"{"katedra":"AUIUI","zkratka":"AP9DM","kreditu":"6","rok":"2026"}"#)
        #expect(text.kreditu == 6)
        #expect(text.rok == "2026")

        let null = try decodeJSON(StagSubject.self, #"{"katedra":"AUIUI","zkratka":"AP9DM","kreditu":null}"#)
        #expect(null.kreditu == nil)
        #expect(null.rok == nil)

        let garbage = try decodeJSON(StagSubject.self, #"{"katedra":"AUIUI","zkratka":"AP9DM","kreditu":"pět"}"#)
        #expect(garbage.kreditu == nil)
    }

    @Test("Bez názvu se zobrazí zkratka")
    func subjectDisplayNameFallback() throws {
        let missing = try decodeJSON(StagSubject.self, #"{"katedra":"AUIUI","zkratka":"AP9PT"}"#)
        #expect(missing.displayName == "AP9PT")
        let empty = try decodeJSON(StagSubject.self, #"{"katedra":"AUIUI","zkratka":"AP9PT","nazev":""}"#)
        #expect(empty.displayName == "AP9PT")
    }

    @Test("Bez katedry nebo zkratky dekódování selže")
    func subjectRequiredFields() {
        #expect(throws: DecodingError.self) {
            try decodeJSON(StagSubject.self, #"{"zkratka":"AP9PT"}"#)
        }
        #expect(throws: DecodingError.self) {
            try decodeJSON(StagSubject.self, #"{"katedra":"AUIUI"}"#)
        }
    }

    // MARK: - StagTimetableAction

    private let fullAction = """
    {
      "roakIdno": 123456,
      "nazev": "Pokročilé mobilní technologie",
      "katedra": "AUIUI",
      "predmet": "AP9PT",
      "typAkce": "Cvičení",
      "typAkceZkr": "Cv",
      "den": "Úterý",
      "denZkr": "Út",
      "hodinaSkutOd": {"value": "10:00"},
      "hodinaSkutDo": {"value": "11:50"},
      "budova": "52",
      "mistnost": "202",
      "vsichniUciteleJmenaTituly": "Ing. Filip Vabroušek",
      "tyden": "Sudý",
      "datum": null,
      "datumOd": {"value": "22.9.2026"},
      "datumDo": {"value": "15.12.2026"}
    }
    """

    @Test("Rozvrhová akce: časy v obalu {\"value\"}, ID jako číslo")
    func timetableActionDecoding() throws {
        let action = try decodeJSON(StagTimetableAction.self, fullAction)
        #expect(action.roakIdno == "123456")
        #expect(action.hodinaSkutOd == "10:00")
        #expect(action.hodinaSkutDo == "11:50")
        #expect(action.datumOd == "22.9.2026")
        #expect(action.datum == nil)
        #expect(action.ucitele == "Ing. Filip Vabroušek")
    }

    @Test("Převod rozvrhové akce na TimetableEvent")
    func timetableActionToEvent() throws {
        let action = try decodeJSON(StagTimetableAction.self, fullAction)
        let event = try #require(action.timetableEvent(hexColor: "#3E63DD"))
        #expect(event.id == "123456")
        #expect(event.subjectCode == "AP9PT")
        #expect(event.department == "AUIUI")
        #expect(event.subjectName == "Pokročilé mobilní technologie")
        #expect(event.typeName == "Cvičení")
        #expect(event.typeShort == "Cv")
        #expect(event.weekday == 2)
        #expect(event.startTime == "10:00")
        #expect(event.endTime == "11:50")
        #expect(event.locationText == "52/202")
        #expect(event.teacher == "Ing. Filip Vabroušek")
        #expect(event.weekParity == "Sudý")
        #expect(event.dateFrom == makeDate(2026, 9, 22))
        #expect(event.dateTo == makeDate(2026, 12, 15))
        #expect(event.singleDate == nil)
        #expect(event.hexColor == "#3E63DD")

        // Sudý týden v rozsahu semestru: 13. 10. (týden 42) ano, 6. 10. (týden 41) ne
        #expect(event.occurs(on: makeDate(2026, 10, 13, 10), calendar: calendar))
        #expect(!event.occurs(on: makeDate(2026, 10, 6, 10), calendar: calendar))
    }

    @Test("Časy jako obyčejný text i bez obalu")
    func timetableActionPlainTimes() throws {
        let action = try decodeJSON(StagTimetableAction.self, """
        {"predmet":"AP9DM","hodinaSkutOd":"08:00","hodinaSkutDo":"09:40","datum":"10.10.2026"}
        """)
        #expect(action.hodinaSkutOd == "08:00")
        #expect(action.hodinaSkutDo == "09:40")
        let event = try #require(action.timetableEvent(hexColor: nil))
        #expect(event.singleDate == makeDate(2026, 10, 10))
        #expect(event.weekday == nil)
        #expect(event.occurs(on: makeDate(2026, 10, 10, 8), calendar: calendar))
    }

    @Test(
        "Zkratka dne → číslo dne (1 = pondělí)",
        arguments: [("Po", 1), ("Út", 2), ("St", 3), ("Čt", 4), ("Pá", 5), ("So", 6), ("Ne", 7), ("ÚT", 2), ("čt", 4)]
    )
    func timetableWeekdayMapping(abbreviation: String, expected: Int) throws {
        let action = try decodeJSON(StagTimetableAction.self, #"{"predmet":"AP9PT","denZkr":"\#(abbreviation)"}"#)
        #expect(action.timetableEvent(hexColor: nil)?.weekday == expected)
    }

    @Test("Celý název dne bez zkratky, neznámý den → nil")
    func timetableWeekdayFromFullName() throws {
        let thursday = try decodeJSON(StagTimetableAction.self, #"{"predmet":"AP9PT","den":"Čtvrtek"}"#)
        #expect(thursday.timetableEvent(hexColor: nil)?.weekday == 4)

        let unknown = try decodeJSON(StagTimetableAction.self, #"{"predmet":"AP9PT","denZkr":"X"}"#)
        #expect(unknown.timetableEvent(hexColor: nil)?.weekday == nil)

        let missing = try decodeJSON(StagTimetableAction.self, #"{"predmet":"AP9PT"}"#)
        #expect(missing.timetableEvent(hexColor: nil)?.weekday == nil)
    }

    @Test("Bez kódu předmětu se akce zahodí")
    func timetableActionWithoutSubject() throws {
        let missing = try decodeJSON(StagTimetableAction.self, #"{"roakIdno":"1","denZkr":"Po"}"#)
        #expect(missing.timetableEvent(hexColor: nil) == nil)
        let empty = try decodeJSON(StagTimetableAction.self, #"{"roakIdno":"1","predmet":""}"#)
        #expect(empty.timetableEvent(hexColor: nil) == nil)
    }

    @Test("Záložní ID, název, typ a zkratka typu")
    func timetableActionFallbacks() throws {
        let action = try decodeJSON(StagTimetableAction.self, """
        {"predmet":"AP9PT","denZkr":"Út","hodinaSkutOd":{"value":"10:00"},"typAkceZkr":"Cv"}
        """)
        let event = try #require(action.timetableEvent(hexColor: nil))
        #expect(event.id == "AP9PT-Út-10:00-Cv")
        #expect(event.subjectName == "AP9PT")
        #expect(event.typeName == "Cv")
        #expect(event.department == "")

        let lecture = try decodeJSON(StagTimetableAction.self, #"{"predmet":"AP9PT","typAkce":"Přednáška"}"#)
        #expect(lecture.timetableEvent(hexColor: nil)?.typeShort == "Př")

        let bare = try decodeJSON(StagTimetableAction.self, #"{"predmet":"AP9PT"}"#)
        #expect(bare.timetableEvent(hexColor: nil)?.typeName == "Výuka")
    }

    @Test("Pole jiného typu (číslo místo textu) akci nezahodí")
    func timetableActionTolerantTypes() throws {
        let action = try decodeJSON(StagTimetableAction.self, """
        {"predmet":"AP9PT","budova":52,"mistnost":202,"hodinaSkutOd":{"value":null}}
        """)
        #expect(action.budova == "52")
        #expect(action.mistnost == "202")
        #expect(action.hodinaSkutOd == nil)
    }

    // MARK: - StagExamTerm → ExamTerm

    private let registeredTerm = """
    {
      "termIdno": 98765,
      "predmet": "AP9PT",
      "katedra": "AUIUI",
      "datum": {"value": "14.1.2027"},
      "casOd": "09:00",
      "casDo": "11:00",
      "obsazeni": "12",
      "limit": 20,
      "budova": "52",
      "mistnost": "202",
      "poznamka": "Přineste si index",
      "opravny": "N",
      "deadlineDatumPrihlaseni": {"value": "14.1.2027 23:59"},
      "deadlineDatumOdhlaseni": "13.1.2027 12:00",
      "zacatekPrihlasovani": "1.12.2026 8:00",
      "platnost": "A",
      "typTerminu": "zkouška",
      "zapsan": "A",
      "lzeZapsatOdepsat": true,
      "textDuvoduProcNelzeZapsatOdepsat": null,
      "ucitel": {"jmeno": "Filip", "prijmeni": "Vabroušek", "titulPred": "Ing.", "titulZa": null}
    }
    """

    @Test("Zapsaný termín: data, časy, obsazenost, vyučující")
    func examTermFull() throws {
        let raw = try decodeJSON(StagExamTerm.self, registeredTerm)
        let term = try #require(raw.examTerm())
        #expect(term.id == "98765")
        #expect(term.subjectCode == "AP9PT")
        #expect(term.department == "AUIUI")
        #expect(term.typeName == "Zkouška")
        #expect(term.taskType == .zkouska)
        #expect(term.start == makeDate(2027, 1, 14, 9, 0))
        #expect(term.end == makeDate(2027, 1, 14, 11, 0))
        #expect(term.room == "52/202")
        #expect(term.teacher == "Ing. Filip Vabroušek")
        #expect(term.occupied == 12)
        #expect(term.capacity == 20)
        #expect(term.freeSpots == 8)
        #expect(term.isRegistered)
        #expect(term.canChangeRegistration)
        #expect(term.blockReason == nil)
        #expect(term.registrationDeadline == makeDate(2027, 1, 14, 23, 59))
        #expect(term.unregisterDeadline == makeDate(2027, 1, 13, 12, 0))
        #expect(term.registrationOpens == makeDate(2026, 12, 1, 8, 0))
        #expect(!term.isRetake)
        #expect(term.note == "Přineste si index")
        #expect(!term.isCancelled)
    }

    @Test(
        "Příznak zapsán: Bool i text A/N/ano",
        arguments: [
            (#"true"#, true), (#"false"#, false), (#""A""#, true), (#""N""#, false),
            (#""ano""#, true), (#""a""#, true), (#"1"#, true), (#"0"#, false), (#"null"#, false)
        ]
    )
    func examTermRegisteredFlag(json: String, expected: Bool) throws {
        let raw = try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"AP9PT","datum":"14.1.2027","zapsan":\(json)}
        """)
        #expect(raw.examTerm()?.isRegistered == expected)
    }

    @Test("Obsazenost a kapacita jako text i číslo, s mezerami")
    func examTermOccupancyTypes() throws {
        let full = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"AP9PT","datum":"14.1.2027","obsazeni":20,"limit":" 20 "}
        """).examTerm())
        #expect(full.occupied == 20)
        #expect(full.capacity == 20)
        #expect(full.isFull)

        let boxed = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"AP9PT","datum":"14.1.2027","obsazeni":{"value":"3"},"limit":{"value":"25"}}
        """).examTerm())
        #expect(boxed.freeSpots == 22)

        let unknown = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"AP9PT","datum":"14.1.2027","obsazeni":"","limit":null}
        """).examTerm())
        #expect(unknown.occupied == nil)
        #expect(unknown.capacity == nil)
        #expect(unknown.freeSpots == nil)
        #expect(!unknown.isFull)
    }

    @Test("Bez ID, předmětu nebo platného data není termín")
    func examTermMissingRequired() throws {
        let noID = try decodeJSON(StagExamTerm.self, #"{"predmet":"AP9PT","datum":"14.1.2027"}"#)
        #expect(noID.examTerm() == nil)
        let emptyID = try decodeJSON(StagExamTerm.self, #"{"termIdno":"","predmet":"AP9PT","datum":"14.1.2027"}"#)
        #expect(emptyID.examTerm() == nil)
        let noSubject = try decodeJSON(StagExamTerm.self, #"{"termIdno":"1","datum":"14.1.2027"}"#)
        #expect(noSubject.examTerm() == nil)
        let badDate = try decodeJSON(StagExamTerm.self, #"{"termIdno":"1","predmet":"AP9PT","datum":"zítra"}"#)
        #expect(badDate.examTerm() == nil)
    }

    @Test("Bez času začíná termín o půlnoci, konec před začátkem se zahodí")
    func examTermTimes() throws {
        let noTime = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"AP9PT","datum":"14.1.2027"}
        """).examTerm())
        #expect(noTime.start == makeDate(2027, 1, 14))
        #expect(noTime.end == nil)

        let reversed = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"AP9PT","datum":"14.1.2027","casOd":"10:00","casDo":"09:00"}
        """).examTerm())
        #expect(reversed.start == makeDate(2027, 1, 14, 10))
        #expect(reversed.end == nil)
    }

    @Test("Typ termínu, opravný, zrušený a výchozí hodnoty")
    func examTermFlagsAndDefaults() throws {
        let credit = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"2","predmet":"AP9EV","datum":"20.1.2027","typTerminu":"zápočet","opravny":"A","platnost":"N"}
        """).examTerm())
        #expect(credit.typeName == "Zápočet")
        #expect(credit.taskType == .zapocet)
        #expect(credit.isRetake)
        #expect(credit.isCancelled)

        let defaults = try #require(try decodeJSON(StagExamTerm.self, """
        {"termIdno":"3","predmet":"AP9EV","datum":"20.1.2027"}
        """).examTerm())
        #expect(defaults.typeName == "Termín")
        #expect(defaults.department == "")
        #expect(!defaults.isRegistered)
        #expect(!defaults.canChangeRegistration)
        #expect(!defaults.isRetake)
        #expect(!defaults.isCancelled)
        #expect(defaults.room == nil)
        #expect(defaults.teacher == nil)
        #expect(defaults.note == nil)
    }

    @Test("Místnost jen z budovy nebo jen z místnosti")
    func examTermRoom() throws {
        let roomOnly = try decodeJSON(StagExamTerm.self, #"{"termIdno":"1","predmet":"X","datum":"1.2.2027","mistnost":"202","budova":""}"#)
        #expect(roomOnly.examTerm()?.room == "202")
        let buildingOnly = try decodeJSON(StagExamTerm.self, #"{"termIdno":"1","predmet":"X","datum":"1.2.2027","budova":"52"}"#)
        #expect(buildingOnly.examTerm()?.room == "52")
    }

    @Test("Vyučující jako objekt s tituly i jako prostý text, důvod blokace")
    func examTermTeacherAndReason() throws {
        let titled = try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"X","datum":"1.2.2027",
         "ucitel":{"jmeno":"Petr","prijmeni":"Šilhavý","titulPred":"doc. Ing.","titulZa":"Ph.D."},
         "popisDuvoduProcNelzeZapsatOdepsat":"Termín je plně obsazen"}
        """)
        #expect(titled.ucitel == "doc. Ing. Petr Šilhavý, Ph.D.")
        #expect(titled.duvodNelze == "Termín je plně obsazen")

        let plain = try decodeJSON(StagExamTerm.self, #"{"termIdno":"1","predmet":"X","datum":"1.2.2027","ucitel":"Ing. Jan Novák"}"#)
        #expect(plain.ucitel == "Ing. Jan Novák")

        let emptyObject = try decodeJSON(StagExamTerm.self, #"{"termIdno":"1","predmet":"X","datum":"1.2.2027","ucitel":{}}"#)
        #expect(emptyObject.ucitel == nil)

        let preferText = try decodeJSON(StagExamTerm.self, """
        {"termIdno":"1","predmet":"X","datum":"1.2.2027","textDuvoduProcNelzeZapsatOdepsat":"Kolize","popisDuvoduProcNelzeZapsatOdepsat":"Jiný"}
        """)
        #expect(preferText.duvodNelze == "Kolize")
    }

    // MARK: - StagDateParser

    @Test("Formáty dat ze STAGu")
    func dateParserFormats() {
        #expect(StagDateParser.date("16.1.2026") == makeDate(2026, 1, 16))
        #expect(StagDateParser.date("16.01.2026") == makeDate(2026, 1, 16))
        #expect(StagDateParser.date("14.1.2027 23:59") == makeDate(2027, 1, 14, 23, 59))
        #expect(StagDateParser.date("16.1.2026 8:05") == makeDate(2026, 1, 16, 8, 5))
        #expect(StagDateParser.date("16.1.2026 08:30:00") == makeDate(2026, 1, 16, 8, 30))
        #expect(StagDateParser.date("2026-01-16T09:15:00") == makeDate(2026, 1, 16, 9, 15))
        #expect(StagDateParser.date("2026-01-16") == makeDate(2026, 1, 16))
        #expect(StagDateParser.date("  16.1.2026 ") == makeDate(2026, 1, 16))
        // Letní čas – stále pražský čas
        #expect(StagDateParser.date("15.6.2026 10:00") == makeDate(2026, 6, 15, 10, 0))
    }

    @Test("Neplatná data vrátí nil")
    func dateParserInvalid() {
        #expect(StagDateParser.date(nil) == nil)
        #expect(StagDateParser.date("") == nil)
        #expect(StagDateParser.date("   ") == nil)
        #expect(StagDateParser.date("neplatné") == nil)
        #expect(StagDateParser.date("32.13.2026") == nil)
    }

    @Test("combine přidá k datu čas v pražské zóně")
    func dateParserCombine() {
        let day = makeDate(2027, 1, 14)
        #expect(StagDateParser.combine(day, time: "09:30") == makeDate(2027, 1, 14, 9, 30))
        #expect(StagDateParser.combine(day, time: "9:05:00") == makeDate(2027, 1, 14, 9, 5))
        #expect(StagDateParser.combine(day, time: "23:59") == makeDate(2027, 1, 14, 23, 59))
        #expect(StagDateParser.combine(day, time: nil) == nil)
        #expect(StagDateParser.combine(day, time: "deset") == nil)
        #expect(StagDateParser.combine(day, time: "10") == nil)
        // Den změny času – čas na hodinách musí sedět
        #expect(StagDateParser.combine(makeDate(2026, 10, 25), time: "10:00") == makeDate(2026, 10, 25, 10, 0))
    }

    // MARK: - StagPeriod

    @Test("Akademický rok slovy")
    func periodTitle() throws {
        let period = try decodeJSON(StagPeriod.self, #"{"obdobi":"ZS","akademRok":"2026"}"#)
        #expect(period.academicYearTitle == "2026/2027")
        let weird = try decodeJSON(StagPeriod.self, #"{"obdobi":"LS","akademRok":"neznámý"}"#)
        #expect(weird.academicYearTitle == "neznámý")
    }
}
