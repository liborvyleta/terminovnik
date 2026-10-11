import Foundation

/// Termín zkoušky/zápočtu ze STAGu převedený do podoby pro aplikaci.
/// Není to SwiftData model – termíny se ukládají jako JSON (App Group) a při každém načtení přepíšou.
nonisolated struct ExamTerm: Codable, Identifiable, Hashable {
    /// termIdno ze STAGu
    let id: String
    let subjectCode: String
    let department: String
    /// Typ termínu ze STAGu („Zkouška“, „Zápočet“…)
    let typeName: String
    let start: Date
    let end: Date?
    /// „52/202“
    let room: String?
    let teacher: String?
    /// Obsazená místa / kapacita
    let occupied: Int?
    let capacity: Int?
    /// Student je na termín zapsaný
    let isRegistered: Bool
    /// Student se teď může zapsat / odhlásit
    let canChangeRegistration: Bool
    /// Proč se zapsat/odhlásit nelze (text ze STAGu)
    let blockReason: String?
    let registrationOpens: Date?
    let registrationDeadline: Date?
    let unregisterDeadline: Date?
    /// Opravný termín
    let isRetake: Bool
    let note: String?
    /// Zrušený termín (student na něm ale může být zapsaný)
    let isCancelled: Bool
}

nonisolated extension ExamTerm {
    /// Volná místa (nil = kapacita neznámá)
    var freeSpots: Int? {
        guard let capacity, let occupied else { return nil }
        return max(0, capacity - occupied)
    }

    var isFull: Bool { freeSpots == 0 }

    /// Termín ještě nezačal
    func isUpcoming(now: Date = .now) -> Bool { start > now }

    /// Odpovídající typ úkolu v aplikaci
    var taskType: TaskType {
        typeName.lowercased().contains("zápoč") || typeName.lowercased().contains("zapoc") ? .zapocet : .zkouska
    }

    /// Název úkolu, který z termínu vznikne
    func taskTitle(subjectName: String?) -> String {
        let name = subjectName ?? subjectCode
        return isRetake
            ? String(localized: "\(typeName) – \(name) (opravný)")
            : "\(typeName) – \(name)"
    }

    /// Ukázkové termíny pro náhledy (smyšlený zkoušející – žádné skutečné osoby)
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
