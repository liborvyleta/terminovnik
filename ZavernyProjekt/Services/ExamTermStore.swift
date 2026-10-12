import Foundation
import Observation
import SwiftData
import UserNotifications

/// Úložiště termínů zkoušek ze STAGu načtených přes uložený účet.
///
/// Používají ho obrazovky termínů a detail předmětu (přes ``ExamTermStore/shared``) i kontrola na pozadí.
/// Data stahuje z IS/STAG službou z ``StagAccountStore`` a ukládá do sdílených `UserDefaults` App Group,
/// takže termíny fungují i offline.
///
/// - Zapsané termíny se automaticky převádí na zkoušky (`ExamTask` se `stagTermID`) s připomínkou den předem;
///   po odhlášení z termínu ve STAGu se zkouška z aplikace odstraní.
/// - Nově vypsané termíny vyvolají okamžité lokální oznámení (při otevření aplikace i při kontrole na pozadí).
/// - Important: V ukázkovém režimu (``DemoMode``) se nic nestahuje, nezapisuje do STAGu ani neukládá do App Group.
@Observable
final class ExamTermStore {
    /// Sdílená instance používaná celou aplikací.
    static let shared = ExamTermStore()

    /// Klíč přepínače v Nastavení – upozornění na nové termíny (výchozí zapnuto)
    nonisolated static let alertsEnabledKey = "examTermAlertsEnabled"

    /// Všechny termíny z posledního úspěšného načtení (nebo z cache).
    private(set) var terms: [ExamTerm] = []
    /// Čas posledního úspěšného načtení ze STAGu; `nil`, pokud termíny ještě nebyly načteny.
    private(set) var fetchedAt: Date?
    /// Probíhá právě načítání ze STAGu.
    private(set) var isLoading = false
    /// Lokalizovaná chyba posledního načtení pro zobrazení v UI; `nil` při úspěchu.
    private(set) var errorMessage: String?
    /// Termíny objevené při posledních kontrolách, které si uživatel ještě neprohlédl (štítek „Nový“)
    private(set) var newTermIDs: Set<String> = []
    /// Termíny, do jejichž fronty čekatelů se uživatel zapsal z aplikace
    /// (STAG to v seznamu termínů neuvádí – evidujeme lokálně, aby šlo nabídnout odhlášení z fronty)
    private(set) var queuedTermIDs: Set<String> = []
    /// Právě probíhající zápis/odhlášení (pro ProgressView a zablokování dalších akcí)
    private(set) var pendingRegistration: PendingRegistration?

    /// Probíhající změna zápisu na termín.
    ///
    /// Drží ji ``ExamTermStore/pendingRegistration`` po dobu volání STAGu, aby UI mohlo
    /// u daného termínu zobrazit průběh a zablokovat další akce.
    struct PendingRegistration: Equatable {
        /// Identifikátor termínu ve STAGu.
        let termID: String
        /// Prováděná akce (zápis, odhlášení, fronta).
        let action: StagTermRegistrationAction
    }

    /// Jak starý seznam se při otevření aplikace obnoví
    private let maxAge: TimeInterval = 15 * 60

    /// Klíče ve sdílených `UserDefaults` App Group.
    private enum Keys {
        static let snapshot = "examTerms.v1"
        static let seen = "examTerms.seenIDs"
        static let new = "examTerms.newIDs"
        static let queued = "examTerms.queuedIDs"
    }

    /// Uložená podoba seznamu termínů v App Group.
    private struct Snapshot: Codable {
        var terms: [ExamTerm]
        var fetchedAt: Date
    }

    /// Vytvoří úložiště a obnoví termíny z cache v App Group.
    private init() {
        restoreFromCache()
    }

    /// Načte uložené termíny z App Group.
    ///
    /// Obnoví seznam termínů, čas načtení, nové termíny i evidenci front; chybějící nebo nečitelná data
    /// znamenají prázdný seznam.
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

    /// Zapsané termíny (nadcházející), od nejbližšího.
    var registeredTerms: [ExamTerm] {
        terms.filter { $0.isRegistered && $0.isUpcoming() }.sorted { $0.start < $1.start }
    }

    /// Termíny, na které se lze zapsat nebo jsou vypsané (nadcházející, platné, nezapsané), od nejbližšího.
    var availableTerms: [ExamTerm] {
        terms.filter { !$0.isRegistered && !$0.isCancelled && $0.isUpcoming() }.sorted { $0.start < $1.start }
    }

    /// Existují termíny se štítkem „Nový“, které si uživatel ještě neprohlédl.
    var hasNewTerms: Bool { !newTermIDs.isEmpty }

    /// Vrátí nadcházející termíny jednoho předmětu.
    ///
    /// - Parameter code: Kód předmětu (porovnává se bez ohledu na velikost písmen).
    /// - Returns: Nadcházející termíny předmětu seřazené od nejbližšího.
    func terms(forSubject code: String) -> [ExamTerm] {
        terms.filter { $0.subjectCode.caseInsensitiveCompare(code) == .orderedSame && $0.isUpcoming() }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Načítání

    /// Načte termíny ze STAGu, sladí zkoušky v aplikaci a upozorní na nové termíny.
    ///
    /// Asynchronně stáhne termíny studenta, uloží je do App Group, pročistí evidenci front,
    /// promítne zapsané termíny do zkoušek (``ExamTermStore/syncRegisteredTasks(in:)``) a případně
    /// odešle oznámení o nových termínech. Chyby se nevyhazují, ale zapisují do ``ExamTermStore/errorMessage``;
    /// při vypršeném přihlášení se uživatel odhlásí ze STAGu.
    ///
    /// - Parameter context: SwiftData kontext, do kterého se zapisují zkoušky ze zapsaných termínů.
    /// - Returns: Počet nově objevených termínů (0 v ukázkovém režimu, bez přihlášení, při běžícím načítání nebo chybě).
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

    /// Obnoví termíny, pokud je uživatel přihlášený a seznam je starší než 15 minut.
    ///
    /// Asynchronní operace; jinak deleguje na ``ExamTermStore/refresh(context:)``.
    ///
    /// - Parameter context: SwiftData kontext pro sladění zkoušek ze zapsaných termínů.
    func refreshIfNeeded(context: ModelContext) async {
        guard StagAccountStore.shared.isConnected else { return }
        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge { return }
        await refresh(context: context)
    }

    /// Označí všechny nové termíny jako prohlédnuté – zmizí štítek „Nový“.
    ///
    /// V ukázkovém režimu se změní jen stav v paměti, App Group zůstane beze změny.
    func markAllSeen() {
        guard !newTermIDs.isEmpty else { return }
        newTermIDs = []
        guard !DemoMode.isActive else { return }
        AppGroup.defaults?.removeObject(forKey: Keys.new)
    }

    /// Smaže uložené termíny (po odhlášení ze STAGu). Zkoušky v aplikaci zůstávají.
    ///
    /// Vyprázdní stav v paměti a mimo ukázkový režim odstraní i všechna data termínů z App Group.
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

    // MARK: - Zápis na termíny (ostré operace ve STAGu)
    // Volat výhradně po výslovném potvrzení uživatelem v dialogu.

    /// Zapíše studenta na termín.
    ///
    /// Asynchronní operace; deleguje na ``ExamTermStore/changeRegistration(_:for:context:)``.
    ///
    /// - Parameters:
    ///   - term: Termín, na který se student zapisuje.
    ///   - context: SwiftData kontext pro sladění zkoušek po obnovení termínů.
    /// - Returns: Výsledek operace ve STAGu.
    /// - Important: Ostrá změna ve STAGu – volat jen po výslovném potvrzení uživatelem.
    func register(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.register, for: term, context: context)
    }

    /// Odhlásí studenta z termínu.
    ///
    /// Asynchronní operace; deleguje na ``ExamTermStore/changeRegistration(_:for:context:)``.
    ///
    /// - Parameters:
    ///   - term: Termín, ze kterého se student odhlašuje.
    ///   - context: SwiftData kontext pro sladění zkoušek po obnovení termínů.
    /// - Returns: Výsledek operace ve STAGu.
    /// - Important: Ostrá změna ve STAGu – volat jen po výslovném potvrzení uživatelem.
    func unregister(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.unregister, for: term, context: context)
    }

    /// Zapíše studenta do fronty čekatelů na plný termín.
    ///
    /// Asynchronní operace; deleguje na ``ExamTermStore/changeRegistration(_:for:context:)``.
    ///
    /// - Parameters:
    ///   - term: Plný termín, do jehož fronty se student zapisuje.
    ///   - context: SwiftData kontext pro sladění zkoušek po obnovení termínů.
    /// - Returns: Výsledek operace ve STAGu.
    /// - Important: Ostrá změna ve STAGu – volat jen po výslovném potvrzení uživatelem.
    func joinQueue(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.joinQueue, for: term, context: context)
    }

    /// Odhlásí studenta z fronty čekatelů.
    ///
    /// Asynchronní operace; deleguje na ``ExamTermStore/changeRegistration(_:for:context:)``.
    ///
    /// - Parameters:
    ///   - term: Termín, z jehož fronty se student odhlašuje.
    ///   - context: SwiftData kontext pro sladění zkoušek po obnovení termínů.
    /// - Returns: Výsledek operace ve STAGu.
    /// - Important: Ostrá změna ve STAGu – volat jen po výslovném potvrzení uživatelem.
    func leaveQueue(_ term: ExamTerm, context: ModelContext) async -> StagTermRegistrationResult {
        await changeRegistration(.leaveQueue, for: term, context: context)
    }

    /// Zjistí, zda je student (podle lokální evidence) ve frontě čekatelů na termín.
    ///
    /// - Parameter term: Kontrolovaný termín.
    /// - Returns: `true`, pokud se uživatel do fronty zapsal z aplikace a fronta je stále platná.
    func isQueued(_ term: ExamTerm) -> Bool { queuedTermIDs.contains(term.id) }

    /// Provede změnu zápisu ve STAGu; po úspěchu obnoví termíny (zapsané se samy převedou na zkoušky s připomínkou).
    ///
    /// Asynchronní operace. Najednou může běžet jen jedna změna (``ExamTermStore/pendingRegistration``).
    /// Po úspěchu aktualizuje lokální evidenci front; termíny se obnoví po úspěchu i neúspěchu.
    /// Chyby se nevyhazují, ale vrací jako `.failure` se zprávou; při vypršeném přihlášení se uživatel odhlásí.
    ///
    /// - Parameters:
    ///   - action: Požadovaná akce (zápis, odhlášení, vstup do fronty, odchod z fronty).
    ///   - term: Termín, kterého se změna týká.
    ///   - context: SwiftData kontext pro sladění zkoušek po obnovení termínů.
    /// - Returns: Výsledek operace ve STAGu nebo `.failure` s lokalizovaným popisem chyby.
    /// - Important: Ostrá změna ve STAGu – volat jen po výslovném potvrzení uživatelem.
    ///   V ukázkovém režimu se nic nezapisuje a vrací se `.failure`.
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

    /// Odebere z evidence front termíny, které zmizely, proběhly nebo na které už je student zapsaný.
    ///
    /// Fronta u takových termínů nedává smysl; změna se uloží jen tehdy, když se evidence opravdu změnila.
    private func pruneQueuedTerms() {
        let valid = Set(terms.filter { !$0.isRegistered && $0.isUpcoming() }.map(\.id))
        let pruned = queuedTermIDs.intersection(valid)
        guard pruned != queuedTermIDs else { return }
        queuedTermIDs = pruned
        persistQueued()
    }

    /// Uloží evidenci front do App Group (v ukázkovém režimu nic neukládá).
    private func persistQueued() {
        guard !DemoMode.isActive else { return }
        AppGroup.defaults?.set(Array(queuedTermIDs), forKey: Keys.queued)
    }

    // MARK: - Nové termíny

    /// Vrátí nově objevené vypsané termíny. Při úplně prvním načtení nic nehlásí (jinak by zasypal uživatele).
    ///
    /// Všechny načtené termíny přidá do množiny již viděných v App Group a nové zapíše
    /// do ``ExamTermStore/newTermIDs``.
    ///
    /// - Parameter fresh: Právě stažené termíny ze STAGu.
    /// - Returns: Nadcházející, nezrušené a nezapsané termíny, které dosud nebyly viděny.
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

    /// Odešle okamžité lokální oznámení o nových termínech (víc termínů = jedno souhrnné oznámení).
    ///
    /// Asynchronně přidá požadavek do `UNUserNotificationCenter`; nic nedělá, pokud uživatel
    /// upozornění vypnul v Nastavení (``ExamTermStore/alertsEnabledKey``). Chyba přidání se ignoruje.
    ///
    /// - Parameters:
    ///   - discovered: Nově objevené termíny (alespoň jeden).
    ///   - context: SwiftData kontext pro dohledání názvů předmětů.
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
    ///
    /// Nové zkoušky přiřadí k předmětu podle kódu, u existujících udržuje aktuální datum a poznámku
    /// a přeplánuje připomínky přes `NotificationManager`. Zkoušky termínů, ze kterých se student odhlásil,
    /// smaže jen pokud jsou budoucí a nesplněné. Změny uloží přes `TaskService.save(_:)`.
    ///
    /// - Parameter context: SwiftData kontext se zkouškami a předměty.
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

    /// Vrátí názvy předmětů z aplikace indexované kódem.
    ///
    /// - Parameter context: SwiftData kontext s předměty.
    /// - Returns: Slovník kód předmětu (velkými písmeny) → název; při chybě načtení prázdný.
    private func subjectNames(in context: ModelContext) -> [String: String] {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        return Dictionary(subjects.map { ($0.code.uppercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Uloží aktuální termíny a čas načtení do App Group (v ukázkovém režimu nic neukládá).
    private func persist() {
        guard !DemoMode.isActive else { return }
        guard let fetchedAt, let data = try? JSONEncoder().encode(Snapshot(terms: terms, fetchedAt: fetchedAt)) else { return }
        AppGroup.defaults?.set(data, forKey: Keys.snapshot)
    }
}

// Ukázkový režim – data jen v paměti, nic se neukládá
extension ExamTermStore {
    /// Nahradí termíny ukázkovými daty pro ukázkový režim.
    ///
    /// - Parameters:
    ///   - terms: Ukázkové termíny.
    ///   - newIDs: Identifikátory termínů, které se mají zobrazit se štítkem „Nový“.
    /// - Important: Data zůstávají jen v paměti, do App Group se nic neukládá.
    func loadDemo(_ terms: [ExamTerm], newIDs: Set<String>) {
        self.terms = terms
        fetchedAt = .now
        newTermIDs = newIDs
        queuedTermIDs = []
        errorMessage = nil
    }

    /// Po ukončení dema vrátí skutečné termíny z App Group.
    func reloadAfterDemo() {
        errorMessage = nil
        restoreFromCache()
    }
}
