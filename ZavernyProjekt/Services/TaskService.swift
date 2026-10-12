import Foundation
import SwiftData

/// Sdílené operace nad daty. Používají je ViewModely Dashboardu, seznamu i detailu předmětu,
/// takže logika „změna dat + synchronizace notifikací“ je na jednom místě.
///
/// Pracuje s modely SwiftData (``ExamTask``, ``Subject``), připomínky řídí `NotificationManager`
/// a po každém uložení obnoví widget přes ``WidgetSync/refresh(from:)``.
enum TaskService {
    /// Přepne stav splnění a podle něj zruší nebo obnoví připomínku.
    ///
    /// Pokud úkol patří do kontextu, změnu hned uloží.
    /// - Parameter task: přepínaný úkol
    static func toggleCompletion(_ task: ExamTask) {
        task.isCompleted.toggle()
        NotificationManager.shared.updateReminder(for: task)
        if let context = task.modelContext { save(context) }
    }

    /// Smaže úkol včetně jeho naplánované notifikace.
    /// - Parameters:
    ///   - task: mazaný úkol
    ///   - context: kontext, ze kterého se úkol smaže a který se uloží
    static func delete(_ task: ExamTask, in context: ModelContext) {
        NotificationManager.shared.cancelReminder(for: task)
        context.delete(task)
        save(context)
    }

    /// Smaže předmět. Úkoly smaže SwiftData sama (cascade), notifikace zrušíme ručně.
    /// - Parameters:
    ///   - subject: mazaný předmět
    ///   - context: kontext, ze kterého se předmět smaže a který se uloží
    static func delete(_ subject: Subject, in context: ModelContext) {
        for task in subject.taskList {
            NotificationManager.shared.cancelReminder(for: task)
        }
        context.delete(subject)
        save(context)
    }

    /// Explicitní uložení. SwiftData ukládá i automaticky, ale takhle máme jistotu okamžitého zápisu.
    /// Po uložení se aktualizuje i widget.
    ///
    /// Před uložením orazítkuje změněné záznamy (``stampChanges(in:now:)``); chyba uložení se jen vypíše.
    /// - Parameter context: ukládaný kontext
    static func save(_ context: ModelContext) {
        stampChanges(in: context)
        do {
            try context.save()
        } catch {
            print("⚠️ Uložení dat selhalo: \(error.localizedDescription)")
        }
        WidgetSync.refresh(from: context)
    }

    /// Upravené záznamy dostanou aktuální `updatedAt` – podle něj se při obnově zálohy pozná novější verze.
    /// - Parameters:
    ///   - context: kontext, jehož změněné modely se orazítkují
    ///   - now: časové razítko (výchozí aktuální čas, pro testy lze předat)
    static func stampChanges(in context: ModelContext, now: Date = .now) {
        for model in context.changedModelsArray {
            if let task = model as? ExamTask { task.updatedAt = now }
            if let subject = model as? Subject { subject.updatedAt = now }
        }
    }
}
