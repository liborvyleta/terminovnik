import Foundation
import Observation
import SwiftData

/// ViewModel sekce „Účet IS/STAG“ v Nastavení.
///
/// Zobrazuje připojený účet ze `StagAccountStore` a spouští aktualizaci předmětů
/// přes `StagSubjectSync` – s uloženým ticketem, tedy bez nového přihlášení.
@Observable
final class StagAccountViewModel {
    enum SyncState: Equatable {
        case idle
        case syncing
        case finished(StagSubjectSync.SyncResult)
        case failed(String)
    }

    private(set) var state: SyncState = .idle

    private let store: StagAccountStore

    #if DEBUG
    /// Jen pro #Preview: pevný účet místo skutečného úložiště
    private var isPreview = false
    private var previewAccount: StagAccount?
    #endif

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

    var isConnected: Bool { account != nil }

    var isSyncing: Bool { state == .syncing }

    // MARK: - Akce

    /// Aktualizuje předměty ze STAGu. Při vypršeném přihlášení se účet odhlásí
    /// a v sekci se zobrazí chyba s výzvou k novému přihlášení.
    func sync(context: ModelContext) async {
        guard !isSyncing else { return }
        state = .syncing
        do {
            let result = try await StagSubjectSync.sync(in: context, store: store)
            // Spolu s předměty obnovíme i rozvrh
            await TimetableStore.shared.refresh(context: context)
            state = .finished(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Odhlášení ze STAGu – smaže ticket i údaje o účtu, předměty v aplikaci zůstanou.
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

extension StagAccountViewModel {
    /// Připojený účet po úspěšné aktualizaci – bez sítě a bez Klíčenky
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

    /// Nepřipojený stav
    static var previewDisconnected: StagAccountViewModel {
        let viewModel = StagAccountViewModel()
        viewModel.isPreview = true
        return viewModel
    }
}
#endif
