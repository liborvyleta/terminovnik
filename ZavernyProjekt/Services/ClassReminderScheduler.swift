import Foundation
import UserNotifications

/// Připomínky výuky: oznámení pár minut před začátkem každé hodiny z rozvrhu STAGu.
///
/// Plánuje se jen na příštích 7 dní (iOS drží nejvýše 64 čekajících oznámení celkem
/// a část z nich patří připomínkám deadlinů). Proto se plán obnovuje po každém načtení
/// rozvrhu, při návratu aplikace do popředí a při změně nastavení.
/// Oznámení mají identifikátory `class-…`, takže se nepletou s připomínkami deadlinů (`deadline-…`).
@MainActor
final class ClassReminderScheduler {
    static let shared = ClassReminderScheduler()

    // MARK: - Nastavení (klíče v UserDefaults sdílené s Nastavením)

    /// Zapnuté připomínky výuky (výchozí true)
    nonisolated static let enabledKey = "classRemindersEnabled"
    /// Předstih připomínky v minutách (výchozí 15)
    nonisolated static let leadMinutesKey = "classReminderLeadMinutes"
    nonisolated static let defaultLeadMinutes = 15
    /// Nabízené předstihy v Nastavení
    nonisolated static let leadMinuteOptions = [5, 10, 15, 30]
    /// Prefix identifikátorů oznámení výuky
    nonisolated static let identifierPrefix = "class-"

    /// Nejvýše tolik připomínek výuky najednou
    private let maxReminders = 40
    /// Systémový limit čekajících oznámení na aplikaci
    private let systemLimit = 64
    /// Kolik dní dopředu plánujeme
    private let daysAhead = 7

    private let center = UNUserNotificationCenter.current()
    /// Poslední naplánovaná práce – volání jdou za sebou, aby se plány nepřekrývaly
    private var currentWork: Task<Void, Never>?

    private init() {}

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var leadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: leadMinutesKey)
        return value > 0 ? value : defaultLeadMinutes
    }

    // MARK: - Veřejné API

    /// Zruší čekající připomínky výuky a podle nastavení a aktuálního rozvrhu je naplánuje znovu.
    func reschedule() {
        enqueue { scheduler in
            await scheduler.performReschedule()
        }
    }

    /// Zruší všechny čekající připomínky výuky (např. po odhlášení ze STAGu).
    func cancelAll() {
        enqueue { scheduler in
            _ = await scheduler.removePendingClassReminders()
        }
    }

    // MARK: - Plánování

    /// Předchozí rozběhnutou práci zruší, počká na její doběhnutí a pak spustí novou.
    private func enqueue(_ work: @escaping @MainActor (ClassReminderScheduler) async -> Void) {
        let previous = currentWork
        previous?.cancel()
        currentWork = Task {
            await previous?.value
            await work(self)
        }
    }

    private func performReschedule() async {
        let otherPendingCount = await removePendingClassReminders()
        guard !Task.isCancelled, Self.isEnabled else { return }

        // Bez povolení oznámení nemá smysl nic plánovat
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }

        guard let snapshot = TimetableStore.shared.snapshot, !snapshot.events.isEmpty else { return }

        let now = Date.now
        let lead = Self.leadMinutes
        let horizon = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        // Místo nechá i připomínkám deadlinů, aby se nepřekročil limit iOS
        let budget = max(0, min(maxReminders, systemLimit - otherPendingCount))

        let reminders = snapshot.upcoming(after: now, limit: 500, daysAhead: daysAhead)
            .filter { $0.start <= horizon }
            .compactMap { occurrence -> (TimetableOccurrence, Date)? in
                guard let fireDate = Calendar.current.date(byAdding: .minute, value: -lead, to: occurrence.start),
                      fireDate > now else { return nil }
                return (occurrence, fireDate)
            }
            .prefix(budget)

        for (occurrence, fireDate) in reminders {
            guard !Task.isCancelled else { return }
            let request = makeRequest(for: occurrence, fireDate: fireDate, leadMinutes: lead)
            do {
                try await center.add(request)
            } catch {
                print("⚠️ Připomínku hodiny se nepodařilo naplánovat: \(error.localizedDescription)")
            }
        }
    }

    /// Odstraní čekající oznámení s prefixem `class-` a vrátí počet ostatních čekajících oznámení.
    @discardableResult
    private func removePendingClassReminders() async -> Int {
        let pending = await center.pendingNotificationRequests()
        let classIDs = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        if !classIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: classIDs)
        }
        return pending.count - classIDs.count
    }

    private func makeRequest(for occurrence: TimetableOccurrence, fireDate: Date, leadMinutes: Int) -> UNNotificationRequest {
        let event = occurrence.event

        let content = UNMutableNotificationContent()
        // „Za 15 min: AP9PT · 52/202“
        let place = event.locationText.map { " · \($0)" } ?? ""
        content.title = "Za \(leadMinutes) min: \(event.subjectCode)\(place)"
        content.subtitle = event.subjectName
        // „Cvičení · 10:00–12:00 · Ing. …“
        let timeStyle = Date.FormatStyle.dateTime.hour().minute().locale(.czech)
        let timeRange = "\(occurrence.start.formatted(timeStyle))–\(occurrence.end.formatted(timeStyle))"
        let teacher = event.teacher?.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = [event.typeName, timeRange, teacher]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = "class-reminders"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: Self.identifierPrefix + occurrence.id, content: content, trigger: trigger)
    }
}
