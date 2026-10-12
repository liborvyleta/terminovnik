import Foundation
import Observation
import SwiftData

/// ViewModel sekce „Účet IS/STAG“ v Nastavení.
///
/// Zobrazuje připojený účet ze `StagAccountStore` a spouští aktualizaci předmětů přes `StagSubjectSync` – s uloženým ticketem, tedy bez nového přihlášení – spolu s obnovou rozvrhu, termínů a známek. Umožňuje také odhlášení účtu. V DEBUG sestavení nabízí náhledové instance pro #Preview.
@Observable
final class StagAccountViewModel {
    /// Stav ruční aktualizace předmětů ze STAGu.
    ///
    /// Řídí, zda sekce ukazuje průběh, výsledek synchronizace, nebo chybu.
    enum SyncState: Equatable {
        case idle
        case syncing
        case finished(StagSubjectSync.SyncResult)
        case failed(String)
    }

    /// Aktuální stav synchronizace zobrazovaný v sekci.
    private(set) var state: SyncState = .idle

    /// Úložiště účtu STAG (ticket a údaje o účtu).
    private let store: StagAccountStore

    #if DEBUG
    /// Jen pro #Preview: pevný účet místo skutečného úložiště.
    private var isPreview = false
    /// Pevný účet zobrazovaný v náhledu.
    private var previewAccount: StagAccount?
    #endif

    /// Vytvoří ViewModel nad úložištěm účtu.
    /// - Parameter store: Úložiště účtu STAG; výchozí je sdílená instance.
    init(store: StagAccountStore = .shared) {
        self.store = store
    }

    // MARK: - Odvozený stav

    /// Připojený účet (nil = nepřipojeno). Sleduje změny v úložišti díky @Observable.
    var account: StagAccount? {
        #if DEBUG
        if isPreview { return previewAccount }
        #endif
        return store.account
    }

    /// Příznak, zda je účet STAG připojený.
    var isConnected: Bool { account != nil }

    /// Příznak, zda právě probíhá synchronizace.
    var isSyncing: Bool { state == .syncing }

    // MARK: - Akce

    /// Aktualizuje předměty ze STAGu (a s nimi rozvrh, termíny a známky).
    ///
    /// Při vypršeném přihlášení se účet odhlásí a v sekci se zobrazí chyba s výzvou k novému přihlášení. Pokud synchronizace už běží, nic nedělá.
    /// - Parameter context: SwiftData kontext, do kterého se předměty ukládají.
    func sync(context: ModelContext) async {
        guard !isSyncing else { return }
        state = .syncing
        do {
            let result = try await StagSubjectSync.sync(in: context, store: store)
            // Spolu s předměty obnovíme i rozvrh, termíny zkoušek a známky
            await TimetableStore.shared.refresh(context: context)
            await ExamTermStore.shared.refresh(context: context)
            await GradeStore.shared.refresh()
            state = .finished(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Odhlášení ze STAGu – smaže ticket, údaje o účtu i data načtená ze STAGu (rozvrh, termíny, známky).
    ///
    /// Předměty a deadliny v aplikaci zůstanou. V ukázkovém režimu jen ukončí demo. Stav synchronizace vrátí na `.idle`.
    func signOut() {
        #if DEBUG
        if isPreview {
            previewAccount = nil
            state = .idle
            return
        }
        #endif
        store.signOut()
        state = .idle
    }
}

#if DEBUG
// MARK: - Náhled

/// Náhledové instance ``StagAccountViewModel`` pro #Preview.
extension StagAccountViewModel {
    /// Připojený účet po úspěšné aktualizaci – bez sítě a bez Klíčenky.
    static var previewConnected: StagAccountViewModel {
        let viewModel = StagAccountViewModel()
        viewModel.isPreview = true
        viewModel.previewAccount = StagAccount(
            fullName: "Jan Novák",
            osCislo: "A23456",
            stagUser: "st12345",
            faculty: "FAI",
            connectedAt: .now.addingTimeInterval(-12 * 24 * 3600),
            lastSyncAt: .now.addingTimeInterval(-25 * 60)
        )
        viewModel.state = .finished(.init(added: 2, updated: 1, total: 5))
        return viewModel
    }

    /// Nepřipojený stav – bez sítě a bez Klíčenky.
    static var previewDisconnected: StagAccountViewModel {
        let viewModel = StagAccountViewModel()
        viewModel.isPreview = true
        return viewModel
    }
}
#endif
