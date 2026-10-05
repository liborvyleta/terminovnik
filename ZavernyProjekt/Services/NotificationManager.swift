import Foundation
import SwiftData
import UserNotifications

/// Správa lokálních notifikací.
/// Ke každému nesplněnému deadlinu naplánuje připomínku přesně 1 den před termínem.
/// Připomínka nese akci „Splněno“, kterou jde úkol odškrtnout přímo z oznámení.
final class NotificationManager {
    static let shared = NotificationManager()

    /// Kategorie připomínky deadlinu – určuje, jaká tlačítka oznámení nabídne.
    nonisolated static let deadlineCategoryID = "DEADLINE_REMINDER"
    /// Akce „Splněno“ v oznámení.
    nonisolated static let markDoneActionID = "MARK_DONE"
    /// Klíč v `userInfo`, pod kterým je uložené UUID úkolu (jako String).
    nonisolated static let taskIDKey = "taskID"

    private let center = UNUserNotificationCenter.current()
    private let notificationDelegate = ForegroundNotificationDelegate()

    /// Kontejner SwiftData – potřebujeme ho, abychom akci z oznámení zapsali do databáze
    /// i ve chvíli, kdy systém aplikaci spustí jen na pozadí.
    private var modelContainer: ModelContainer?

    private init() {}

    /// Volá se při startu aplikace: uloží kontejner, nastaví delegáta (banner i v popředí,
    /// zpracování akcí z oznámení) a zaregistruje kategorii s tlačítkem „Splněno“.
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        center.delegate = notificationDelegate

        // Bez volby .foreground → akce se vyřídí na pozadí a aplikace se neotevře.
        let markDone = UNNotificationAction(
            identifier: Self.markDoneActionID,
            title: "Splněno",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
        )
        let category = UNNotificationCategory(
            identifier: Self.deadlineCategoryID,
            actions: [markDone],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Požádá uživatele o povolení notifikací. Systémový dialog se ukáže jen poprvé,
    /// další volání rovnou vrátí uložený stav. Volá se v kontextu (při uložení deadlinu),
    /// ne hned po spuštění – uživatel tak ví, proč aplikace notifikace chce.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("⚠️ Žádost o notifikace selhala: \(error.localizedDescription)")
            return false
        }
    }

    /// Okamžik připomínky = termín mínus 1 kalendářní den (ve stejný čas).
    static func reminderDate(for dueDate: Date) -> Date? {
        Calendar.current.date(byAdding: .day, value: -1, to: dueDate)
    }

    /// Naplánuje (nebo přeplánuje) připomínku pro úkol.
    /// Volá se po vytvoření, úpravě i odškrtnutí – vždy nejdřív zruší starou notifikaci.
    func updateReminder(for task: ExamTask) {
        cancelReminder(for: task)
        scheduleRequest(for: task)
    }

    /// Přeplánuje připomínky všech nesplněných úkolů (volá se při startu).
    /// Díky tomu dostanou tlačítko „Splněno“ i připomínky naplánované starší verzí aplikace.
    /// Čekající požadavky se nahradí; už doručená oznámení v Centru oznámení zůstanou.
    func rescheduleAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<ExamTask>(predicate: #Predicate { !$0.isCompleted })
        let tasks = (try? context.fetch(descriptor)) ?? []

        center.removePendingNotificationRequests(withIdentifiers: tasks.map(\.notificationID))
        for task in tasks {
            scheduleRequest(for: task)
        }
    }

    /// Zruší čekající i již doručenou připomínku úkolu.
    func cancelReminder(for task: ExamTask) {
        center.removePendingNotificationRequests(withIdentifiers: [task.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [task.notificationID])
    }

    /// Označí úkol jako splněný na základě akce „Splněno“ z oznámení.
    /// Přijímá jen String (Sendable), samotný model se načte až tady na MainActoru.
    func markTaskDone(taskID: String) {
        guard let modelContainer, let uuid = UUID(uuidString: taskID) else { return }

        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<ExamTask>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1

        guard let task = try? context.fetch(descriptor).first, !task.isCompleted else { return }

        task.isCompleted = true
        cancelReminder(for: task)
        TaskService.save(context) // uloží a zároveň aktualizuje widget
    }

    // MARK: - Soukromé

    /// Přidá požadavek na připomínku, pokud dává smysl (nesplněný úkol, čas v budoucnosti).
    /// Požadavek se stejným identifikátorem systém nahradí.
    private func scheduleRequest(for task: ExamTask) {
        // Splněné úkoly a termíny, kde by připomínka byla v minulosti, přeskočíme.
        guard !task.isCompleted,
              let fireDate = Self.reminderDate(for: task.dueDate),
              fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zítra: \(task.taskType.title)"
        content.subtitle = task.subject?.name ?? ""
        content.body = "\(task.title) · \(task.dueDate.deadlineFormatted)"
        content.sound = .default
        // Kategorie přidá tlačítko „Splněno“, userInfo nese ID úkolu pro jeho dohledání.
        content.categoryIdentifier = Self.deadlineCategoryID
        content.userInfo = [Self.taskIDKey: task.id.uuidString]

        // Kalendářní trigger – spustí se přesně v daný den, hodinu a minutu.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: task.notificationID,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("⚠️ Notifikaci se nepodařilo naplánovat: \(error.localizedDescription)")
            }
        }
    }
}

/// Delegát notifikací:
/// - banner se ukáže i když je aplikace v popředí,
/// - akce „Splněno“ z oznámení odškrtne úkol (i když aplikace běží jen na pozadí).
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == NotificationManager.markDoneActionID,
              let taskID = response.notification.request.content
                  .userInfo[NotificationManager.taskIDKey] as? String
        else { return }

        // Přes hranici izolace posíláme jen String; práce s modelem proběhne na MainActoru.
        // Metoda vrátí řízení až po uložení – systém do té doby nechá aplikaci běžet.
        await MainActor.run {
            NotificationManager.shared.markTaskDone(taskID: taskID)
        }
    }
}
