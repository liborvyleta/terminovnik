import Foundation
import SwiftData
import WidgetKit

/// Zapisuje nejbližší deadliny pro widget a hodinky.
///
/// Zapíše nejbližší nesplněné deadliny do sdíleného úložiště (App Group) a požádá widget o překreslení.
/// Volá se automaticky z `TaskService.save` po každé změně dat a při spuštění aplikace.
/// Stejný ``WidgetSnapshot`` pak ``WatchSync`` posílá na Apple Watch.
enum WidgetSync {
    /// Kolik deadlinů widget dostane (největší widget jich zobrazí méně)
    static let limit = 12

    /// Načte nejbližších ``limit`` nesplněných úkolů, uloží je jako ``WidgetSnapshot``,
    /// obnoví časové osy widgetů a odešle data hodinkám.
    /// - Parameter context: kontext SwiftData, ze kterého se úkoly čtou
    /// - Note: V ukázkovém režimu se nic nezapisuje – widget i hodinky dál ukazují skutečná data.
    static func refresh(from context: ModelContext) {
        // Ukázkový režim: widget i hodinky dál ukazují skutečná data
        guard !DemoMode.isActive else { return }
        var descriptor = FetchDescriptor<ExamTask>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        descriptor.fetchLimit = limit
        let tasks = (try? context.fetch(descriptor)) ?? []

        let deadlines = tasks.map { task in
            WidgetDeadline(
                id: task.id,
                title: task.title,
                subjectCode: task.subject?.code ?? "",
                subjectName: task.subject?.name ?? "",
                hexColor: task.subject?.hexColor ?? "#687076",
                typeTitle: task.taskType.title,
                typeSymbol: task.taskType.symbol,
                dueDate: task.dueDate
            )
        }
        WidgetSnapshot(deadlines: deadlines, generatedAt: .now).save()
        WidgetCenter.shared.reloadAllTimelines()
        // Stejná data dostanou i hodinky
        WatchSync.shared.push()
    }
}
