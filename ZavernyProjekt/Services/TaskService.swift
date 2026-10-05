import Foundation
import SwiftData

/// Sdílené operace nad daty. Používají je ViewModely Dashboardu, seznamu i detailu předmětu,
/// takže logika „změna dat + synchronizace notifikací“ je na jednom místě.
enum TaskService {
    /// Přepne stav splnění a podle něj zruší nebo obnoví připomínku.
    static func toggleCompletion(_ task: ExamTask) {
        task.isCompleted.toggle()
        NotificationManager.shared.updateReminder(for: task)
        if let context = task.modelContext { save(context) }
    }

    /// Smaže úkol včetně jeho naplánované notifikace.
    static func delete(_ task: ExamTask, in context: ModelContext) {
        NotificationManager.shared.cancelReminder(for: task)
        context.delete(task)
        save(context)
    }

    /// Smaže předmět. Úkoly smaže SwiftData sama (cascade), notifikace zrušíme ručně.
    static func delete(_ subject: Subject, in context: ModelContext) {
        for task in subject.tasks {
            NotificationManager.shared.cancelReminder(for: task)
        }
        context.delete(subject)
        save(context)
    }

    /// Explicitní uložení. SwiftData ukládá i automaticky, ale takhle máme jistotu okamžitého zápisu.
    /// Po uložení se aktualizuje i widget.
    static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("⚠️ Uložení dat selhalo: \(error.localizedDescription)")
        }
        WidgetSync.refresh(from: context)
    }
}
