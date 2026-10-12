import Foundation

/// Termín zkoušky nebo zápočtu ze STAGu převedený do podoby pro aplikaci.
///
/// Není to SwiftData model – termíny se ukládají jako JSON (App Group) a při každém načtení
/// přepíšou. Ze zapsaného termínu může vzniknout `ExamTask` (propojení přes `ExamTask.stagTermID`).
nonisolated struct ExamTerm: Codable, Identifiable, Hashable {
    /// Identifikátor termínu ve STAGu (pole `termIdno`).
    let id: String
    /// Kód předmětu, např. „AP9PT“.
    let subjectCode: String
    /// Zkratka katedry, např. „AUIUI“.
    let department: String
    /// Typ termínu tak, jak ho uvádí STAG („Zkouška“, „Zápočet“…).
    let typeName: String
    /// Začátek termínu.
    let start: Date
    /// Konec termínu, pokud ho STAG uvádí.
    let end: Date?
    /// Budova a místnost, např. „52/202“.
    let room: String?
    /// Zkoušející.
    let teacher: String?
    /// Počet obsazených míst.
    let occupied: Int?
    /// Kapacita termínu.
    let capacity: Int?
    /// Příznak, že je student na termín zapsaný.
    let isRegistered: Bool
    /// Příznak, že se student teď může zapsat nebo odhlásit.
    let canChangeRegistration: Bool
    /// Důvod, proč se zapsat ani odhlásit nelze (text ze STAGu).
    let blockReason: String?
    /// Okamžik, od kdy je možné se na termín zapsat.
    let registrationOpens: Date?
    /// Poslední okamžik pro zápis na termín.
    let registrationDeadline: Date?
    /// Poslední okamžik pro odhlášení z termínu.
    let unregisterDeadline: Date?
    /// Příznak opravného termínu.
    let isRetake: Bool
    /// Poznámka k termínu ze STAGu.
    let note: String?
    /// Příznak zrušeného termínu (student na něm ale může být zapsaný).
    let isCancelled: Bool
}

nonisolated extension ExamTerm {
    /// Počet volných míst (nejméně 0); `nil`, pokud chybí kapacita nebo obsazenost.
    var freeSpots: Int? {
        guard let capacity, let occupied else { return nil }
        return max(0, capacity - occupied)
    }

    /// Příznak plně obsazeného termínu; při neznámé kapacitě je `false`.
    var isFull: Bool { freeSpots == 0 }

    /// Zjistí, zda termín ještě nezačal.
    /// - Parameter now: Referenční okamžik, výchozí je aktuální čas.
    /// - Returns: `true`, pokud je začátek termínu později než `now`.
    func isUpcoming(now: Date = .now) -> Bool { start > now }

    /// Odpovídající typ úkolu v aplikaci.
    ///
    /// Typ obsahující „zápoč“ nebo „zapoc“ (bez ohledu na velikost písmen) je zápočet, vše ostatní zkouška.
    var taskType: TaskType {
        typeName.lowercased().contains("zápoč") || typeName.lowercased().contains("zapoc") ? .zapocet : .zkouska
    }

    /// Sestaví název úkolu, který z termínu vznikne, např. „Zkouška – Datamining“.
    ///
    /// U opravného termínu se připojí lokalizovaný doplněk „(opravný)“.
    /// - Parameter subjectName: Název předmětu; při `nil` se použije kód předmětu.
    /// - Returns: Název úkolu.
    func taskTitle(subjectName: String?) -> String {
        let name = subjectName ?? subjectCode
        return isRetake
            ? String(localized: "\(typeName) – \(name) (opravný)")
            : "\(typeName) – \(name)"
    }

    /// Pět ukázkových termínů relativně k dnešku pro náhledy a ukázkový režim.
    ///
    /// Zkoušející je smyšlený – žádné skutečné osoby.
    static var samples: [ExamTerm] {
        let calendar = Calendar.current
        func day(_ offset: Int, _ hour: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }
        func term(_ id: String, _ code: String, _ type: String, _ offset: Int, _ hour: Int, _ room: String,
                  _ occupied: Int, _ capacity: Int, registered: Bool, retake: Bool = false) -> ExamTerm {
            ExamTerm(id: id, subjectCode: code, department: "AUIUI", typeName: type, start: day(offset, hour),
                     end: day(offset, hour + 2), room: room, teacher: "doc. Ing. Petr Svoboda, Ph.D.", occupied: occupied,
                     capacity: capacity, isRegistered: registered, canChangeRegistration: true, blockReason: nil,
                     registrationOpens: day(-3, 8), registrationDeadline: day(offset - 2, 23),
                     unregisterDeadline: day(offset - 1, 12), isRetake: retake, note: nil, isCancelled: false)
        }
        return [
            term("t1", "AP9PT", "Zkouška", 9, 9, "52/202", 14, 20, registered: true),
            term("t2", "AP9PT", "Zkouška", 16, 9, "52/202", 6, 20, registered: false),
            term("t3", "AP9EV", "Zápočet", 5, 10, "54/304", 18, 18, registered: false),
            term("t4", "AP9DM", "Zkouška", 12, 13, "54/211", 3, 25, registered: false),
            term("t5", "AP9DM", "Zkouška", 26, 9, "54/211", 0, 25, registered: false, retake: true)
        ]
    }
}
