import Foundation
import Observation

/// Připojený účet IS/STAG (bez ticketu – ten je v Klíčence).
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
}

/// Úložiště připojeného účtu IS/STAG.
///
/// Údaje o studentovi jsou v UserDefaults, přístupový ticket v Klíčence.
/// Díky dlouhodobému ticketu (`longTicket=1`, platí až 90 dní) se uživatel nemusí
/// přihlašovat při každé aktualizaci předmětů. Odhlášením se vše smaže.
@Observable
final class StagAccountStore {
    static let shared = StagAccountStore()

    private(set) var account: StagAccount?

    private let defaultsKey = "stagAccount.v1"
    private let ticketKey = "stagTicket"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(StagAccount.self, from: data),
           KeychainStore.string(for: ticketKey) != nil {
            account = saved
        } else {
            // Klíčenka přežije odinstalaci aplikace – po čisté instalaci starý ticket zahodíme.
            KeychainStore.remove(ticketKey)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    var isConnected: Bool { account != nil }

    /// Přístupový ticket z Klíčenky
    var ticket: String? { KeychainStore.string(for: ticketKey) }

    /// Uloží účet po úspěšném přihlášení
    func connect(_ account: StagAccount, ticket: String) {
        KeychainStore.set(ticket, for: ticketKey)
        self.account = account
        persist()
    }

    /// Poznamená čas posledního načtení předmětů
    func markSynced(at date: Date = .now) {
        account?.lastSyncAt = date
        persist()
    }

    /// Odhlášení – smaže ticket i údaje o účtu
    func signOut() {
        KeychainStore.remove(ticketKey)
        account = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Klient STAGu s přihlášením uloženého účtu (nil = nepřipojeno)
    func makeService() -> StagService? {
        guard let account, let ticket else { return nil }
        return StagService(ticket: ticket, stagUser: account.stagUser)
    }

    private func persist() {
        guard let account, let data = try? JSONEncoder().encode(account) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
