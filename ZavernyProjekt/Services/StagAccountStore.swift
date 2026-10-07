import Foundation
import Observation
import UIKit
import UserNotifications
import os

/// Připojený účet IS/STAG (bez ticketu – ten je v Klíčence zvlášť).
nonisolated struct StagAccount: Codable, Equatable {
    /// Jméno a příjmení studenta
    var fullName: String
    /// Osobní číslo studenta (např. A23456)
    var osCislo: String
    /// Uživatelské jméno role studenta – posílá se jako parametr stagUser
    var stagUser: String
    /// Zkratka fakulty (např. FAI)
    var faculty: String?
    /// Kdy se uživatel přihlásil (ticket platí až 90 dní)
    var connectedAt: Date
    /// Kdy se naposledy načetly / aktualizovaly předměty
    var lastSyncAt: Date?
    /// Škola, ke které účet patří (nil = účet z doby před výběrem školy → UTB)
    var school: StagSchool?

    /// Škola účtu – starší uložené účty patří UTB
    var resolvedSchool: StagSchool { school ?? .utb }
}

/// Chyba při ukládání přihlášení
nonisolated enum StagAccountError: LocalizedError {
    /// Ticket nebo účet se nepodařilo zapsat do Klíčenky
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed:
            String(localized: "Přihlášení se nepodařilo bezpečně uložit do Klíčenky. Zkus se přihlásit znovu.")
        }
    }
}

/// Úložiště připojeného účtu IS/STAG.
///
/// Údaje o studentovi (JSON `StagAccount`) i přístupový ticket jsou v Klíčence
/// (`AfterFirstUnlockThisDeviceOnly` – nejdou do záloh ani na jiné zařízení).
/// Díky dlouhodobému ticketu (`longTicket=1`, platí až 90 dní) se uživatel nemusí
/// přihlašovat při každé aktualizaci předmětů. Odhlášením se vše smaže.
///
/// Klíčenka přežije odinstalaci aplikace, UserDefaults ne. Značka instalace v UserDefaults
/// proto rozliší první spuštění po (pře)instalaci, kdy se staré přihlášení zahodí.
@Observable
final class StagAccountStore {
    static let shared = StagAccountStore()

    private(set) var account: StagAccount?

    /// Starší umístění účtu (UserDefaults) – při startu se přesune do Klíčenky
    private let legacyDefaultsKey = "stagAccount.v1"
    /// Značka, že aplikace na tomto zařízení už běžela (po přeinstalaci chybí)
    private let installMarkerKey = "installMarker.v1"
    /// Položky v Klíčence
    private let ticketKey = "stagTicket"
    private let accountKey = "stagAccount"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Terminovnik", category: "stag-account")
    /// Pozorovatelé pro opakované načtení po odemčení (jen po přechodné chybě Klíčenky)
    @ObservationIgnored private var retryObservers: [NSObjectProtocol] = []

    private init() {
        if !load() { scheduleRetry() }
    }

    var isConnected: Bool { account != nil }

    /// Přístupový ticket z Klíčenky (nil = chybí nebo je Klíčenka momentálně nedostupná)
    var ticket: String? { KeychainStore.string(for: ticketKey) }

    /// Uloží účet po úspěšném přihlášení.
    /// - Throws: `StagAccountError.keychainWriteFailed`, pokud se ticket nebo účet nepodařilo uložit
    func connect(_ account: StagAccount, ticket: String) throws {
        guard KeychainStore.set(ticket, for: ticketKey) else {
            throw StagAccountError.keychainWriteFailed
        }
        guard let data = try? JSONEncoder().encode(account), KeychainStore.set(data, for: accountKey) else {
            KeychainStore.remove(ticketKey)
            throw StagAccountError.keychainWriteFailed
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyDefaultsKey)
        defaults.set(true, forKey: installMarkerKey)
        cancelRetry()
        self.account = account
    }

    /// Poznamená čas posledního načtení předmětů
    func markSynced(at date: Date = .now) {
        account?.lastSyncAt = date
        persist()
    }

    /// Odhlášení – smaže ticket, údaje o účtu, načtená data ze STAGu a vše, co by po účtu zůstalo
    /// (Live Activity, doručená oznámení, připomínky hodin, HTTP cache a cookies škol).
    func signOut() {
        let schoolHosts = Self.schoolHosts(including: account?.resolvedSchool)

        KeychainStore.remove(ticketKey)
        KeychainStore.remove(accountKey)
        account = nil
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        cancelRetry()

        TimetableStore.shared.clear()
        ExamTermStore.shared.clear()
        ClassReminderScheduler.shared.cancelAll()
        LiveActivityManager.shared.endAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // STAG už jde přes ephemeral session; uklidíme, co mohla uložit starší verze přes URLSession.shared.
        URLCache.shared.removeAllCachedResponses()
        Self.removeCookies(forHosts: schoolHosts)
    }

    /// Klient STAGu s přihlášením uloženého účtu (nil = nepřipojeno)
    func makeService() -> StagService? {
        guard let account, let ticket else { return nil }
        return StagService(baseURL: account.resolvedSchool.baseURL, ticket: ticket, stagUser: account.stagUser)
    }

    // MARK: - Načtení a migrace

    /// Načte účet z Klíčenky (případně ho přesune z UserDefaults) a po čisté instalaci uklidí
    /// přihlášení, které v Klíčence zůstalo po předchozí instalaci.
    /// - Returns: `false` při přechodné chybě Klíčenky (nic se nesmazalo, zkusí se to znovu)
    @discardableResult
    private func load() -> Bool {
        let defaults = UserDefaults.standard
        do {
            // Nejdřív ověříme, že je Klíčenka dostupná. Před prvním odemčením po restartu není
            // dostupná ani Klíčenka, ani UserDefaults – prázdné UserDefaults pak neznamenají čistou instalaci.
            let hasTicket = try KeychainStore.contains(ticketKey)
            let legacyData = defaults.data(forKey: legacyDefaultsKey)

            if !defaults.bool(forKey: installMarkerKey) {
                defaults.set(true, forKey: installMarkerKey)
                if legacyData == nil {
                    // První spuštění po instalaci (nebo přeinstalaci): staré přihlášení zahodíme.
                    KeychainStore.remove(ticketKey)
                    KeychainStore.remove(accountKey)
                    account = nil
                    return true
                }
                // Starší verze bez značky, ale s uloženým účtem → existující instalace, účet zachováme.
            }

            // Migrace: účet z UserDefaults přesuneme do Klíčenky. Z UserDefaults ho smažeme,
            // až když je bezpečně zapsaný – jinak se o to pokusíme při příštím spuštění.
            var accountData = try KeychainStore.data(for: accountKey)
            if let legacyData {
                if KeychainStore.set(legacyData, for: accountKey) {
                    defaults.removeObject(forKey: legacyDefaultsKey)
                } else {
                    logger.error("Přesun účtu STAG do Klíčenky se nepodařil, zkusí se to příště")
                }
                accountData = legacyData
            }

            guard let accountData else {
                // Bez údajů o účtu není ticket k ničemu
                if hasTicket { KeychainStore.remove(ticketKey) }
                account = nil
                return true
            }
            guard hasTicket, let saved = try? JSONDecoder().decode(StagAccount.self, from: accountData) else {
                // Neúplné nebo poškozené přihlášení – stejně jako dřív ho zahodíme, uživatel se přihlásí znovu
                KeychainStore.remove(ticketKey)
                KeychainStore.remove(accountKey)
                defaults.removeObject(forKey: legacyDefaultsKey)
                account = nil
                return true
            }
            account = saved
            return true
        } catch {
            // Přechodná chyba (typicky zamčené zařízení po restartu) – nic nemažeme.
            let status = (error as? KeychainError)?.status ?? 0
            logger.notice("Klíčenka není dostupná (\(status, privacy: .public)), účet se načte později")
            if account == nil,
               let legacyData = defaults.data(forKey: legacyDefaultsKey),
               let saved = try? JSONDecoder().decode(StagAccount.self, from: legacyData) {
                account = saved
            }
            return false
        }
    }

    /// Po přechodné chybě zkusí účet načíst znovu, až bude zařízení odemčené / aplikace aktivní.
    private func scheduleRetry() {
        guard retryObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names = [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification]
        retryObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    StagAccountStore.shared.retryLoad()
                }
            }
        }
    }

    private func retryLoad() {
        if load() { cancelRetry() }
    }

    private func cancelRetry() {
        for observer in retryObservers { NotificationCenter.default.removeObserver(observer) }
        retryObservers = []
    }

    private func persist() {
        guard let account, let data = try? JSONEncoder().encode(account) else { return }
        if !KeychainStore.set(data, for: accountKey) {
            logger.error("Uložení účtu STAG do Klíčenky selhalo")
        }
    }

    // MARK: - Cookies

    /// Domény škol (poslední dvě části hostu, např. „utb.cz“) – cookies STAGu i školního SSO
    private static func schoolHosts(including school: StagSchool?) -> Set<String> {
        let schools = StagSchool.all + [school, StagSchoolPreference.selected].compactMap { $0 }
        return Set(schools.compactMap { school in
            guard let host = school.baseURL.host()?.lowercased() else { return nil }
            let labels = host.split(separator: ".")
            return labels.count > 2 ? labels.suffix(2).joined(separator: ".") : host
        })
    }

    private static func removeCookies(forHosts domains: Set<String>) {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies ?? [] {
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") { domain.removeFirst() }
            if domains.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) {
                storage.deleteCookie(cookie)
            }
        }
    }
}
