import Foundation
import SwiftData
import Testing
@testable import ZavernyProjekt

/// Testy ukázkového režimu (`DemoMode`, `DemoData`).
///
/// Ověřují zapínání režimu příznakem a spouštěcím argumentem, izolovaný paměťový kontejner
/// s ukázkovými daty a konzistenci ukázkových předmětů, úkolů, termínů a známek.
@MainActor
struct DemoModeTests {
    /// Vytvoří prázdné vlastní úložiště `UserDefaults` s unikátním názvem.
    ///
    /// Testy se tak nedotknou `UserDefaults.standard` aplikace.
    ///
    /// - Returns: Nová prázdná instance `UserDefaults`.
    private func makeDefaults() -> UserDefaults {
        let name = "DemoModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Příznak v úložišti zapíná a vypíná ukázkový režim; po vypnutí se klíč odstraní.
    @Test func flagTogglesDemoMode() {
        let defaults = makeDefaults()
        #expect(!DemoMode.isActive(defaults: defaults, arguments: []))
        DemoMode.setFlag(true, defaults: defaults)
        #expect(DemoMode.isActive(defaults: defaults, arguments: []))
        DemoMode.setFlag(false, defaults: defaults)
        #expect(!DemoMode.isActive(defaults: defaults, arguments: []))
        #expect(defaults.object(forKey: DemoMode.defaultsKey) == nil)
    }

    /// Spouštěcí argument `-demo` zapne ukázkový režim jen v ladicím sestavení.
    @Test func launchArgumentOnlyInDebug() {
        let defaults = makeDefaults()
        #if DEBUG
        #expect(DemoMode.isActive(defaults: defaults, arguments: ["-demo"]))
        #else
        #expect(!DemoMode.isActive(defaults: defaults, arguments: ["-demo"]))
        #endif
    }

    /// Ukázkový kontejner je jen v paměti a každý nový kontejner začíná prázdný.
    @Test func demoContainerIsInMemoryAndIsolated() throws {
        let demo = DemoData.makeContainer(schema: PersistenceController.schema)
        let inMemory = demo.configurations.allSatisfy { $0.isStoredInMemoryOnly }
        #expect(inMemory)
        DemoData.insertSubjects(into: demo.mainContext)
        #expect(try demo.mainContext.fetchCount(FetchDescriptor<Subject>()) > 0)

        // Nový demo kontejner je prázdný – data nikam neunikají
        let other = DemoData.makeContainer(schema: PersistenceController.schema)
        #expect(try other.mainContext.fetchCount(FetchDescriptor<Subject>()) == 0)
    }

    /// Ukázkové předměty mají unikátní kódy, každý úkol má předmět a termíny i rozvrh patří k ukázkovým předmětům.
    @Test func demoSubjectsAndTasksAreConsistent() throws {
        let container = DemoData.makeContainer(schema: PersistenceController.schema)
        DemoData.insertSubjects(into: container.mainContext)
        let subjects = try container.mainContext.fetch(FetchDescriptor<Subject>())
        let tasks = try container.mainContext.fetch(FetchDescriptor<ExamTask>())

        #expect(subjects.count == 6)
        #expect(Set(subjects.map(\.code)).count == subjects.count)
        #expect(!tasks.isEmpty)
        #expect(tasks.allSatisfy { $0.subject != nil })

        // Termíny a známky patří k předmětům dema (nebo k dřívějším semestrům u známek)
        let codes = Set(subjects.map(\.code))
        #expect(ExamTerm.samples.allSatisfy { codes.contains($0.subjectCode) })
        #expect(TimetableSnapshot.sample.events.allSatisfy { codes.contains($0.subjectCode) })
    }

    /// Jméno ukázkového studenta se neobjevuje mezi vyučujícími ani zkoušejícími.
    @Test func teachersDifferFromDemoStudent() {
        let student = DemoData.account.fullName
        #expect(ExamTerm.samples.allSatisfy { !($0.teacher ?? "").contains(student) })
        let examiners = SubjectGrade.samples.flatMap { [$0.creditTest?.examiner, $0.exam?.examiner] }.compactMap { $0 }
        #expect(!examiners.isEmpty)
        #expect(examiners.allSatisfy { !$0.contains(student) })
        #expect(TimetableSnapshot.sample.events.allSatisfy { !($0.teacher ?? "").contains(student) })
    }
}
