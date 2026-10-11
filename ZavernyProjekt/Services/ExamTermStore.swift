import Foundation
import Observation
import SwiftData
import UserNotifications

/// Termíny zkoušek ze STAGu načtené přes uložený účet.
///
/// - Termíny se ukládají do App Group (fungují offline).
/// - Zapsané termíny se automaticky převádí na zkoušky (`ExamTask` se `stagTermID`) s připomínkou den předem;
///   po odhlášení z termínu ve STAGu se zkouška z aplikace odstraní.
/// - Nově vypsané termíny vyvolají okamžité lokální oznámení (při otevření aplikace i při kontrole na pozadí).
@Observable
final class ExamTermStore {
    static let shared = ExamTermStore()

    /// Klíč přepínače v Nastavení – upozornění na nové termíny (výchozí zapnuto)
    nonisolated static let alertsEnabledKey = "examTermAlertsEnabled"

    private(set) var terms: [ExamTerm] = []
    private(set) var fetchedAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Termíny objevené při posledních kontrolách, které si uživatel ještě neprohlédl (štítek „Nový“)
    private(set) var newTermIDs: Set<String> = []
    /// Termíny, do jejichž fronty čekatelů se uživatel zapsal z aplikace
    /// (STAG to v seznamu termínů neuvádí – evidujeme lokálně, aby šlo nabídnout odhlášení z fronty)
    private(set) var queuedTermIDs: Set<String> = []
    /// Právě probíhající zápis/odhlášení (pro ProgressView a zablokování dalších akcí)
    private(set) var pendingRegistration: PendingRegistration?

    /// Probíhající změna zápisu na termín
    struct PendingRegistration: Equatable {
        let termID: String
        let action: StagTermRegistrationAction
    }

    /// Jak starý seznam se při otevření aplikace obnoví
    private let maxAge: TimeInterval = 15 * 60

    private enum Keys {
        static let snapshot = "examTerms.v1"
        static let seen = "examTerms.seenIDs"
        static let new = "examTerms.newIDs"
        static let queued = "examTerms.queuedIDs"
    }

    private struct Snapshot: Codable {
        var terms: [ExamTerm]
        var fetchedAt: Date
    }

    private init() {
        restoreFromCache()
    }

    /// Načte uložené termíny z App Group
    private func restoreFromCache() {
        terms = []
        fetchedAt = nil
        let defaults = AppGroup.defaults
        if let data = defaults?.data(forKey: Keys.snapshot),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            terms = snapshot.terms
            fetchedAt = snapshot.fetchedAt
        }
        newTermIDs = Set(defaults?.stringArray(forKey: Keys.new) ?? [])
        queuedTermIDs = Set(defaults?.stringArray(forKey: Keys.queued) ?? [])
    }

    // MARK: - Odvozené seznamy

    /// Zapsané termíny (nadcházející), od nejbližšího
    var registeredTerms: [ExamTerm] {
        terms.filter { $0.isRegistered && $0.isUpcoming() }.sorted { $0.start < $1.start }
    }

    /// Termíny, na které se lze zapsat nebo jsou vypsané (nadcházející, platné, nezapsané)
    var availableTerms: [ExamTerm] {
        terms.filter { !$0.isRegistered && !$0.isCancelled && $0.isUpcoming() }.sorted { $0.start < $1.start }
    }

    var hasNewTerms: Bool { !newTermIDs.isEmpty }

    func terms(forSubject code: String) -> [ExamTerm] {
        terms.filter { $0.subjectCode.caseInsensitiveCompare(code) == .orderedSame && $0.isUpcoming() }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Načítání

    /// Načte termíny ze STAGu, sladí zkoušky v aplikaci a upozorní na nové termíny.
    /// - Returns: počet nově objevených termínů
    @discardableResult
    func refresh(context: ModelContext) async -> Int {
        if DemoMode.isActive { return 0 }
        guard let account = StagAccountStore.shared.account,
              let service = StagAccountStore.shared.makeService() else {
            errorMessage = String(localized: "Pro načtení termínů se přihlas do IS/STAG.")
            return 0
        }
        guard !isLoading else { return 0 }
        isLoading = true
        defer { isLoading = false }

        do {
            let fresh = try await service.studentExamTerms(osCislo: account.osCislo).compactMap { $0.examTerm() }
            let discovered = detectNewTerms(in: fresh)
            terms = fresh
            fetchedAt = .now
            errorMessage = nil
            persist()
            pruneQueuedTerms()
            syncRegisteredTasks(in: context)
            if !discovered.isEmpty { await notifyAboutNewTerms(discovered, context: context) }
            return discovered.count
        } catch StagError.unauthorized {
            StagAccountStore.shared.signOut()
            errorMessage = String(localized: "Přihlášení do STAGu vypršelo, přihlas se znovu.")
        } catch {
            errorMessage = error.localizedDescription
        }
        return 0
    }

    /// Obnoví termíny, pokud je uživatel přihlášený a seznam je starší než pár minut.
    func refreshIfNeeded(context: ModelContext) async {
        guard StagAccountStore.shared.isConnected else { return }
        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge { return }
        await refresh(context: context)
    }

    /// Uživatel si nové termíny prohlédl – zmizí štítek „Nový“
    func markAllSeen() {
        guard !newTermIDs.isEmpty else { return }
        newTermIDs = []
        guard !DemoMode.isActive else { return }
        AppGroup.defaults?.removeObject(forKey: Keys.new)
    }

    /// Smaže uložené termíny (po odhlášení ze STAGu). Zkoušky v aplikaci zůstávají.
    func clear() {
        terms = []
        fetchedAt = nil
        newTermIDs = []
        queuedTermIDs = []
        errorMessage = nil
        // V demu jen paměť – skutečná cache v App Group zůstane
        guard !DemoMode.isActive else { return }
        let defaults = AppGroup.defaults
        defaults?.removeObject(forKey: Keys.snapshot)
        defaults?.removeObject(forKey: Keys.seen)
        defaults?.removeObject(forKey: Keys.new)
        defaults?.removeObject(forKey: Keys.queued)
    }

    // MARK: - Zápis na termíny (OSTRÉ operace ve STAGu)
    // Volat VÝHRADNĚ po výslovném potvrzení uživatelem v dialogu.

    /// Zapíše studenta na termín
    func register(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.register, for: term, context: context)
    }

    /// Odhlásí studenta z termínu
    func unregister(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.unregister, for: term, context: context)
    }

    /// Zapíše studenta do fronty čekatelů na plný termín
    func joinQueue(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.joinQueue, for: term, context: context)
    }

    /// Odhlásí studenta z fronty čekatelů
    func leaveQueue(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.leaveQueue, for: term, context: context)
    }

    func isQueued(_ term: ExamTerm) -> Bool { queuedTermIDs.contains(term.id) }

    /// Provede změnu zápisu ve STAGu; po úspěchu obnoví termíny (zapsané se samy převedou na zkoušky s připomínkou).
    func changeRegistration(_ action: StagTermRegistrationAction, for term: ExamTerm,
                            context: ModelContext) async -> StagTermRegistrationResult {
        if DemoMode.isActive { return .failure("V demo režimu se na termíny nezapisuje.") }
        guard let account = StagAccountStore.shared.account,
              let service = StagAccountStore.shared.makeService() else {
            return .failure(String(localized: "Pro zápis na termín se přihlas do IS/STAG."))
        }
        guard pendingRegistration == nil else {
            return .failure(String(localized: "Počkej, než se dokončí předchozí změna zápisu."))
        }
        pendingRegistration = PendingRegistration(termID: term.id, action: action)
        defer { pendingRegistration = nil }

        let result: StagTermRegistrationResult
        do {
            result = try await service.changeTermRegistration(action, osCislo: account.osCislo, termIdno: term.id)
        } catch StagError.unauthorized {
            StagAccountStore.shared.signOut()
            return .failure(String(localized: "Přihlášení do STAGu vypršelo, přihlas se znovu."))
        } catch {
            // Stav ve STAGu je nejistý (např. vypadlo spojení po odeslání) – obnovíme seznam
            await refresh(context: context)
            return .failure(error.localizedDescription)
        }

        if result == .success {
            switch action {
            case .joinQueue: queuedTermIDs.insert(term.id)
            case .leaveQueue, .register, .unregister: queuedTermIDs.remove(term.id)
            }
            persistQueued()
        }
        // Obnovíme i po neúspěchu – STAG mohl mezitím změnit obsazenost či stav termínu
        await refresh(context: context)
        return result
    }

    /// Fronta u termínů, které zmizely, proběhly nebo na které už je student zapsaný, nedává smysl
    private func pruneQueuedTerms() {
        let valid = Set(terms.filter { !$0.isRegistered && $0.isUpcoming() }.map(\.id))
        let pruned = queuedTermIDs.intersection(valid)
        guard pruned != queuedTermIDs else { return }
        queuedTermIDs = pruned
        persistQueued()
    }

    private func persistQueued() {
        guard !DemoMode.isActive else { return }
        AppGroup.defaults?.set(Array(queuedTermIDs), forKey: Keys.queued)
    }

    // MARK: - Nové termíny

    /// Vrátí nově objevené vypsané termíny. Při úplně prvním načtení nic nehlásí (jinak by zasypal uživatele).
    private func detectNewTerms(in fresh: [ExamTerm]) -> [ExamTerm] {
        let defaults = AppGroup.defaults
        let isFirstSync = defaults?.object(forKey: Keys.seen) == nil
        var seen = Set(defaults?.stringArray(forKey: Keys.seen) ?? [])
        let candidates = fresh.filter { !$0.isRegistered && !$0.isCancelled && $0.isUpcoming() }
        let discovered = isFirstSync ? [] : candidates.filter { !seen.contains($0.id) }
        seen.formUnion(fresh.map(\.id))
        defaults?.set(Array(seen), forKey: Keys.seen)
        if !discovered.isEmpty {
            newTermIDs.formUnion(discovered.map(\.id))
            defaults?.set(Array(newTermIDs), forKey: Keys.new)
        }
        return discovered
    }

    /// Okamžité lokální oznámení o nových termínech (víc termínů = jedno souhrnné oznámení)
    private func notifyAboutNewTerms(_ discovered: [ExamTerm], context: ModelContext) async {
        let enabled = UserDefaults.standard.object(forKey: Self.alertsEnabledKey) as? Bool ?? true
        guard enabled else { return }
        let names = subjectNames(in: context)
        let content = UNMutableNotificationContent()
        content.sound = .default
        if discovered.count == 1, let term = discovered.first {
            content.title = String(localized: "Nový termín: \(term.subjectCode) – \(term.typeName)", comment: "Oznámení: kód předmětu a typ termínu ze STAGu")
            content.subtitle = names[term.subjectCode.uppercased()] ?? ""
            var parts = [term.start.deadlineLongFormatted]
            if let room = term.room { parts.append(room) }
            if let free = term.freeSpots, let capacity = term.capacity { parts.append(String(localized: "volno \(free)/\(capacity)", comment: "Volná místa / kapacita termínu")) }
            content.body = parts.joined(separator: " · ")
        } else {
            let codes = Array(Set(discovered.map(\.subjectCode))).sorted().joined(separator: ", ")
            content.title = String(localized: "Vypsáno \(discovered.count) nových termínů", comment: "Oznámení o více nových termínech najednou (počet ≥ 2)")
            content.body = String(localized: "Předměty: \(codes). Otevři Termínovník a zapiš se, dokud jsou volná místa.", comment: "Kódy předmětů oddělené čárkou")
        }
        let request = UNNotificationRequest(identifier: "term-new-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Zapsané termíny → zkoušky v aplikaci

    /// Zapsané nadcházející termíny promítne do zkoušek v aplikaci (vytvoří / aktualizuje / odstraní).
    private func syncRegisteredTasks(in context: ModelContext) {
        let registered = terms.filter { $0.isRegistered && !$0.isCancelled && $0.isUpcoming() }
        let registeredIDs = Set(registered.map(\.id))
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let subjectByCode = Dictionary(subjects.map { ($0.code.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let linked = ((try? context.fetch(FetchDescriptor<ExamTask>())) ?? []).filter { $0.stagTermID != nil }
        let linkedByID = Dictionary(linked.map { ($0.stagTermID!, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false

        for term in registered {
            let subject = subjectByCode[term.subjectCode.uppercased()]
            let note = [term.room.map { String(localized: "Místnost \($0)", comment: "Poznámka zkoušky: místnost ze STAGu") }, term.teacher, term.note].compactMap { $0 }.joined(separator: " · ")
            if let task = linkedByID[term.id] {
                // Termín se mohl ve STAGu přesunout – udržujeme datum a místnost aktuální
                if task.dueDate != term.start || task.note != note {
                    task.dueDate = term.start
                    task.note = note
                    NotificationManager.shared.updateReminder(for: task)
                    changed = true
                }
            } else {
                let task = ExamTask(
                    title: term.taskTitle(subjectName: subject?.name),
                    taskType: term.taskType,
                    dueDate: term.start,
                    note: note,
                    stagTermID: term.id
                )
                context.insert(task)
                task.subject = subject
                NotificationManager.shared.updateReminder(for: task)
                changed = true
            }
        }

        // Odhlášení z termínu ve STAGu → zkoušku odstraníme (jen budoucí a nesplněné)
        for task in linked where !registeredIDs.contains(task.stagTermID ?? "") && !task.isCompleted && task.dueDate > .now {
            NotificationManager.shared.cancelReminder(for: task)
            context.delete(task)
            changed = true
        }

        if changed { TaskService.save(context) }
    }

    // MARK: - Pomocné

    private func subjectNames(in context: ModelContext) -> [String: String] {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        return Dictionary(subjects.map { ($0.code.uppercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func persist() {
        guard !DemoMode.isActive else { return }
        guard let fetchedAt, let data = try? JSONEncoder().encode(Snapshot(terms: terms, fetchedAt: fetchedAt)) else { return }
        AppGroup.defaults?.set(data, forKey: Keys.snapshot)
    }
}

// Ukázkový režim – data jen v paměti, nic se neukládá
extension ExamTermStore {
    func loadDemo(_ terms: [ExamTerm], newIDs: Set<String>) {
        self.terms = terms
        fetchedAt = .now
        newTermIDs = newIDs
        queuedTermIDs = []
        errorMessage = nil
    }

    /// Po ukončení dema vrátí skutečné termíny z App Group
    func reloadAfterDemo() {
        errorMessage = nil
        restoreFromCache()
    }
}
