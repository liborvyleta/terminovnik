import Foundation
import SwiftData
import UserNotifications

/// Správa lokálních notifikací.
///
/// Ke každému nesplněnému deadlinu (`ExamTask`) naplánuje připomínku přesně 1 den před termínem.
/// Připomínka nese akci „Splněno“, kterou jde úkol odškrtnout přímo z oznámení (zápis
/// do SwiftData přes uložený `ModelContainer`). Dále okamžitě oznamuje změny rozvrhu
/// zjištěné ``TimetableChangeDetector``. Používají ho obrazovky úkolů, start aplikace
/// a ``ForegroundNotificationDelegate``.
final class NotificationManager {
    /// Sdílená instance používaná celou aplikací.
    static let shared = NotificationManager()

    /// Kategorie připomínky deadlinu – určuje, jaká tlačítka oznámení nabídne.
    nonisolated static let deadlineCategoryID = "DEADLINE_REMINDER"
    /// Akce „Splněno“ v oznámení.
    nonisolated static let markDoneActionID = "MARK_DONE"
    /// Klíč v `userInfo`, pod kterým je uložené UUID úkolu (jako String).
    nonisolated static let taskIDKey = "taskID"
    /// Kategorie oznámení o změně rozvrhu
    nonisolated static let timetableChangeCategoryID = "TIMETABLE_CHANGE"
    /// Klíč v `userInfo` se záložkou, která se po klepnutí otevře (hodnota pro `@AppStorage("selectedTab")`)
    nonisolated static let openTabKey = "openTab"
    /// Otisk naposledy oznámených změn rozvrhu (klíč v App Group).
    private static let lastTimetableChangesKey = "timetableChanges.lastFingerprint"

    /// Systémové centrum notifikací.
    private let center = UNUserNotificationCenter.current()
    /// Delegát držený silně – `UNUserNotificationCenter.delegate` je slabý odkaz.
    private let notificationDelegate = ForegroundNotificationDelegate()

    /// Kontejner SwiftData – potřebujeme ho, abychom akci z oznámení zapsali do databáze
    /// i ve chvíli, kdy systém aplikaci spustí jen na pozadí.
    private var modelContainer: ModelContainer?

    /// Soukromý init – používá se jen ``shared``.
    private init() {}

    /// Volá se při startu aplikace: uloží kontejner, nastaví delegáta (banner i v popředí,
    /// zpracování akcí z oznámení) a zaregistruje kategorii s tlačítkem „Splněno“
    /// a kategorii oznámení o změně rozvrhu.
    /// - Parameter modelContainer: Kontejner SwiftData pro zápis akcí z oznámení.
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        center.delegate = notificationDelegate

        // Bez volby .foreground → akce se vyřídí na pozadí a aplikace se neotevře.
        // .authenticationRequired → na zamčeném zařízení akci nejde provést bez odemčení.
        let markDone = UNNotificationAction(
            identifier: Self.markDoneActionID,
            title: String(localized: "Splněno", comment: "Tlačítko v oznámení: označit deadline jako splněný"),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
        )
        let category = UNNotificationCategory(
            identifier: Self.deadlineCategoryID,
            actions: [markDone],
            intentIdentifiers: [],
            options: []
        )
        let timetableCategory = UNNotificationCategory(
            identifier: Self.timetableChangeCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, timetableCategory])
    }

    /// Asynchronně požádá uživatele o povolení notifikací. Systémový dialog se ukáže jen poprvé,
    /// další volání rovnou vrátí uložený stav. Volá se v kontextu (při uložení deadlinu),
    /// ne hned po spuštění – uživatel tak ví, proč aplikace notifikace chce.
    /// - Returns: `true`, pokud jsou notifikace povolené; `false` při zamítnutí nebo chybě.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("⚠️ Žádost o notifikace selhala: \(error.localizedDescription)")
            return false
        }
    }

    /// Asynchronně požádá o povolení, jen pokud o něm uživatel ještě nerozhodl (systémový dialog jinak nic neudělá).
    /// Volá se po přihlášení do STAGu – připomínky zkoušek, hodin a nových termínů bez povolení nefungují.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        await requestAuthorization()
    }

    /// Okamžik připomínky = termín mínus 1 kalendářní den (ve stejný čas).
    /// - Parameter dueDate: Termín deadlinu.
    /// - Returns: Datum připomínky, nebo nil, pokud ho kalendář nedokáže spočítat.
    static func reminderDate(for dueDate: Date) -> Date? {
        Calendar.current.date(byAdding: .day, value: -1, to: dueDate)
    }

    /// Naplánuje (nebo přeplánuje) připomínku pro úkol.
    /// Volá se po vytvoření, úpravě i odškrtnutí – vždy nejdřív zruší starou notifikaci.
    /// - Parameter task: Úkol, jehož připomínka se má aktualizovat.
    func updateReminder(for task: ExamTask) {
        // Ukázkový režim: žádné skutečné připomínky se neplánují ani neruší
        guard !DemoMode.isActive else { return }
        cancelReminder(for: task)
        scheduleRequest(for: task)
    }

    /// Přeplánuje připomínky všech nesplněných úkolů (volá se při startu).
    /// Díky tomu dostanou tlačítko „Splněno“ i připomínky naplánované starší verzí aplikace.
    /// Čekající požadavky se nahradí; už doručená oznámení v Centru oznámení zůstanou.
    /// - Parameter context: Kontext SwiftData, ze kterého se načtou nesplněné úkoly.
    func rescheduleAll(in context: ModelContext) {
        guard !DemoMode.isActive else { return }
        let descriptor = FetchDescriptor<ExamTask>(predicate: #Predicate { !$0.isCompleted })
        let tasks = (try? context.fetch(descriptor)) ?? []

        center.removePendingNotificationRequests(withIdentifiers: tasks.map(\.notificationID))
        for task in tasks {
            scheduleRequest(for: task)
        }
    }

    /// Zruší čekající i již doručenou připomínku úkolu.
    /// - Parameter task: Úkol, jehož připomínka se ruší.
    func cancelReminder(for task: ExamTask) {
        guard !DemoMode.isActive else { return }
        center.removePendingNotificationRequests(withIdentifiers: [task.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [task.notificationID])
    }

    /// Označí úkol jako splněný na základě akce „Splněno“ z oznámení.
    /// Přijímá jen String (Sendable), samotný model se načte až tady na MainActoru.
    /// Neexistující nebo již splněný úkol ignoruje.
    /// - Parameter taskID: UUID úkolu jako text z `userInfo` oznámení.
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

    /// Asynchronně a okamžitě oznámí změny rozvrhu (zrušené / přesunuté / nové hodiny).
    /// Víc změn → jedno souhrnné oznámení. Stejnou sadu změn neoznamuje dvakrát
    /// (porovnává otisk z ``TimetableChangeDetector/fingerprint(of:)``). Respektuje přepínač
    /// v Nastavení a ukázkový režim.
    /// - Parameter changes: Změny zjištěné ``TimetableChangeDetector/diff(old:new:now:calendar:horizonDays:)``.
    func notifyTimetableChanges(_ changes: [TimetableChange]) async {
        guard !DemoMode.isActive else { return }
        let enabled = UserDefaults.standard.object(forKey: TimetableStore.changeAlertsEnabledKey) as? Bool ?? true
        guard enabled, !changes.isEmpty else { return }
        let fingerprint = TimetableChangeDetector.fingerprint(of: changes)
        guard AppGroup.defaults?.string(forKey: Self.lastTimetableChangesKey) != fingerprint else { return }
        AppGroup.defaults?.set(fingerprint, forKey: Self.lastTimetableChangesKey)

        let text = TimetableChangeDetector.notificationText(for: changes)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = Self.timetableChangeCategoryID
        content.threadIdentifier = "timetable-change"
        content.userInfo = [Self.openTabKey: "timetable"]
        let request = UNNotificationRequest(identifier: "timetable-change-\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }

    // MARK: - Soukromé

    /// Přidá požadavek na připomínku, pokud dává smysl (nesplněný úkol, čas v budoucnosti).
    /// Požadavek se stejným identifikátorem systém nahradí.
    /// - Parameter task: Úkol, pro který se připomínka plánuje.
    private func scheduleRequest(for task: ExamTask) {
        guard !DemoMode.isActive else { return }
        // Splněné úkoly a termíny, kde by připomínka byla v minulosti, přeskočíme.
        guard !task.isCompleted,
              let fireDate = Self.reminderDate(for: task.dueDate),
              fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Zítra: \(task.taskType.title)", comment: "Nadpis připomínky deadlinu den předem; typ úkolu")
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

/// Delegát notifikací aplikace.
///
/// - Banner se ukáže, i když je aplikace v popředí.
/// - Akce „Splněno“ z oznámení odškrtne úkol (i když aplikace běží jen na pozadí).
/// - Klepnutí na oznámení s `openTab` přepne záložku.
///
/// Instanci vlastní a registruje ``NotificationManager/configure(modelContainer:)``.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Určí, jak se oznámení zobrazí, když je aplikace v popředí.
    /// - Parameters:
    ///   - center: Centrum notifikací.
    ///   - notification: Doručované oznámení.
    /// - Returns: Banner, záznam v seznamu a zvuk.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Asynchronně zpracuje reakci uživatele na oznámení.
    ///
    /// Klepnutí na oznámení s klíčem ``NotificationManager/openTabKey`` uloží záložku do `selectedTab`;
    /// akce „Splněno“ odškrtne úkol přes ``NotificationManager/markTaskDone(taskID:)``.
    /// - Parameters:
    ///   - center: Centrum notifikací.
    ///   - response: Odpověď uživatele s identifikátorem akce a `userInfo`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Klepnutí na oznámení, které chce otevřít konkrétní záložku (např. změna rozvrhu)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let tab = response.notification.request.content.userInfo[NotificationManager.openTabKey] as? String {
            await MainActor.run {
                UserDefaults.standard.set(tab, forKey: "selectedTab")
            }
            return
        }

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
