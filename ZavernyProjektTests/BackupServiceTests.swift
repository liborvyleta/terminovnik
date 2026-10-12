import Foundation
import SwiftData
import Testing
@testable import ZavernyProjekt

/// Testy zálohy dat do souboru (`BackupService`).
///
/// Ověřují kódování a dekódování zálohy, obnovu ve sloučení i nahrazení, odmítnutí neznámé verze
/// a poškozených dat, tolerantní dekódování a odstranění duplicit importovaných ze STAGu.
@MainActor
struct BackupServiceTests {
    private let old = makeDate(2026, 1, 1)
    private let new = makeDate(2026, 6, 1)

    /// Vloží do kontextu jeden předmět s jedním splněným úkolem a uloží je.
    ///
    /// Oba záznamy mají `updatedAt` nastavené na starší datum `old`.
    ///
    /// - Parameter context: Kontext, do kterého se data vloží.
    /// - Returns: Vložený předmět a k němu přiřazený úkol.
    private func seed(_ context: ModelContext) -> (Subject, ExamTask) {
        let subject = Subject(name: "Mobilní technologie", code: "AP9PT", hexColor: "#FF0000", credits: 5)
        subject.updatedAt = old
        let task = ExamTask(title: "Zkouška", taskType: .zkouska, dueDate: makeDate(2027, 1, 20, 9),
                            isCompleted: true, pointsOrGrade: "A", note: "Místnost 52/202", stagTermID: "123")
        task.updatedAt = old
        context.insert(subject)
        context.insert(task)
        task.subject = subject
        try? context.save()
        return (subject, task)
    }

    /// Záloha po zakódování, dekódování a obnově do nové databáze zachová všechna pole úkolu i předmětu.
    @Test func roundtrip() throws {
        let sourceContainer = try makeInMemoryContainer() // kontejner musí žít po celý test, kontext ho nedrží
        let source = sourceContainer.mainContext
        let (subject, task) = seed(source)
        let data = try BackupService.encode(BackupService.makeBackup(from: source, now: new))

        let decoded = try BackupService.decode(data)
        #expect(decoded.version == 1)
        #expect(decoded.createdAt == new)

        let targetContainer = try makeInMemoryContainer()
        let target = targetContainer.mainContext
        try BackupService.restore(decoded, into: target, mode: .merge)
        let restored = try #require(try target.fetch(FetchDescriptor<ExamTask>()).first)
        #expect(restored.id == task.id)
        #expect(restored.note == "Místnost 52/202")
        #expect(restored.isCompleted)
        #expect(restored.pointsOrGrade == "A")
        #expect(restored.taskType == .zkouska)
        #expect(restored.stagTermID == "123")
        #expect(restored.subject?.id == subject.id)
        #expect(restored.subject?.credits == 5)
    }

    /// Sloučení nevytváří duplicity, přidá nový úkol a u existujících záznamů vyhraje novější verze.
    @Test func mergeDedupsAndNewerWins() throws {
        let contextContainer = try makeInMemoryContainer()
        let context = contextContainer.mainContext
        let (subject, task) = seed(context)
        var backup = try BackupService.makeBackup(from: context)
        // Novější úkol v záloze, starší předmět v záloze, plus jeden nový úkol
        backup.tasks[0].title = "Zkouška – nový název"
        backup.tasks[0].updatedAt = new
        backup.subjects[0].name = "Starý název"
        backup.subjects[0].updatedAt = makeDate(2025, 1, 1)
        backup.tasks.append(.init(id: UUID(), title: "Projekt", taskType: "projekt", dueDate: new, isCompleted: false,
                                  pointsOrGrade: nil, note: "", stagTermID: nil, subjectID: subject.id, updatedAt: nil))

        let summary = try BackupService.restore(backup, into: context, mode: .merge)
        #expect(summary == .init(subjectsAdded: 0, subjectsUpdated: 0, tasksAdded: 1, tasksUpdated: 1))
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ExamTask>()) == 2)
        #expect(task.title == "Zkouška – nový název")
        #expect(subject.name == "Mobilní technologie")
        #expect(subject.taskList.count == 2)
    }

    /// Režim nahrazení smaže stávající předměty i úkoly a ponechá jen data ze zálohy.
    @Test func replaceRemovesExisting() throws {
        let contextContainer = try makeInMemoryContainer()
        let context = contextContainer.mainContext
        _ = seed(context)
        let backup = BackupFile(createdAt: new, appVersion: nil,
                                subjects: [.init(id: UUID(), name: "Datamining", code: "AP9DM", hexColor: "#00FF00", credits: 4, updatedAt: nil)],
                                tasks: [])
        try BackupService.restore(backup, into: context, mode: .replace)
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        #expect(subjects.map(\.code) == ["AP9DM"])
        #expect(try context.fetchCount(FetchDescriptor<ExamTask>()) == 0)
    }

    /// Záloha s neznámou verzí formátu je odmítnuta chybou `unsupportedVersion`.
    @Test func unknownVersionIsRejected() throws {
        let data = Data(#"{"version": 99, "createdAt": "2026-01-01T00:00:00Z", "subjects": "cokoli"}"#.utf8)
        #expect(throws: BackupService.BackupError.unsupportedVersion(99)) { try BackupService.decode(data) }
    }

    /// Neplatný JSON nebo chybějící povinná pole vedou k chybě `corrupted`.
    @Test func corruptedFileIsRejected() throws {
        #expect(throws: BackupService.BackupError.corrupted) { try BackupService.decode(Data("není json".utf8)) }
        #expect(throws: BackupService.BackupError.corrupted) { try BackupService.decode(Data(#"{"subjects": []}"#.utf8)) }
    }

    /// Poškozené položky se přeskočí, chybějící hodnoty dostanou výchozí hodnoty a neznámý typ úkolu se změní na úkol.
    @Test func tolerantDecodingSkipsBrokenItems() throws {
        let json = #"""
        {"version": 1, "subjects": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "code": "AP9PT"}, {"name": "bez id"}],
         "tasks": [{"id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "dueDate": "2026-05-01T08:00:00Z", "taskType": "neznamy", "extra": 1}]}
        """#
        let backup = try BackupService.decode(Data(json.utf8))
        #expect(backup.subjects.count == 1)
        #expect(backup.subjects[0].credits == 0)
        #expect(backup.tasks.count == 1)
        let contextContainer = try makeInMemoryContainer()
        let context = contextContainer.mainContext
        try BackupService.restore(backup, into: context, mode: .merge)
        #expect(try context.fetch(FetchDescriptor<ExamTask>()).first?.taskType == .ukol)
    }

    /// Název souboru zálohy obsahuje datum vytvoření.
    @Test func fileNameContainsDate() {
        #expect(BackupService.fileName(for: makeDate(2026, 10, 11, 12), calendar: TestCalendar.prague) == "Termínovník-záloha-2026-10-11")
    }

    /// Duplicitní předmět (kód bez ohledu na velikost písmen) a úkol se stejným ID termínu STAGu se odstraní.
    @Test func removesStagDuplicates() throws {
        let contextContainer = try makeInMemoryContainer()
        let context = contextContainer.mainContext
        let (_, _) = seed(context)
        let copy = Subject(name: "Kopie", code: "ap9pt", hexColor: "#000000")
        let copyTask = ExamTask(title: "Zkouška", taskType: .zkouska, dueDate: .now, stagTermID: "123")
        context.insert(copy)
        context.insert(copyTask)
        copyTask.subject = copy
        try context.save()

        let removed = try BackupService.removeStagDuplicates(in: context)
        #expect(removed == 2)
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 1)
        let remaining = try context.fetch(FetchDescriptor<ExamTask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isCompleted == true)
    }
}
