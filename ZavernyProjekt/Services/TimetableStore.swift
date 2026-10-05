import Foundation
import Observation
import SwiftData
import WidgetKit

/// Rozvrh studenta načtený z IS/STAG přes uložený účet.
///
/// Rozvrh se ukládá do App Group (`TimetableSnapshot`), takže funguje i offline
/// a čte ho widget „Další hodina“. Barvy akcí odpovídají barvám předmětů v aplikaci.
@Observable
final class TimetableStore {
    static let shared = TimetableStore()

    private(set) var snapshot: TimetableSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Jak starý rozvrh se při otevření aplikace automaticky obnoví
    private let maxAge: TimeInterval = 6 * 60 * 60

    private init() {
        snapshot = TimetableSnapshot.load()
    }

    var events: [TimetableEvent] { snapshot?.events ?? [] }
    var hasTimetable: Bool { !(snapshot?.events.isEmpty ?? true) }

    /// Načte rozvrh ze STAGu (aktuální semestr). Bez přihlášení jen nastaví chybovou hlášku.
    func refresh(context: ModelContext) async {
        guard let account = StagAccountStore.shared.account,
              let service = StagAccountStore.shared.makeService() else {
            errorMessage = "Pro načtení rozvrhu se přihlas do IS/STAG."
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Období je veřejná služba – zjistíme ho bez ticketu
            let period = try await StagService().currentPeriod()
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
            fresh.save()
            snapshot = fresh
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch StagError.unauthorized {
            StagAccountStore.shared.signOut()
            errorMessage = "Přihlášení do STAGu vypršelo, přihlas se znovu."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Obnoví rozvrh, jen když je uživatel přihlášený a rozvrh chybí nebo je starší než pár hodin.
    func refreshIfNeeded(context: ModelContext) async {
        guard StagAccountStore.shared.isConnected else { return }
        if let snapshot, Date.now.timeIntervalSince(snapshot.fetchedAt) < maxAge { return }
        await refresh(context: context)
    }

    /// Smaže uložený rozvrh (např. po odhlášení ze STAGu)
    func clear() {
        TimetableSnapshot.clear()
        snapshot = nil
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Barvy předmětů podle kódu, aby rozvrh ladil se zbytkem aplikace
    private func subjectColors(in context: ModelContext) -> [String: String] {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        return Dictionary(subjects.map { ($0.code.uppercased(), $0.hexColor) }, uniquingKeysWith: { first, _ in first })
    }
}
