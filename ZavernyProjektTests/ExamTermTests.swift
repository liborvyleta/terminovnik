import Foundation
import Testing
@testable import ZavernyProjekt

/// Testy odvozených vlastností termínu zkoušky.
///
/// Pokrývají vlastnosti modelu `ExamTerm`, například počet volných míst.
@Suite("Termíny zkoušek")
struct ExamTermTests {
    private let start = makeDate(2027, 1, 14, 9, 0)

    /// Vytvoří termín zkoušky z předmětu AP9PT s nastavitelnými vlastnostmi.
    ///
    /// - Parameters:
    ///   - id: Identifikátor termínu.
    ///   - typeName: Název typu termínu.
    ///   - start: Začátek; `nil` znamená výchozí `start` testu.
    ///   - occupied: Počet obsazených míst.
    ///   - capacity: Kapacita termínu.
    ///   - isRetake: Zda jde o opravný termín.
    /// - Returns: Nový termín zkoušky.
    private func term(
        id: String = "t1",
        typeName: String = "Zkouška",
        start: Date? = nil,
        occupied: Int? = 14,
        capacity: Int? = 20,
        isRetake: Bool = false
    ) -> ExamTerm {
        ExamTerm(
            id: id, subjectCode: "AP9PT", department: "AUIUI", typeName: typeName,
            start: start ?? self.start, end: nil, room: "52/202", teacher: nil,
            occupied: occupied, capacity: capacity, isRegistered: false, canChangeRegistration: true,
            blockReason: nil, registrationOpens: nil, registrationDeadline: nil, unregisterDeadline: nil,
            isRetake: isRetake, note: nil, isCancelled: false
        )
    }

    // MARK: - Volná místa

    @Test("Volná místa = kapacita − obsazeno, nikdy záporná")
    func freeSpots() {
        #expect(term(occupied: 14, capacity: 20).freeSpots == 6)
        #expect(term(occupied: 0, capacity: 25).freeSpots == 25)
        #expect(term(occupied: 20, capacity: 20).freeSpots == 0)
        #expect(term(occupied: 25, capacity: 20).freeSpots == 0)
    }

    @Test("Neznámá kapacita nebo obsazenost → volná místa nil")
    func freeSpotsUnknown() {
        #expect(term(occupied: nil, capacity: 20).freeSpots == nil)
        #expect(term(occupied: 5, capacity: nil).freeSpots == nil)
        #expect(term(occupied: nil, capacity: nil).freeSpots == nil)
    }

    @Test("Plný termín")
    func isFull() {
        #expect(term(occupied: 20, capacity: 20).isFull)
        #expect(term(occupied: 21, capacity: 20).isFull)
        #expect(!term(occupied: 19, capacity: 20).isFull)
        // Neznámá kapacita se nebere jako plno
        #expect(!term(occupied: 20, capacity: nil).isFull)
        #expect(!term(occupied: nil, capacity: nil).isFull)
    }

    // MARK: - Typ úkolu

    @Test(
        "Zápočet × zkouška podle názvu typu",
        arguments: [
            ("Zkouška", TaskType.zkouska),
            ("zkouška", .zkouska),
            ("Termín", .zkouska),
            ("Kolokvium", .zkouska),
            ("Zápočet", .zapocet),
            ("zápočet", .zapocet),
            ("ZÁPOČET", .zapocet),
            ("Zapocet", .zapocet),
            ("Klasifikovaný zápočet", .zapocet),
            ("Zápočtový test", .zapocet)
        ]
    )
    func taskType(typeName: String, expected: TaskType) {
        #expect(term(typeName: typeName).taskType == expected)
    }

    // MARK: - Nadcházející

    @Test("isUpcoming jen pro termíny, které ještě nezačaly")
    func isUpcoming() {
        let exam = term(start: start)
        #expect(exam.isUpcoming(now: start.addingTimeInterval(-60)))
        #expect(!exam.isUpcoming(now: start))
        #expect(!exam.isUpcoming(now: start.addingTimeInterval(60)))
        #expect(exam.isUpcoming(now: makeDate(2026, 10, 7, 12)))
    }

    // MARK: - Název úkolu

    @Test("Název úkolu z termínu")
    func taskTitle() {
        #expect(term().taskTitle(subjectName: "Pokročilé mobilní technologie") == "Zkouška – Pokročilé mobilní technologie")
        #expect(term(typeName: "Zápočet").taskTitle(subjectName: nil) == "Zápočet – AP9PT")
        #expect(term(isRetake: true).taskTitle(subjectName: "Datamining") == "Zkouška – Datamining (opravný)")
    }

    // MARK: - Ukládání a ukázková data

    @Test("Termín přežije JSON (ukládá se jako JSON do App Group)")
    func codableRoundTrip() throws {
        let original = term()
        let decoded = try JSONDecoder().decode(ExamTerm.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("Ukázkové termíny mají unikátní ID a obsahují plný termín")
    func samples() {
        let samples = ExamTerm.samples
        #expect(samples.count == 5)
        #expect(Set(samples.map(\.id)).count == samples.count)
        #expect(samples.contains { $0.isFull })
        #expect(samples.contains { $0.isRegistered })
        #expect(samples.contains { $0.taskType == .zapocet })
    }
}
