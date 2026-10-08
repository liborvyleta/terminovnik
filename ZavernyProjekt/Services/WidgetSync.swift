import Foundation
import SwiftData
import WidgetKit

/// Zapíše nejbližší nesplněné deadliny do sdíleného úložiště (App Group) a požádá widget o překreslení.
/// Volá se automaticky z `TaskService.save` po každé změně dat a při spuštění aplikace.
enum WidgetSync {
    /// Kolik deadlinů widget dostane (největší widget jich zobrazí méně)
    static let limit = 12

    static func refresh(from context: ModelContext) {
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
