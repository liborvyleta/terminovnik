import Foundation
import Observation
import SwiftData

/// Hodnoty segmentového přepínače na Dashboardu
enum DashboardFilter: String, CaseIterable, Identifiable {
    case all = "Vše"
    case upcoming = "Blížící se"
    case completed = "Splněné"

    var id: Self { self }

    /// Název segmentu zobrazovaný v UI
    var title: String {
        switch self {
        case .all: String(localized: "Vše")
        case .upcoming: String(localized: "Blížící se")
        case .completed: String(localized: "Splněné")
        }
    }
}

/// Jedna sekce seznamu (např. „Dnes a zítra“)
struct TaskSection: Identifiable {
    let id: String
    let title: String
    let tasks: [ExamTask]
}

/// Čísla pro souhrnné kartičky nahoře
struct DashboardStats {
    var active = 0
    var thisWeek = 0
    var overdue = 0
}

/// ViewModel hlavního přehledu.
///
/// MVVM se SwiftData: `@Query` musí žít ve View (jen tam se automaticky aktualizuje),
/// proto View předává načtená data sem a ViewModel řeší filtrování, vyhledávání,
/// seskupení a akce. Logika je tak oddělená od UI a snadno testovatelná.
@Observable
final class DashboardViewModel {
    /// Text z vyhledávacího pole (.searchable)
    var searchText = ""
    /// Zvolený segment – výchozí jsou nadcházející nesplněné deadliny
    var filter: DashboardFilter = .upcoming
    /// Zvýší se při každém splnění – View na změnu reaguje haptickou odezvou
    private(set) var completionFeedback = 0

    var isSearching: Bool { !trimmedQuery.isEmpty }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Data pro View

    /// Vrátí sekce k zobrazení podle filtru a vyhledávání.
    func sections(from tasks: [ExamTask], now: Date = .now) -> [TaskSection] {
        let matching = tasks.filter(matchesSearch)
        // Aktivní od nejbližšího termínu, splněné od nejpozdějšího termínu
        let active = matching.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
        let completed = matching.filter(\.isCompleted).sorted { $0.dueDate > $1.dueDate }

        let completedSection = completed.isEmpty
            ? []
            : [TaskSection(id: "completed", title: String(localized: "Splněné"), tasks: completed)]

        switch filter {
        case .all: return groupByUrgency(active, now: now) + completedSection
        case .upcoming: return groupByUrgency(active, now: now)
        case .completed: return completedSection
        }
    }

    /// Spočítá souhrnná čísla pro kartičky (počítá se ze všech úkolů, ne z vyhledávání).
    func stats(from tasks: [ExamTask], now: Date = .now) -> DashboardStats {
        var stats = DashboardStats()
        for task in tasks where !task.isCompleted {
            stats.active += 1
            if task.dueDate < now {
                stats.overdue += 1
            } else if task.dueDate.calendarDays(from: now) <= 7 {
                stats.thisWeek += 1
            }
        }
        return stats
    }

    // MARK: - Akce

    func toggleCompletion(_ task: ExamTask) {
        TaskService.toggleCompletion(task)
        if task.isCompleted { completionFeedback += 1 }
    }

    func delete(_ task: ExamTask, in context: ModelContext) {
        TaskService.delete(task, in: context)
    }

    // MARK: - Pomocné funkce

    /// Hledá v názvu, předmětu (název i kód), typu a poznámce. Ignoruje velikost písmen i diakritiku.
    private func matchesSearch(_ task: ExamTask) -> Bool {
        let query = trimmedQuery
        guard !query.isEmpty else { return true }
        let fields = [
            task.title,
            task.subject?.name ?? "",
            task.subject?.code ?? "",
            task.taskType.title,
            task.note
        ]
        return fields.contains { $0.localizedStandardContains(query) }
    }

    /// Rozdělí aktivní úkoly do časových skupin; prázdné skupiny vynechá.
    private func groupByUrgency(_ tasks: [ExamTask], now: Date) -> [TaskSection] {
        var overdue: [ExamTask] = []
        var soon: [ExamTask] = []
        var week: [ExamTask] = []
        var later: [ExamTask] = []

        for task in tasks {
            if task.dueDate < now {
                overdue.append(task)
                continue
            }
            switch task.dueDate.calendarDays(from: now) {
            case ...1: soon.append(task)
            case 2...7: week.append(task)
            default: later.append(task)
            }
        }

        return [
            TaskSection(id: "overdue", title: String(localized: "Po termínu"), tasks: overdue),
            TaskSection(id: "soon", title: String(localized: "Dnes a zítra"), tasks: soon),
            TaskSection(id: "week", title: String(localized: "Příštích 7 dní"), tasks: week),
            TaskSection(id: "later", title: String(localized: "Později"), tasks: later)
        ].filter { !$0.tasks.isEmpty }
    }
}
