import AppIntents
import Foundation
import SwiftData

// Společné typy pro akce Siri, Zkratek a Spotlightu (App Intents).
// Typy, se kterými systém pracuje mimo hlavní vlákno (výčty, entita, dotaz), jsou `nonisolated`.
// Práce se SwiftData a formátování probíhá na MainActoru (`IntentStore`, `IntentText`).

// MARK: - Den pro „Rozvrh na den“

/// Den, pro který se vypíše rozvrh.
nonisolated enum ScheduleDay: String, AppEnum {
    case dnes
    case zitra
    case pozitri

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Den"

    static let caseDisplayRepresentations: [ScheduleDay: DisplayRepresentation] = [
        .dnes: "Dnes",
        .zitra: "Zítra",
        .pozitri: "Pozítří"
    ]

    /// Posun od dneška ve dnech
    var dayOffset: Int {
        switch self {
        case .dnes: 0
        case .zitra: 1
        case .pozitri: 2
        }
    }

    /// Název dne do věty
    var label: String {
        switch self {
        case .dnes: String(localized: "Dnes")
        case .zitra: String(localized: "Zítra")
        case .pozitri: String(localized: "Pozítří")
        }
    }
}

// MARK: - Typ povinnosti

/// Typ nové povinnosti pro akci „Přidat deadline“ (zrcadlí `TaskType`).
nonisolated enum DeadlineKind: String, AppEnum {
    case zkouska
    case zapocet
    case projekt
    case ukol

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Typ povinnosti"

    static let caseDisplayRepresentations: [DeadlineKind: DisplayRepresentation] = [
        .zkouska: DisplayRepresentation(title: "Zkouška", image: .init(systemName: "graduationcap.fill")),
        .zapocet: DisplayRepresentation(title: "Zápočet", image: .init(systemName: "checkmark.seal.fill")),
        .projekt: DisplayRepresentation(title: "Projekt", image: .init(systemName: "hammer.fill")),
        .ukol: DisplayRepresentation(title: "Úkol", image: .init(systemName: "doc.text.fill"))
    ]

    @MainActor
    var taskType: TaskType {
        switch self {
        case .zkouska: .zkouska
        case .zapocet: .zapocet
        case .projekt: .projekt
        case .ukol: .ukol
        }
    }
}

/// Filtr pro akci „Nejbližší zkouška“ – konkrétní typ, nebo všechny povinnosti.
nonisolated enum DeadlineFilter: String, AppEnum {
    case vse
    case zkouska
    case zapocet
    case projekt
    case ukol

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Typ termínu"

    static let caseDisplayRepresentations: [DeadlineFilter: DisplayRepresentation] = [
        .vse: "Vše",
        .zkouska: "Zkouška",
        .zapocet: "Zápočet",
        .projekt: "Projekt",
        .ukol: "Úkol"
    ]

    /// Odpovídající typ úkolu; nil = bez omezení
    @MainActor
    var taskType: TaskType? {
        switch self {
        case .vse: nil
        case .zkouska: .zkouska
        case .zapocet: .zapocet
        case .projekt: .projekt
        case .ukol: .ukol
        }
    }

    /// Začátek odpovědi, např. „Nejbližší zkouška“
    var headline: String {
        switch self {
        case .vse: String(localized: "Nejbližší termín")
        case .zkouska: String(localized: "Nejbližší zkouška")
        case .zapocet: String(localized: "Nejbližší zápočet")
        case .projekt: String(localized: "Nejbližší projekt")
        case .ukol: String(localized: "Nejbližší úkol")
        }
    }

    /// Odpověď, když nic nenajdeme
    var emptyText: String {
        switch self {
        case .vse: String(localized: "Žádný nadcházející termín – máš hotovo.")
        case .zkouska: String(localized: "Žádná nadcházející zkouška.")
        case .zapocet: String(localized: "Žádný nadcházející zápočet.")
        case .projekt: String(localized: "Žádný nadcházející projekt.")
        case .ukol: String(localized: "Žádný nadcházející úkol.")
        }
    }
}

// MARK: - Předmět jako entita

/// Předmět, jak ho vidí Siri a Zkratky. Nese jen hodnoty (ne SwiftData model), aby byl `Sendable`.
nonisolated struct SubjectEntity: AppEntity {
    let id: UUID
    let code: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Předmět"
    static let defaultQuery = SubjectQuery()

    /// „AP9PT – Pokročilé mobilní technologie“
    var displayTitle: String {
        code.isEmpty ? name : "\(code) – \(name)"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayTitle)")
    }
}

/// Dotaz, kterým systém dohledává předměty (podle id, nabídka všech, hledání textem).
nonisolated struct SubjectQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [SubjectEntity.ID]) async throws -> [SubjectEntity] {
        IntentStore.subjectEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SubjectEntity] {
        IntentStore.subjectEntities()
    }

    @MainActor
    func entities(matching string: String) async throws -> [SubjectEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjects = IntentStore.subjectEntities()
        guard !query.isEmpty else { return subjects }
        return subjects.filter {
            $0.name.localizedStandardContains(query) || $0.code.localizedStandardContains(query)
        }
    }
}

// MARK: - Chyby

nonisolated enum TerminovnikIntentError: Error, CustomLocalizedStringResourceConvertible {
    case subjectNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .subjectNotFound: "Předmět se nepodařilo najít – možná byl mezitím smazán."
        }
    }
}

// MARK: - Přístup k datům (MainActor)

/// Čtení a zápis SwiftData pro akce. Používá sdílený kontejner, takže změny hned vidí i otevřené UI.
enum IntentStore {
    static var context: ModelContext { PersistenceController.shared.mainContext }

    /// Všechny předměty seřazené podle názvu (abeceda jazyka aplikace)
    static func subjectEntities() -> [SubjectEntity] {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        return subjects
            .map { SubjectEntity(id: $0.id, code: $0.code, name: $0.name) }
            .sorted { $0.name.compare($1.name, locale: .app) == .orderedAscending }
    }

    static func subject(id: UUID) -> Subject? {
        var descriptor = FetchDescriptor<Subject>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Nesplněné úkoly s termínem v budoucnosti, od nejbližšího
    static func upcomingTasks(after now: Date = .now) -> [ExamTask] {
        let descriptor = FetchDescriptor<ExamTask>(
            predicate: #Predicate { !$0.isCompleted && $0.dueDate >= now },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - Texty odpovědí (MainActor)

/// Lokalizované texty odpovědí pro intenty.
enum IntentText {
    static var timetableNotLoaded: String {
        String(localized: "Rozvrh zatím není načtený – otevři Termínovník a přihlas se do STAGu.")
    }

    /// „10:00“
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(.app))
    }

    /// „v 10:00“ / „ve 12:00“ – předložka podle výslovnosti hodiny (anglicky vždy „at 10:00“)
    static func atTime(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let clock = time(date)
        // „ve dvě“, „ve dvanáct“, „ve dvacet“… – ostatní hodiny s „v“
        if [2, 3, 4, 12, 13, 14, 20, 21, 22, 23].contains(hour) {
            return String(localized: "ve \(clock)", comment: "Čas do věty, např. „ve 12:00“ (anglicky „at 12:00“)")
        }
        return String(localized: "v \(clock)", comment: "Čas do věty, např. „v 10:00“ (anglicky „at 10:00“)")
    }

    /// „út 6. 10.“
    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.defaultDigits).locale(.app))
    }

    /// „dnes“, „zítra“, „pozítří“, jinak „ve středu 14. 10.“
    static func dayPhrase(_ date: Date) -> String {
        switch date.calendarDays() {
        case 0: return String(localized: "dnes")
        case 1: return String(localized: "zítra")
        case 2: return String(localized: "pozítří")
        default:
            let dayMonth = date.formatted(.dateTime.day().month(.defaultDigits).locale(.app))
            switch TimetableEvent.weekday(of: date) { // 1 = pondělí
            case 1: return String(localized: "v pondělí \(dayMonth)")
            case 2: return String(localized: "v úterý \(dayMonth)")
            case 3: return String(localized: "ve středu \(dayMonth)")
            case 4: return String(localized: "ve čtvrtek \(dayMonth)")
            case 5: return String(localized: "v pátek \(dayMonth)")
            case 6: return String(localized: "v sobotu \(dayMonth)")
            default: return String(localized: "v neděli \(dayMonth)")
            }
        }
    }

    /// „Za 5 dní“ → „za 5 dní“ (do věty)
    static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}
