import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// ViewModel obrazovky Nastavení.
///
/// Drží stav povolení oznámení (z `UNUserNotificationCenter`), reaguje na přepínače připomínek výuky, upozornění na termíny a známky a Live Activity (`ClassReminderScheduler`, `LiveActivityManager`), maže všechna data aplikace včetně dat ze STAGu (`TimetableStore`, `ExamTermStore`, `GradeStore`) a poskytuje informace o jazyce a verzi aplikace. Používá ho obrazovka Nastavení.
@Observable
final class SettingsViewModel {
    /// Zjednodušený stav povolení notifikací pro zobrazení v UI.
    ///
    /// Převádí systémový `UNAuthorizationStatus` na čtyři stavy s textem, ikonou a barvou pro řádek v Nastavení.
    enum NotificationPermission {
        case unknown        // stav se ještě načítá
        case notDetermined  // uživatel se zatím nerozhodl
        case authorized
        case denied

        /// Převede systémový stav autorizace; dočasná i provizorní povolení se berou jako povoleno.
        /// - Parameter status: Stav autorizace notifikací ze systému.
        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .denied: self = .denied
            case .authorized, .provisional, .ephemeral: self = .authorized
            @unknown default: self = .unknown
            }
        }

        /// Lokalizovaný popis stavu.
        var title: String {
            switch self {
            case .unknown: String(localized: "Zjišťuji…")
            case .notDetermined: String(localized: "Zatím nerozhodnuto")
            case .authorized: String(localized: "Povoleno")
            case .denied: String(localized: "Zakázáno")
            }
        }

        /// Název SF Symbolu pro stav.
        var systemImage: String {
            switch self {
            case .unknown: "ellipsis.circle"
            case .notDetermined: "questionmark.circle.fill"
            case .authorized: "checkmark.circle.fill"
            case .denied: "xmark.circle.fill"
            }
        }

        /// Barva ikony stavu.
        var tint: Color {
            switch self {
            case .unknown: .secondary
            case .notDetermined: .orange
            case .authorized: .green
            case .denied: .red
            }
        }
    }

    /// Aktuální stav povolení oznámení; obnovuje ho ``refreshNotificationStatus()``.
    var notificationPermission: NotificationPermission = .unknown
    /// Zda se zobrazuje potvrzení smazání všech dat.
    var isConfirmingDeleteAll = false

    /// Odkaz do systémového Nastavení přímo na oznámení této aplikace.
    let notificationSettingsURL = URL(string: UIApplication.openNotificationSettingsURLString)

    /// Odkaz do systémového Nastavení této aplikace – tam iOS nabízí volbu jazyka aplikace.
    let appSettingsURL = URL(string: UIApplication.openSettingsURLString)

    /// Název aktuálního jazyka aplikace („Čeština“ / „English“) – vždy v daném jazyce.
    var appLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "cs"
        return code.hasPrefix("en") ? "English" : "Čeština"
    }

    /// Verze aplikace z Info.plist, např. „1.0 (1)“.
    var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    // MARK: - Oznámení

    /// Načte aktuální stav povolení ze systému (volá se při zobrazení a návratu do popředí).
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = NotificationPermission(settings.authorizationStatus)
    }

    /// Zobrazí systémový dialog s žádostí o povolení a poté obnoví stav.
    func requestNotifications() async {
        await NotificationManager.shared.requestAuthorization()
        await refreshNotificationStatus()
    }

    // MARK: - Výuka

    /// Zapnutí / vypnutí připomínek hodin.
    ///
    /// Při zapnutí si případně (dosud nerozhodnuto) vyžádá povolení oznámení, pak připomínky hned přeplánuje.
    /// - Parameter enabled: Nový stav přepínače.
    func classRemindersChanged(enabled: Bool) async {
        if enabled, notificationPermission == .notDetermined {
            await requestNotifications()
        }
        ClassReminderScheduler.shared.reschedule()
    }

    /// Zapnutí upozornění na nové termíny – bez povolených oznámení by nepřišla, tak o ně rovnou požádáme.
    /// - Parameter enabled: Nový stav přepínače.
    func examTermAlertsChanged(enabled: Bool) async {
        if enabled, notificationPermission == .notDetermined {
            await requestNotifications()
        }
    }

    /// Zapnutí upozornění na nové známky – stejně jako u termínů rovnou požádáme o povolení oznámení.
    /// - Parameter enabled: Nový stav přepínače.
    func gradeAlertsChanged(enabled: Bool) async {
        await examTermAlertsChanged(enabled: enabled)
    }

    /// Změna předstihu připomínky – stará oznámení se nahradí novými.
    func classReminderLeadChanged() {
        ClassReminderScheduler.shared.reschedule()
    }

    /// Zapnutí / vypnutí Live Activity – hned ji spustí, nebo ukončí.
    func lessonLiveActivityChanged() {
        LiveActivityManager.shared.updateLessonActivity()
    }

    // MARK: - Data

    /// Smaže všechna data aplikace.
    ///
    /// Předměty, deadliny, připomínky deadlinů, uložený rozvrh, termíny zkoušek a známky. Mimo ukázkový režim navíc zruší připomínky hodin, ukončí Live Activity, odstraní doručená oznámení a obnoví widgety. Úkoly předmětů smaže SwiftData kaskádou, úkoly bez předmětu mažeme ručně.
    /// - Parameters:
    ///   - context: SwiftData kontext, ze kterého se data mažou.
    ///   - signOut: `true` = navíc odhlásí účet STAG (smaže přístupový klíč a údaje o účtu).
    func deleteAllData(in context: ModelContext, signOut: Bool = false) {
        do {
            let tasks = try context.fetch(FetchDescriptor<ExamTask>())
            let subjects = try context.fetch(FetchDescriptor<Subject>())

            for task in tasks {
                NotificationManager.shared.cancelReminder(for: task)
            }
            for task in tasks where task.subject == nil {
                context.delete(task)
            }
            for subject in subjects {
                context.delete(subject)
            }
        } catch {
            print("⚠️ Načtení dat ke smazání selhalo: \(error.localizedDescription)")
        }
        // Uloží změny a přepíše data widgetu (prázdný seznam deadlinů)
        TaskService.save(context)

        // Data ze STAGu uložená v App Group (čte je i widget „Další hodina“).
        // V ukázkovém režimu se mažou jen demo data v paměti.
        TimetableStore.shared.clear()
        ExamTermStore.shared.clear()
        GradeStore.shared.clear()
        if DemoMode.isActive {
            if signOut { StagAccountStore.shared.signOut() }
            return
        }
        ClassReminderScheduler.shared.cancelAll()
        LiveActivityManager.shared.endAll()
        // Doručená oznámení (deadliny, hodiny, nové termíny) by po smazání jen mátla
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        if signOut {
            StagAccountStore.shared.signOut()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
