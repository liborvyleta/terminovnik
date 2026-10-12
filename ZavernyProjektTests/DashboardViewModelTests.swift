import Foundation
import SwiftData
import Testing
@testable import ZavernyProjekt

/// Testy view modelu přehledu (`DashboardViewModel`).
///
/// Ověřují sekce podle filtru, souhrnná čísla a vyhledávání.
/// Data žijí jen v paměťové SwiftData databázi. Akce `toggleCompletion`/`delete` netestujeme –
/// přes `TaskService` plánují notifikace a zapisují widget do App Group.
@MainActor
@Suite("Dashboard")
struct DashboardViewModelTests {
    let container: ModelContainer
    let context: ModelContext
    let calendar = TestCalendar.device
    /// Středa 7. 10. 2026 12:00 (kalendář zařízení – ViewModel interně používá Calendar.current)
    let now: Date

    let mobile: Subject
    let datamining: Subject

    let overdue: ExamTask
    let today: ExamTask
    let tomorrow: ExamTask
    let inFiveDays: ExamTask
    let inSevenDays: ExamTask
    let inEightDays: ExamTask
    let doneOld: ExamTask
    let doneRecent: ExamTask

    var allTasks: [ExamTask] { [doneOld, inEightDays, today, overdue, inSevenDays, doneRecent, tomorrow, inFiveDays] }

    init() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let calendar = TestCalendar.device
        self.container = container
        self.context = context
        now = makeDate(2026, 10, 7, 12, 0, calendar: calendar)

        let mobile = Subject(name: "Pokročilé mobilní technologie", code: "AP9PT", hexColor: "#3E63DD", credits: 5)
        let datamining = Subject(name: "Datamining", code: "AP9DM", hexColor: "#12A594", credits: 4)
        context.insert(mobile)
        context.insert(datamining)
        self.mobile = mobile
        self.datamining = datamining

        /// Vytvoří úkol, vloží ho do kontextu a přiřadí k předmětu.
        ///
        /// - Parameters:
        ///   - title: Název úkolu.
        ///   - type: Typ úkolu.
        ///   - due: Termín.
        ///   - subject: Předmět, ke kterému úkol patří.
        ///   - done: Zda je úkol splněný, výchozí `false`.
        ///   - note: Poznámka, výchozí prázdná.
        /// - Returns: Vložený úkol.
        func task(_ title: String, _ type: TaskType, _ due: Date, subject: Subject, done: Bool = false, note: String = "") -> ExamTask {
            let task = ExamTask(title: title, taskType: type, dueDate: due, isCompleted: done, note: note)
            context.insert(task)
            task.subject = subject
            return task
        }
        /// Vytvoří datum v říjnu 2026 v kalendáři testu.
        ///
        /// - Parameters:
        ///   - day: Den v měsíci.
        ///   - hour: Hodina.
        ///   - minute: Minuta, výchozí 0.
        /// - Returns: Odpovídající datum.
        func day(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { makeDate(2026, 10, day, hour, minute, calendar: calendar) }

        overdue = task("Domácí úkol 1", .ukol, day(6, 10), subject: mobile)
        today = task("Zkouška – 1. termín", .zkouska, day(7, 18), subject: mobile)
        tomorrow = task("Odevzdání projektu", .projekt, day(8, 9), subject: mobile, note: "Přes Moodle, včetně dokumentace")
        inFiveDays = task("Zápočtový test", .zapocet, day(12, 10), subject: mobile)
        inSevenDays = task("Prezentace", .ukol, day(14, 23), subject: datamining)
        inEightDays = task("Semestrální práce", .projekt, day(15, 8), subject: datamining)
        doneOld = task("Úvodní úkol", .ukol, day(1, 10), subject: mobile, done: true)
        doneRecent = task("Test z teorie", .zapocet, day(3, 10), subject: datamining, done: true)
    }

    /// Vrátí identifikátory sekcí v pořadí.
    ///
    /// - Parameter sections: Sekce přehledu.
    /// - Returns: Pole `id` jednotlivých sekcí.
    private func ids(_ sections: [TaskSection]) -> [String] { sections.map(\.id) }
    /// Vrátí názvy úkolů v sekci.
    ///
    /// - Parameter section: Sekce přehledu, nebo `nil`.
    /// - Returns: Názvy úkolů v pořadí; pro `nil` prázdné pole.
    private func titles(_ section: TaskSection?) -> [String] { section?.tasks.map(\.title) ?? [] }

    // MARK: - Filtry a sekce

    @Test("Výchozí filtr jsou nadcházející úkoly")
    func defaults() {
        let viewModel = DashboardViewModel()
        #expect(viewModel.filter == .upcoming)
        #expect(viewModel.searchText.isEmpty)
        #expect(!viewModel.isSearching)
        #expect(DashboardFilter.allCases.count == 3)
    }

    @Test("Blížící se: časové skupiny bez splněných, seřazené od nejbližšího")
    func upcomingSections() {
        let viewModel = DashboardViewModel()
        let sections = viewModel.sections(from: allTasks, now: now)
        #expect(ids(sections) == ["overdue", "soon", "week", "later"])
        #expect(titles(sections.first { $0.id == "overdue" }) == ["Domácí úkol 1"])
        #expect(titles(sections.first { $0.id == "soon" }) == ["Zkouška – 1. termín", "Odevzdání projektu"])
        #expect(titles(sections.first { $0.id == "week" }) == ["Zápočtový test", "Prezentace"])
        #expect(titles(sections.first { $0.id == "later" }) == ["Semestrální práce"])
        #expect(sections.allSatisfy { $0.tasks.allSatisfy { !$0.isCompleted } })
    }

    @Test("Vše: časové skupiny + splněné na konci, splněné od nejnovějšího")
    func allSections() {
        let viewModel = DashboardViewModel()
        viewModel.filter = .all
        let sections = viewModel.sections(from: allTasks, now: now)
        #expect(ids(sections) == ["overdue", "soon", "week", "later", "completed"])
        #expect(titles(sections.last) == ["Test z teorie", "Úvodní úkol"])
        #expect(sections.reduce(0) { $0 + $1.tasks.count } == allTasks.count)
    }

    @Test("Splněné: jen sekce splněných")
    func completedSection() {
        let viewModel = DashboardViewModel()
        viewModel.filter = .completed
        let sections = viewModel.sections(from: allTasks, now: now)
        #expect(ids(sections) == ["completed"])
        #expect(sections.first?.title == "Splněné")
        #expect(titles(sections.first) == ["Test z teorie", "Úvodní úkol"])
    }

    @Test("Prázdné skupiny se vynechají")
    func emptyGroupsSkipped() {
        let viewModel = DashboardViewModel()
        #expect(ids(viewModel.sections(from: [inFiveDays, inEightDays], now: now)) == ["week", "later"])
        #expect(viewModel.sections(from: [], now: now).isEmpty)

        viewModel.filter = .completed
        #expect(viewModel.sections(from: [today], now: now).isEmpty)
    }

    @Test("Hranice skupin: dnes/zítra, 2–7 dní, později; přesně teď není po termínu")
    func groupBoundaries() {
        let viewModel = DashboardViewModel()
        /// Zjistí, do které sekce přehled zařadí úkol s daným termínem.
        ///
        /// - Parameter due: Termín zkušebního úkolu.
        /// - Returns: `id` první sekce, nebo `nil`, pokud úkol do žádné nepatří.
        func group(_ due: Date) -> String? {
            let probe = ExamTask(title: "probe", taskType: .ukol, dueDate: due)
            context.insert(probe)
            return viewModel.sections(from: [probe], now: now).first?.id
        }
        #expect(group(now) == "soon")
        #expect(group(now.addingTimeInterval(-1)) == "overdue")
        #expect(group(makeDate(2026, 10, 8, 23, 59, calendar: calendar)) == "soon")
        #expect(group(makeDate(2026, 10, 9, 0, 0, calendar: calendar)) == "week")
        #expect(group(makeDate(2026, 10, 14, 23, 59, calendar: calendar)) == "week")
        #expect(group(makeDate(2026, 10, 15, 0, 0, calendar: calendar)) == "later")
    }

    // MARK: - Statistiky

    @Test("Souhrnná čísla: aktivní, tento týden (do 7 dní), po termínu")
    func stats() {
        let stats = DashboardViewModel().stats(from: allTasks, now: now)
        #expect(stats.active == 6)
        #expect(stats.overdue == 1)
        #expect(stats.thisWeek == 4)
    }

    @Test("Statistiky ignorují vyhledávání i filtr")
    func statsIgnoreSearch() {
        let viewModel = DashboardViewModel()
        viewModel.searchText = "datamining"
        viewModel.filter = .completed
        let stats = viewModel.stats(from: allTasks, now: now)
        #expect(stats.active == 6)
        #expect(stats.thisWeek == 4)
    }

    @Test("Bez úkolů jsou statistiky nulové")
    func statsEmpty() {
        let stats = DashboardViewModel().stats(from: [doneOld, doneRecent], now: now)
        #expect(stats.active == 0 && stats.thisWeek == 0 && stats.overdue == 0)
    }

    // MARK: - Vyhledávání

    /// Vyhledá úkoly ve všech testovacích datech.
    ///
    /// - Parameters:
    ///   - query: Hledaný text.
    ///   - filter: Filtr přehledu, výchozí `.all`.
    /// - Returns: Množina názvů nalezených úkolů.
    private func search(_ query: String, filter: DashboardFilter = .all) -> Set<String> {
        let viewModel = DashboardViewModel()
        viewModel.filter = filter
        viewModel.searchText = query
        return Set(viewModel.sections(from: allTasks, now: now).flatMap(\.tasks).map(\.title))
    }

    @Test("Hledání ignoruje diakritiku a velikost písmen")
    func searchDiacriticsInsensitive() {
        #expect(search("zapoctovy") == ["Zápočtový test"])
        #expect(search("ZÁPOČTOVÝ") == ["Zápočtový test"])
        #expect(search("domaci ukol") == ["Domácí úkol 1"])
        #expect(search("UVODNI") == ["Úvodní úkol"])
    }

    @Test("Hledání v předmětu (název i kód), typu a poznámce")
    func searchFields() {
        #expect(search("mobilni") == ["Domácí úkol 1", "Zkouška – 1. termín", "Odevzdání projektu", "Zápočtový test", "Úvodní úkol"])
        #expect(search("ap9dm") == ["Prezentace", "Semestrální práce", "Test z teorie"])
        #expect(search("moodle") == ["Odevzdání projektu"])
        #expect(search("dokumentace") == ["Odevzdání projektu"])
        // Typ „Zápočet“ (i bez diakritiky) najde oba zápočty, i když ho nemají v názvu
        #expect(search("zapocet") == ["Zápočtový test", "Test z teorie"])
    }

    @Test("Hledaný text se ořízne, mezery samy nic nefiltrují")
    func searchTrimmed() {
        let viewModel = DashboardViewModel()
        viewModel.searchText = "   "
        #expect(!viewModel.isSearching)
        viewModel.searchText = "  moodle \n"
        #expect(viewModel.isSearching)
        #expect(search("  moodle \n") == ["Odevzdání projektu"])
        #expect(search("   ").count == allTasks.count)
    }

    @Test("Hledání respektuje filtr a bez shody nevrací žádné sekce")
    func searchWithFilter() {
        #expect(search("ap9dm", filter: .upcoming) == ["Prezentace", "Semestrální práce"])
        #expect(search("ap9dm", filter: .completed) == ["Test z teorie"])

        let viewModel = DashboardViewModel()
        viewModel.searchText = "neexistující předmět"
        #expect(viewModel.sections(from: allTasks, now: now).isEmpty)
    }
}
