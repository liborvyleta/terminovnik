import Foundation
import SwiftData

/// Ukázková data pro rychlé vyzkoušení aplikace a pro SwiftUI Previews.
///
/// Vytváří čtyři předměty s úkoly různých typů a stavů relativně k dnešku. Data vkládá do předaného
/// `ModelContext` a ukládá přes ``TaskService/save(_:)``; pro náhledy poskytuje ``previewContainer``.
enum SampleData {
    /// Vloží ukázková data jen do prázdné databáze (nevznikají duplicity).
    /// - Parameters:
    ///   - context: cílový kontext SwiftData
    ///   - scheduleNotifications: zda pro nové úkoly naplánovat připomínky
    static func insertIfEmpty(into context: ModelContext, scheduleNotifications: Bool = true) {
        let count = (try? context.fetchCount(FetchDescriptor<Subject>())) ?? 0
        guard count == 0 else { return }
        insert(into: context, scheduleNotifications: scheduleNotifications)
    }

    /// Vloží ukázkové předměty a úkoly bez ohledu na obsah databáze a uloží je.
    /// - Parameters:
    ///   - context: cílový kontext SwiftData
    ///   - scheduleNotifications: zda přes `NotificationManager` naplánovat připomínky úkolů
    static func insert(into context: ModelContext, scheduleNotifications: Bool = true) {
        let mobile = Subject(name: "Pokročilé mobilní technologie", code: "AP9PT", hexColor: SubjectPalette.hex(7), credits: 4)
        let databases = Subject(name: "Databázové systémy", code: "AP7DS", hexColor: SubjectPalette.hex(4), credits: 6)
        let math = Subject(name: "Matematika II", code: "AUMA2", hexColor: SubjectPalette.hex(1), credits: 4)
        let english = Subject(name: "Angličtina pro IT", code: "AUAJ3", hexColor: SubjectPalette.hex(9), credits: 2)
        for subject in [mobile, databases, math, english] {
            context.insert(subject)
        }

        // Pomocná funkce: nejdřív objekt vložíme do kontextu, teprve pak nastavíme vazbu.
        func add(
            _ title: String, _ type: TaskType, inDays days: Int, at hour: Int, minute: Int = 0,
            to subject: Subject, done: Bool = false, grade: String? = nil, note: String = ""
        ) {
            let task = ExamTask(
                title: title,
                taskType: type,
                dueDate: date(daysFromNow: days, hour: hour, minute: minute),
                isCompleted: done,
                pointsOrGrade: grade,
                note: note
            )
            context.insert(task)
            task.subject = subject
            if scheduleNotifications {
                NotificationManager.shared.updateReminder(for: task)
            }
        }

        add("Zápočtový test – SwiftUI", .zapocet, inDays: 1, at: 10, to: mobile, note: "Učebna U54/310")
        add("Závěrečný projekt – odevzdání", .projekt, inDays: 4, at: 23, minute: 59, to: mobile, note: "Odevzdat přes Moodle včetně README")
        add("Úkol 3: SwiftData", .ukol, inDays: -9, at: 23, minute: 59, to: mobile, done: true, grade: "10/10")
        add("Zkouška – 1. termín", .zkouska, inDays: 12, at: 9, to: databases, note: "Písemná část + ústní")
        add("SQL úkol – normalizace", .ukol, inDays: 2, at: 22, to: databases)
        add("Semestrální projekt – E-R model", .projekt, inDays: -3, at: 12, to: databases, done: true, grade: "18 b")
        add("Písemka z integrálů", .zapocet, inDays: 6, at: 8, to: math)
        add("Domácí úkol 4", .ukol, inDays: -1, at: 20, to: math)
        add("Zkouška", .zkouska, inDays: 20, at: 9, to: math)
        add("Prezentace – IT trendy", .ukol, inDays: 3, at: 12, to: english)
        add("Ústní zkouška", .zkouska, inDays: 25, at: 13, to: english)

        TaskService.save(context)
    }

    /// Datum za X dní v zadanou hodinu.
    /// - Parameters:
    ///   - days: posun od dnešního dne (záporný = v minulosti)
    ///   - hour: hodina
    ///   - minute: minuta (výchozí 0)
    /// - Returns: Datum v aktuálním kalendáři; při selhání výpočtu začátek dne nebo `now`.
    static func date(daysFromNow days: Int, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now)) ?? .now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: - Previews

    /// In-memory kontejner s ukázkovými daty pro #Preview (bez plánování připomínek)
    static let previewContainer: ModelContainer = {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: Subject.self, ExamTask.self, configurations: configuration)
            insert(into: container.mainContext, scheduleNotifications: false)
            return container
        } catch {
            fatalError("Nepodařilo se vytvořit preview kontejner: \(error)")
        }
    }()

    /// První předmět z preview kontejneru (pro náhled detailu), řazeno podle názvu.
    ///
    /// - Important: Pokud kontejner neobsahuje žádný předmět, aplikace skončí `fatalError`.
    static var previewSubject: Subject {
        let descriptor = FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.name)])
        guard let subject = try? previewContainer.mainContext.fetch(descriptor).first else {
            fatalError("Preview kontejner neobsahuje žádný předmět")
        }
        return subject
    }
}
