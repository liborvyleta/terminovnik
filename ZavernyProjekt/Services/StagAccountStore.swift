import Foundation
import Observation
import UIKit
import UserNotifications
import os

/// Připojený účet IS/STAG (bez ticketu – ten je v Klíčence zvlášť).
///
/// Vzniká po úspěšném přihlášení, ``StagAccountStore`` ho ukládá jako JSON do Klíčenky
/// a z jeho údajů (`stagUser`, škola) sestavuje ``StagService`` pro dotazy na STAG.
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

    /// Škola účtu – starší uložené účty bez vyplněné školy patří UTB.
    var resolvedSchool: StagSchool { school ?? .utb }
}

/// Chyba při ukládání přihlášení.
///
/// Vyhazuje ji ``StagAccountStore/connect(_:ticket:)``, když se ticket nebo účet
/// nepodaří zapsat do Klíčenky; přihlašovací obrazovka zobrazí `errorDescription`.
nonisolated enum StagAccountError: LocalizedError {
    /// Ticket nebo účet se nepodařilo zapsat do Klíčenky
    case keychainWriteFailed

    /// Lokalizovaný popis chyby pro zobrazení uživateli.
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
    /// Sdílená instance používaná celou aplikací.
    static let shared = StagAccountStore()

    /// Aktuálně připojený účet (nil = uživatel není přihlášený).
    private(set) var account: StagAccount?

    /// Starší umístění účtu (UserDefaults) – při startu se přesune do Klíčenky
    private let legacyDefaultsKey = "stagAccount.v1"
    /// Značka, že aplikace na tomto zařízení už běžela (po přeinstalaci chybí)
    private let installMarkerKey = "installMarker.v1"
    /// Položka v Klíčence s přístupovým ticketem.
    private let ticketKey = "stagTicket"
    /// Položka v Klíčence s JSON údaji o účtu.
    private let accountKey = "stagAccount"

    /// Logger pro chyby a stavy Klíčenky.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Terminovnik", category: "stag-account")
    /// Pozorovatelé pro opakované načtení po odemčení (jen po přechodné chybě Klíčenky)
    @ObservationIgnored private var retryObservers: [NSObjectProtocol] = []

    /// Vytvoří úložiště a načte uložený účet.
    ///
    /// V ukázkovém režimu použije fiktivní účet z `DemoData`; při přechodné nedostupnosti
    /// Klíčenky naplánuje opakované načtení přes ``scheduleRetry()``.
    private init() {
        if DemoMode.isActive { account = DemoData.account; return }
        if !load() { scheduleRetry() }
    }

    /// Zda je připojený účet IS/STAG.
    var isConnected: Bool { account != nil }

    /// Přístupový ticket z Klíčenky (nil = chybí, je aktivní ukázkový režim, nebo je Klíčenka momentálně nedostupná).
    var ticket: String? {
        if DemoMode.isActive { return nil }
        return KeychainStore.string(for: ticketKey)
    }

    /// Uloží účet po úspěšném přihlášení.
    ///
    /// Zapíše ticket i účet do Klíčenky, smaže starší umístění v UserDefaults, nastaví
    /// značku instalace a zruší případné čekání na odemčení. V ukázkovém režimu
    /// účet jen podrží v paměti.
    /// - Parameters:
    ///   - account: Údaje o přihlášeném studentovi.
    ///   - ticket: Přístupový ticket IS/STAG.
    /// - Throws: ``StagAccountError/keychainWriteFailed``, pokud se ticket nebo účet nepodařilo uložit
    ///   (při selhání zápisu účtu se již uložený ticket zase odstraní).
    func connect(_ account: StagAccount, ticket: String) throws {
        if DemoMode.isActive { self.account = account; return }
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

    /// Poznamená čas posledního načtení předmětů a uloží účet do Klíčenky.
    /// - Parameter date: Okamžik synchronizace (výchozí je aktuální čas).
    func markSynced(at date: Date = .now) {
        account?.lastSyncAt = date
        persist()
    }

    /// Odhlášení – smaže ticket, údaje o účtu, načtená data ze STAGu a vše, co by po účtu zůstalo
    /// (Live Activity, doručená oznámení, připomínky hodin, HTTP cache a cookies škol).
    /// - Note: V ukázkovém režimu jen ukončí demo, skutečný účet zůstane zachovaný.
    func signOut() {
        // V ukázkovém režimu odhlášení = ukončení dema (skutečný účet zůstane)
        if DemoMode.isActive { DemoController.shared.exit(); return }
        let schoolHosts = Self.schoolHosts(including: account?.resolvedSchool)

        KeychainStore.remove(ticketKey)
        KeychainStore.remove(accountKey)
        account = nil
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        cancelRetry()

        TimetableStore.shared.clear()
        ExamTermStore.shared.clear()
        GradeStore.shared.clear()
        ClassReminderScheduler.shared.cancelAll()
        LiveActivityManager.shared.endAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // STAG už jde přes ephemeral session; uklidíme, co mohla uložit starší verze přes URLSession.shared.
        URLCache.shared.removeAllCachedResponses()
        Self.removeCookies(forHosts: schoolHosts)
    }

    /// Vytvoří klienta STAGu s přihlášením uloženého účtu.
    /// - Returns: ``StagService`` pro školu účtu, nebo nil, pokud účet nebo ticket chybí.
    func makeService() -> StagService? {
        guard let account, let ticket else { return nil }
        return StagService(baseURL: account.resolvedSchool.baseURL, ticket: ticket, stagUser: account.stagUser)
    }

    // MARK: - Načtení a migrace

    /// Načte účet z Klíčenky (případně ho přesune z UserDefaults) a po čisté instalaci uklidí
    /// přihlášení, které v Klíčence zůstalo po předchozí instalaci.
    ///
    /// Neúplné nebo poškozené přihlášení zahodí. Při přechodné chybě Klíčenky nic nemaže
    /// a jako náhradu zkusí použít účet ze starého umístění v UserDefaults.
    /// - Returns: `false` při přechodné chybě Klíčenky (nic se nesmazalo, zkusí se to znovu), jinak `true`.
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
    ///
    /// Registruje pozorovatele `protectedDataDidBecomeAvailable` a `didBecomeActive`;
    /// pokud už pozorovatelé existují, nic nedělá.
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

    /// Zopakuje ``load()`` a po úspěchu odregistruje pozorovatele.
    private func retryLoad() {
        if load() { cancelRetry() }
    }

    /// Odregistruje všechny pozorovatele opakovaného načtení.
    private func cancelRetry() {
        for observer in retryObservers { NotificationCenter.default.removeObserver(observer) }
        retryObservers = []
    }

    /// Uloží aktuální účet do Klíčenky (mimo ukázkový režim).
    ///
    /// Selhání zápisu jen zaloguje.
    private func persist() {
        if DemoMode.isActive { return }
        guard let account, let data = try? JSONEncoder().encode(account) else { return }
        if !KeychainStore.set(data, for: accountKey) {
            logger.error("Uložení účtu STAG do Klíčenky selhalo")
        }
    }

    // MARK: - Ukázkový režim

    /// Nastaví fiktivní účet jen v paměti (Klíčenka se nedotkne).
    /// - Parameter demoAccount: Ukázkový účet z dema.
    func loadDemo(_ demoAccount: StagAccount) {
        cancelRetry()
        account = demoAccount
    }

    /// Po ukončení dema znovu načte skutečný účet z Klíčenky.
    func reloadAfterDemo() {
        account = nil
        if !load() { scheduleRetry() }
    }

    // MARK: - Cookies

    /// Domény škol (poslední dvě části hostu, např. „utb.cz“) – cookies STAGu i školního SSO.
    /// - Parameter school: Škola účtu, která se přidá k seznamu známých škol a zvolené škole.
    /// - Returns: Množina domén všech dotčených škol.
    private static func schoolHosts(including school: StagSchool?) -> Set<String> {
        let schools = StagSchool.all + [school, StagSchoolPreference.selected].compactMap { $0 }
        return Set(schools.compactMap { school in
            guard let host = school.baseURL.host()?.lowercased() else { return nil }
            let labels = host.split(separator: ".")
            return labels.count > 2 ? labels.suffix(2).joined(separator: ".") : host
        })
    }

    /// Smaže ze sdíleného úložiště cookies všech zadaných domén včetně subdomén.
    /// - Parameter domains: Domény škol z ``schoolHosts(including:)``.
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
