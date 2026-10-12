import Foundation
import SwiftData

/// Smyšlená data ukázkového režimu.
///
/// Ukázkový režim (viz `DemoMode`) běží nad úložištěm SwiftData jen v paměti a naplní
/// i úložiště dat ze STAGu (účet, rozvrh, termíny, známky, budovy). Žádné skutečné osoby –
/// jména jsou vymyšlená.
enum DemoData {
    /// Fiktivní přihlášený student (účet UTB, fakulta FAI).
    static let account = StagAccount(
        fullName: "Jan Novák",
        osCislo: "A00000",
        stagUser: "demo",
        faculty: "FAI",
        connectedAt: Calendar.current.date(byAdding: .day, value: -12, to: .now) ?? .now,
        lastSyncAt: .now,
        school: .utb
    )

    /// Vytvoří úložiště SwiftData jen v paměti pro ukázkový režim.
    ///
    /// Skutečná databáze se pro zápis vůbec neotevírá; synchronizace přes CloudKit je vypnutá.
    /// Pokud kontejner nejde vytvořit, aplikace skončí přes `fatalError`.
    /// - Parameter schema: Schéma modelů aplikace.
    /// - Returns: Kontejner uložený výhradně v paměti.
    static func makeContainer(schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Demo úložiště se nepodařilo vytvořit: \((error as NSError).code)")
        }
    }

    /// Naplní ukázkové úložiště a všechna úložiště dat ze STAGu ukázkovými daty (vše jen v paměti).
    ///
    /// V režimu DEBUG nejdřív zpracuje argumenty spuštění pro snímky obrazovky.
    /// - Parameter container: Kontejner ukázkového režimu, do kterého se vloží předměty a úkoly.
    static func prepare(container: ModelContainer) {
        #if DEBUG
        applyLaunchArguments()
        #endif
        insertSubjects(into: container.mainContext)
        StagAccountStore.shared.loadDemo(account)
        TimetableStore.shared.loadDemo(.sample)
        ExamTermStore.shared.loadDemo(ExamTerm.samples, newIDs: ["t4"])
        GradeStore.shared.loadDemo(SubjectGrade.samples)
        BuildingStore.shared.loadDemo(buildings)
    }

    #if DEBUG
    /// Zpracuje argumenty spuštění pro snímky obrazovky a uloží je do `UserDefaults`.
    ///
    /// Podporuje `-tab dashboard|timetable|terms|subjects|grades|settings` (hodnota `grades`
    /// se mapuje na záložku Předměty) a `-timetableMode day|week`. Neplatné hodnoty ignoruje.
    private static func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if let tab = DemoMode.argument(after: "-tab") {
            // Známky jsou dostupné ze záložky Předměty
            let valid = ["dashboard", "timetable", "terms", "subjects", "settings"]
            let mapped = tab == "grades" ? "subjects" : tab
            if valid.contains(mapped) { defaults.set(mapped, forKey: "selectedTab") }
        }
        if let mode = DemoMode.argument(after: "-timetableMode"), ["day", "week"].contains(mode) {
            defaults.set(mode, forKey: "timetableDisplayMode")
        }
    }
    #endif

    // MARK: - Předměty a deadliny

    /// Vloží šest ukázkových předmětů a k nim deset deadlinů a uloží kontext.
    ///
    /// Termíny se počítají relativně k dnešku (`SampleData.date(daysFromNow:hour:minute:)`),
    /// jeden úkol je už splněný a jeden po termínu.
    /// - Parameter context: Kontext, do kterého se data vloží.
    static func insertSubjects(into context: ModelContext) {
        let mobile = Subject(name: "Pokročilé mobilní technologie", code: "AP9PT", hexColor: "#3E63DD", credits: 4)
        let evolution = Subject(name: "Evoluční výpočetní techniky", code: "AP9EV", hexColor: "#B8860B", credits: 5)
        let mining = Subject(name: "Datamining", code: "AP9DM", hexColor: "#12A594", credits: 5)
        let security = Subject(name: "Bezpečnost informačních systémů", code: "AP9BI", hexColor: "#E5484D", credits: 4)
        let software = Subject(name: "Softwarové inženýrství II", code: "AP9SI", hexColor: "#8E4EC6", credits: 6)
        let english = Subject(name: "Odborná angličtina", code: "AP9AJ", hexColor: "#F76B15", credits: 2)
        for subject in [mobile, evolution, mining, security, software, english] { context.insert(subject) }

        func add(_ title: String, _ type: TaskType, days: Int, hour: Int, minute: Int = 0, _ subject: Subject,
                 done: Bool = false, grade: String? = nil, note: String = "") {
            let task = ExamTask(title: title, taskType: type,
                                dueDate: SampleData.date(daysFromNow: days, hour: hour, minute: minute),
                                isCompleted: done, pointsOrGrade: grade, note: note)
            context.insert(task)
            task.subject = subject
        }

        add("Závěrečný projekt – odevzdání", .projekt, days: 0, hour: 23, minute: 59, mobile, note: "Odevzdat přes Moodle včetně README a videa")
        add("Zápočtový test – SwiftUI", .zapocet, days: 1, hour: 10, mobile, note: "Učebna U52/202, s sebou notebook")
        add("Implementace genetického algoritmu", .ukol, days: 3, hour: 22, evolution, note: "Python, report max. 4 strany")
        add("Semestrální práce – klasifikace", .projekt, days: 7, hour: 23, minute: 59, mining, note: "Dataset z UCI, porovnat 3 modely")
        add("Analýza rizik – case study", .ukol, days: 14, hour: 12, security, note: "Týmová práce (3 lidé)")
        add("Zkouška – 1. termín", .zkouska, days: 9, hour: 9, mobile, note: "Písemná část + obhajoba projektu")
        add("Prezentace architektury", .ukol, days: 5, hour: 14, software)
        add("UML diagramy – návrh systému", .ukol, days: -6, hour: 23, minute: 59, software, done: true, grade: "9/10")
        add("Esej – Technology trends", .ukol, days: -1, hour: 20, english, note: "Min. 800 slov")
        add("Zkouška", .zkouska, days: 21, hour: 9, mining)

        try? context.save()
    }

    // MARK: - Budovy UTB (souřadnice přibližné, kromě U52)

    /// Ukázkové budovy UTB pro mapu; souřadnice jsou přibližné (kromě U52 z `StagBuilding.sample`).
    static let buildings: [StagBuilding] = [
        StagBuilding.sample,
        StagBuilding(code: "51", street: "U51 - (Severní pavilon A) Nad stráněmi", streetNumber: "4511", city: "Zlín",
                     latitude: 49.23099, longitude: 17.65701),
        StagBuilding(code: "53", street: "U53 - Nad stráněmi", streetNumber: "4511", city: "Zlín",
                     latitude: 49.23020, longitude: 17.65790),
        StagBuilding(code: "54", street: "U54 - (Fakulta aplikované informatiky) Nad stráněmi", streetNumber: "4511", city: "Zlín",
                     latitude: 49.23080, longitude: 17.65790),
        StagBuilding(code: "U5", street: "U5 - Mostní", streetNumber: "5139", city: "Zlín",
                     latitude: 49.22670, longitude: 17.66820)
    ]
}
