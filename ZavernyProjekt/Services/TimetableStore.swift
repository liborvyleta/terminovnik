import Foundation
import Observation
import SwiftData
import WidgetKit

/// Rozvrh studenta načtený z IS/STAG přes uložený účet.
///
/// Rozvrh se ukládá do App Group (`TimetableSnapshot`), takže funguje i offline
/// a čte ho widget „Další hodina“. Barvy akcí odpovídají barvám předmětů v aplikaci.
/// Používají ho obrazovka rozvrhu, ``ClassReminderScheduler``, Live Activity a ``BackgroundRefresh``.
/// Při změně rozvrhu stejného účtu upozorní přes `NotificationManager`.
@Observable
final class TimetableStore {
    /// Sdílená instance
    static let shared = TimetableStore()

    /// Uložený rozvrh, nebo `nil`, pokud zatím žádný není
    private(set) var snapshot: TimetableSnapshot?
    /// Probíhá načítání ze STAGu
    private(set) var isLoading = false
    /// Poslední chybová hláška pro UI (`nil` = bez chyby)
    private(set) var errorMessage: String?

    /// Jak starý rozvrh se při otevření aplikace automaticky obnoví
    private let maxAge: TimeInterval = 6 * 60 * 60

    /// Účet (škola + osobní číslo), kterému patří uložený rozvrh
    private static let ownerKey = "timetableSnapshot.owner"
    /// Zapnutí oznámení o změnách rozvrhu (Nastavení)
    nonisolated static let changeAlertsEnabledKey = "timetableChangeAlertsEnabled"

    /// Soukromý inicializátor – načte uložený rozvrh z App Group.
    private init() {
        snapshot = TimetableSnapshot.load()
    }

    /// Rozvrhové akce uloženého rozvrhu (prázdné, pokud rozvrh není).
    var events: [TimetableEvent] { snapshot?.events ?? [] }
    /// Existuje rozvrh s aspoň jednou akcí.
    var hasTimetable: Bool { !(snapshot?.events.isEmpty ?? true) }

    /// Načte rozvrh ze STAGu (aktuální semestr). Bez přihlášení jen nastaví chybovou hlášku.
    ///
    /// Asynchronně zjistí období, stáhne rozvrhové akce, obarví je podle předmětů, uloží snímek
    /// do App Group, případně upozorní na změny a obnoví widget, připomínky hodin a Live Activity.
    /// Vypršené přihlášení účet odhlásí; chyby se ukládají do ``errorMessage``.
    /// - Parameter context: kontext SwiftData pro čtení barev předmětů
    /// - Note: V ukázkovém režimu nedělá nic – nesmí přepsat skutečný rozvrh.
    func refresh(context: ModelContext) async {
        if DemoMode.isActive { return }
        guard let account = StagAccountStore.shared.account,
              let service = StagAccountStore.shared.makeService() else {
            errorMessage = String(localized: "Pro načtení rozvrhu se přihlas do IS/STAG.")
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Období je veřejná služba – zjistíme ho bez ticketu
            let period = try await StagService(baseURL: account.resolvedSchool.baseURL).currentPeriod()
            let actions = try await service.studentTimetable(
                osCislo: account.osCislo,
                semester: period.obdobi,
                year: period.akademRok
            )
            let colors = subjectColors(in: context)
            let events = actions.compactMap { action in
                action.timetableEvent(hexColor: colors[(action.predmet ?? "").uppercased()])
            }
            let fresh = TimetableSnapshot(
                events: events,
                semester: period.obdobi,
                academicYear: period.akademRok,
                fetchedAt: .now
            )
            // Změny proti předchozímu rozvrhu – jen u stejného účtu (semestr hlídá detektor)
            let owner = "\(account.resolvedSchool.baseURL)|\(account.osCislo)"
            let previousOwner = AppGroup.defaults?.string(forKey: Self.ownerKey)
            let changes = previousOwner == owner
                ? TimetableChangeDetector.diff(old: snapshot, new: fresh)
                : []
            fresh.save()
            AppGroup.defaults?.set(owner, forKey: Self.ownerKey)
            snapshot = fresh
            if !changes.isEmpty {
                await NotificationManager.shared.notifyTimetableChanges(changes)
            }
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            // Nový rozvrh → přeplánovat připomínky hodin a obnovit Live Activity
            ClassReminderScheduler.shared.reschedule()
            LiveActivityManager.shared.updateLessonActivity()
        } catch StagError.unauthorized {
            StagAccountStore.shared.signOut()
            errorMessage = String(localized: "Přihlášení do STAGu vypršelo, přihlas se znovu.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Obnoví rozvrh, jen když je uživatel přihlášený a rozvrh chybí nebo je starší než pár hodin.
    ///
    /// Asynchronní; hranici stáří určuje ``maxAge`` (6 hodin).
    /// - Parameter context: kontext SwiftData předaný do ``refresh(context:)``
    func refreshIfNeeded(context: ModelContext) async {
        guard StagAccountStore.shared.isConnected else { return }
        if let snapshot, Date.now.timeIntervalSince(snapshot.fetchedAt) < maxAge { return }
        await refresh(context: context)
    }

    /// Smaže uložený rozvrh (např. po odhlášení ze STAGu).
    ///
    /// Odstraní snímek a vlastníka z App Group, obnoví widget a zruší připomínky hodin.
    /// - Note: V ukázkovém režimu vymaže jen stav v paměti.
    func clear() {
        // V demu jen paměť – skutečný rozvrh v App Group a připomínky hodin zůstanou
        if DemoMode.isActive { snapshot = nil; errorMessage = nil; return }
        TimetableSnapshot.clear()
        AppGroup.defaults?.removeObject(forKey: Self.ownerKey)
        snapshot = nil
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
        // Bez rozvrhu nemají připomínky hodin smysl
        ClassReminderScheduler.shared.cancelAll()
    }

    /// Barvy předmětů podle kódu, aby rozvrh ladil se zbytkem aplikace.
    /// - Parameter context: kontext SwiftData s předměty
    /// - Returns: Slovník velkými písmeny psaný kód → hex barva (při duplicitě vyhrává první).
    private func subjectColors(in context: ModelContext) -> [String: String] {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        return Dictionary(subjects.map { ($0.code.uppercased(), $0.hexColor) }, uniquingKeysWith: { first, _ in first })
    }
}

// Ukázkový režim – data jen v paměti, nic se neukládá
extension TimetableStore {
    /// Nastaví demo rozvrh jen v paměti (nic se neukládá do App Group).
    /// - Parameter snapshot: ukázkový rozvrh
    func loadDemo(_ snapshot: TimetableSnapshot) {
        self.snapshot = snapshot
        errorMessage = nil
    }

    /// Po ukončení dema vrátí skutečný rozvrh z App Group a vymaže chybovou hlášku.
    func reloadAfterDemo() {
        snapshot = TimetableSnapshot.load()
        errorMessage = nil
    }
}
