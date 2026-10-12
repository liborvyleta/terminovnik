import Foundation
import Observation
import SwiftData
import SwiftUI

/// Co má záložka Zkoušky právě zobrazit.
///
/// Stav odvozuje ``ExamTermsViewModel/screenState`` z dat `ExamTermStore` a připojení účtu STAG; View podle něj volí mezi výzvou k připojení, načítáním, chybou, prázdným stavem a seznamem termínů.
enum ExamTermsScreenState: Equatable {
    /// Účet STAG není připojený (volitelně s důvodem, např. vypršelé přihlášení)
    case notConnected(message: String?)
    /// Termíny se poprvé načítají
    case loading
    /// Načtení selhalo a nemáme žádná uložená data
    case failed(String)
    /// Žádné zapsané ani vypsané termíny
    case empty
    /// Termíny jsou k dispozici
    case ready
}

/// Přepínač v horní části záložky Zkoušky: zapsané × vypsané termíny.
///
/// Hodnotu drží ``ExamTermsViewModel/segment``; používá se v segmentovém pickeru obrazovky termínů.
enum ExamTermsSegment: String, CaseIterable, Identifiable {
    case registered
    case available

    /// Identifikátor pro `ForEach` – samotná hodnota výčtu.
    var id: Self { self }

    /// Lokalizovaný název segmentu zobrazovaný v pickeru.
    var title: String {
        switch self {
        case .registered: String(localized: "Zapsané", comment: "Segment: zapsané termíny")
        case .available: String(localized: "Vypsané", comment: "Segment: vypsané termíny")
        }
    }
}

/// Vypsané termíny jednoho předmětu.
///
/// Skupinu sestavuje ``ExamTermsViewModel/availableGroups`` – kód předmětu (velkými písmeny) a jeho termíny seřazené od nejbližšího. Zobrazuje se jako sekce v segmentu Vypsané.
nonisolated struct ExamTermGroup: Identifiable, Hashable {
    let subjectCode: String
    let terms: [ExamTerm]
    /// Identifikátor skupiny – kód předmětu.
    var id: String { subjectCode }
}

/// Stav přihlašování na termín (pro řádek a detail).
///
/// Vypočítá ho ``ExamTermsViewModel/registrationWindow(_:now:)`` z dat otevření a uzávěrky přihlašování ze STAGu.
enum ExamTermRegistrationWindow: Equatable {
    /// Přihlašování ještě nezačalo
    case opensLater(opens: Date, deadline: Date?)
    /// Přihlásit se lze (do uzávěrky, pokud je známá)
    case open(deadline: Date?)
    /// Uzávěrka přihlašování už minula
    case closed(deadline: Date)

    /// Název SF Symbolu odpovídající stavu přihlašování.
    var symbol: String {
        switch self {
        case .opensLater: "lock.badge.clock"
        case .open: "person.crop.circle.badge.plus"
        case .closed: "lock.fill"
        }
    }
}

/// ViewModel záložky Zkoušky.
///
/// Vybírá data z `ExamTermStore` (zapsané termíny, vypsané seskupené po předmětech, nové termíny) a `StagAccountStore` (připojení účtu), připravuje texty pro řádky a detail a provádí akce obnovení, zápisu/odhlášení a označení nových termínů jako zobrazených. Názvy a barvy předmětů bere z předmětů v aplikaci, záložně z `TimetableStore`. Pro náhledy a snímky obrazovky lze vstříknout vlastní termíny – pak se nikdy nevolá síť.
@Observable
final class ExamTermsViewModel {
    /// Náhledový režim – data jsou vstříknutá, síť se nevolá.
    let isPreview: Bool
    /// V náhledu se zápis jen simuluje (mění se vstříknuté termíny), proto `var`.
    private var previewTerms: [ExamTerm]?
    /// Termíny, u kterých je student v náhledu „ve frontě“.
    private var previewQueuedIDs: Set<String> = []
    /// Simulovaná probíhající změna zápisu v náhledu.
    private var previewPending: ExamTermStore.PendingRegistration?
    /// Termíny se štítkem „Nový“ v náhledu.
    private let previewNewTermIDs: Set<String>
    /// Čas posledního načtení v náhledu.
    private let previewFetchedAt: Date?

    /// Ručně zvolený segment; `nil` = automaticky (Zapsané, pokud nějaké jsou).
    private var chosenSegment: ExamTermsSegment?

    /// Vytvoří ViewModel v ostrém režimu – data z `ExamTermStore.shared`.
    init() {
        isPreview = false
        previewTerms = nil
        previewNewTermIDs = []
        previewFetchedAt = nil
    }

    /// Vytvoří ViewModel v náhledovém režimu pro #Preview a snímky obrazovky.
    /// - Parameters:
    ///   - previewTerms: Zobrazené termíny; `nil` = nepřipojený účet.
    ///   - newTermIDs: Termíny se štítkem „Nový“.
    ///   - fetchedAt: Čas posledního načtení (patička „Aktualizováno…“); při `previewTerms == nil` se ignoruje.
    init(previewTerms: [ExamTerm]?, newTermIDs: Set<String> = [], fetchedAt: Date? = .now.addingTimeInterval(-4 * 60)) {
        isPreview = true
        self.previewTerms = previewTerms
        previewNewTermIDs = newTermIDs
        previewFetchedAt = previewTerms == nil ? nil : fetchedAt
    }

    // MARK: - Data ze store

    /// Všechny termíny – vstříknuté v náhledu, jinak z `ExamTermStore`.
    var terms: [ExamTerm] {
        isPreview ? (previewTerms ?? []) : ExamTermStore.shared.terms
    }

    /// Zapsané nadcházející termíny od nejbližšího (i zrušené – student o nich musí vědět).
    var registeredTerms: [ExamTerm] {
        isPreview
            ? terms.filter { $0.isRegistered && $0.isUpcoming() }.sorted { $0.start < $1.start }
            : ExamTermStore.shared.registeredTerms
    }

    /// Vypsané nadcházející termíny bez zrušených, na které student není zapsaný.
    var availableTerms: [ExamTerm] {
        isPreview
            ? terms.filter { !$0.isRegistered && !$0.isCancelled && $0.isUpcoming() }.sorted { $0.start < $1.start }
            : ExamTermStore.shared.availableTerms
    }

    /// Identifikátory termínů, které se mají označit štítkem „Nový“.
    var newTermIDs: Set<String> {
        isPreview ? previewNewTermIDs : ExamTermStore.shared.newTermIDs
    }

    /// Příznak, zda je účet STAG připojený (v náhledu podle toho, zda jsou vstříknuté termíny).
    var isConnected: Bool {
        isPreview ? previewTerms != nil : StagAccountStore.shared.isConnected
    }

    /// Příznak probíhajícího načítání termínů (v náhledu vždy `false`).
    var isLoading: Bool {
        isPreview ? false : ExamTermStore.shared.isLoading
    }

    /// Chybová hláška posledního načtení (v náhledu vždy `nil`).
    var errorMessage: String? {
        isPreview ? nil : ExamTermStore.shared.errorMessage
    }

    /// Čas posledního úspěšného načtení termínů.
    var fetchedAt: Date? {
        isPreview ? previewFetchedAt : ExamTermStore.shared.fetchedAt
    }

    /// Zjistí, zda je termín nový.
    /// - Parameter term: Testovaný termín.
    /// - Returns: `true`, pokud je termín v ``newTermIDs``.
    func isNew(_ term: ExamTerm) -> Bool { newTermIDs.contains(term.id) }

    /// Aktuální podoba termínu (po zápisu/obnovení se mění) – záložně ta předaná.
    /// - Parameter term: Termín, jehož aktuální verzi hledáme.
    /// - Returns: Termín se stejným `id` z ``terms``, nebo předaný termín.
    func latest(_ term: ExamTerm) -> ExamTerm {
        terms.first { $0.id == term.id } ?? term
    }

    /// Zjistí, zda je student ve frontě čekatelů (zapsal se do ní z aplikace).
    /// - Parameter term: Testovaný termín.
    /// - Returns: `true`, pokud je student ve frontě.
    func isQueued(_ term: ExamTerm) -> Bool {
        isPreview ? previewQueuedIDs.contains(term.id) : ExamTermStore.shared.isQueued(term)
    }

    /// Právě probíhající změna zápisu.
    var pendingRegistration: ExamTermStore.PendingRegistration? {
        isPreview ? previewPending : ExamTermStore.shared.pendingRegistration
    }

    /// Zjistí, zda u termínu právě probíhá změna zápisu.
    /// - Parameter term: Testovaný termín.
    /// - Returns: `true`, pokud se ``pendingRegistration`` týká tohoto termínu.
    func isRegistrationPending(_ term: ExamTerm) -> Bool { pendingRegistration?.termID == term.id }

    /// Akce, kterou lze u termínu nabídnout (zápis / odhlášení / fronta).
    /// - Parameters:
    ///   - term: Termín.
    ///   - now: Referenční okamžik.
    /// - Returns: Nabízená akce, nebo `nil`, pokud žádná nedává smysl.
    func registrationAction(for term: ExamTerm, now: Date = .now) -> StagTermRegistrationAction? {
        Self.registrationAction(for: term, isQueued: isQueued(term), now: now)
    }

    /// Počet nových vypsaných termínů (štítek u segmentu).
    var newAvailableCount: Int { availableTerms.filter(isNew).count }

    /// Vypsané termíny seskupené po předmětech; předměty podle nejbližšího termínu.
    var availableGroups: [ExamTermGroup] {
        let grouped = Dictionary(grouping: availableTerms) { $0.subjectCode.uppercased() }
        return grouped
            .map { ExamTermGroup(subjectCode: $0.key, terms: $0.value.sorted { $0.start < $1.start }) }
            .sorted { ($0.terms.first?.start ?? .distantFuture) < ($1.terms.first?.start ?? .distantFuture) }
    }

    /// Příznak, zda existuje aspoň jeden zapsaný nebo vypsaný termín.
    var hasTerms: Bool { !registeredTerms.isEmpty || !availableTerms.isEmpty }

    /// Stav obrazovky odvozený z termínů, připojení, načítání a chyby.
    var screenState: ExamTermsScreenState {
        if hasTerms { return .ready }
        if !isConnected { return .notConnected(message: errorMessage) }
        if isLoading { return .loading }
        if let errorMessage { return .failed(errorMessage) }
        // Připojeno, ale termíny ještě nedorazily – .task je právě načítá
        if fetchedAt == nil { return .loading }
        return .empty
    }

    /// Zvolený segment – dokud uživatel nevybere sám, ukazujeme Zapsané (jsou-li nějaké).
    var segment: ExamTermsSegment {
        get { chosenSegment ?? (registeredTerms.isEmpty ? .available : .registered) }
        set { chosenSegment = newValue }
    }

    // MARK: - Akce

    /// Vynuceně znovu načte termíny ze STAGu (v náhledu nic nedělá).
    /// - Parameter context: SwiftData kontext předávaný do `ExamTermStore`.
    func refresh(context: ModelContext) async {
        guard !isPreview else { return }
        await ExamTermStore.shared.refresh(context: context)
    }

    /// Načte termíny ze STAGu, pokud to `ExamTermStore` považuje za potřebné (v náhledu nic nedělá).
    /// - Parameter context: SwiftData kontext předávaný do `ExamTermStore`.
    func refreshIfNeeded(context: ModelContext) async {
        guard !isPreview else { return }
        await ExamTermStore.shared.refreshIfNeeded(context: context)
    }

    /// Provede změnu zápisu ve STAGu – OSTRÁ operace, volat jen po potvrzení uživatelem v dialogu.
    ///
    /// V náhledovém režimu se nic neposílá, změna se po sekundové pauze jen nasimuluje na vstříknutých termínech.
    /// - Parameters:
    ///   - action: Požadovaná akce (zápis, odhlášení, fronta).
    ///   - term: Termín, kterého se akce týká.
    ///   - context: SwiftData kontext předávaný do `ExamTermStore`.
    /// - Returns: Výsledek operace; v náhledu vždy `.success`.
    func performRegistration(_ action: StagTermRegistrationAction, for term: ExamTerm,
                             context: ModelContext) async -> StagTermRegistrationResult {
        guard isPreview else {
            return await ExamTermStore.shared.changeRegistration(action, for: term, context: context)
        }
        previewPending = ExamTermStore.PendingRegistration(termID: term.id, action: action)
        defer { previewPending = nil }
        try? await Task.sleep(for: .seconds(1))
        simulatePreview(action, for: term)
        return .success
    }

    /// Nasimuluje změnu zápisu na vstříknutých náhledových termínech.
    ///
    /// U fronty jen upraví množinu termínů ve frontě, u zápisu/odhlášení přepíše termín s novým stavem a obsazeností.
    /// - Parameters:
    ///   - action: Simulovaná akce.
    ///   - term: Termín, kterého se akce týká.
    private func simulatePreview(_ action: StagTermRegistrationAction, for term: ExamTerm) {
        switch action {
        case .joinQueue: previewQueuedIDs.insert(term.id); return
        case .leaveQueue: previewQueuedIDs.remove(term.id); return
        case .register, .unregister: break
        }
        guard let index = previewTerms?.firstIndex(where: { $0.id == term.id }), let old = previewTerms?[index] else { return }
        let registering = action == .register
        previewTerms?[index] = ExamTerm(
            id: old.id, subjectCode: old.subjectCode, department: old.department, typeName: old.typeName,
            start: old.start, end: old.end, room: old.room, teacher: old.teacher,
            occupied: old.occupied.map { max(0, $0 + (registering ? 1 : -1)) }, capacity: old.capacity,
            isRegistered: registering, canChangeRegistration: old.canChangeRegistration, blockReason: old.blockReason,
            registrationOpens: old.registrationOpens, registrationDeadline: old.registrationDeadline,
            unregisterDeadline: old.unregisterDeadline, isRetake: old.isRetake, note: old.note, isCancelled: old.isCancelled
        )
    }

    /// Uživatel si nové termíny prohlédl – štítky „Nový“ zmizí (v náhledu nic nedělá).
    func markAllSeen() {
        guard !isPreview else { return }
        ExamTermStore.shared.markAllSeen()
    }

    // MARK: - Předměty (název a barva)

    /// Názvy a barvy předmětů z rozvrhu – záloha, když předmět v aplikaci chybí.
    private var timetableSubjects: [String: (name: String, hex: String?)] {
        let events = isPreview ? TimetableSnapshot.sample.events : TimetableStore.shared.events
        var result: [String: (name: String, hex: String?)] = [:]
        for event in events where result[event.subjectCode.uppercased()] == nil {
            result[event.subjectCode.uppercased()] = (event.subjectName, event.hexColor)
        }
        return result
    }

    /// Název předmětu: z předmětů v aplikaci, záložně z rozvrhu.
    /// - Parameters:
    ///   - code: Kód předmětu ze STAGu (porovnává se bez ohledu na velikost písmen).
    ///   - subjects: Předměty uložené v aplikaci.
    /// - Returns: Název předmětu, nebo `nil`, pokud není znám.
    func subjectName(for code: String, subjects: [Subject]) -> String? {
        let key = code.uppercased()
        if let subject = subjects.first(where: { $0.code.uppercased() == key }), !subject.name.isEmpty {
            return subject.name
        }
        return timetableSubjects[key]?.name
    }

    /// Barva předmětu: z aplikace, záložně z rozvrhu, jinak deterministicky z palety.
    /// - Parameters:
    ///   - code: Kód předmětu ze STAGu.
    ///   - subjects: Předměty uložené v aplikaci.
    /// - Returns: Barva pro zvýraznění termínu.
    func tint(for code: String, subjects: [Subject]) -> Color {
        let key = code.uppercased()
        if let subject = subjects.first(where: { $0.code.uppercased() == key }) {
            return subject.color
        }
        if let hex = timetableSubjects[key]?.hex, !hex.isEmpty {
            return Color(hex: hex)
        }
        let seed = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: SubjectPalette.hex(seed))
    }

    // MARK: - Texty

    /// Text patičky ve tvaru „Aktualizováno před 5 min“.
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Text patičky, nebo `nil`, pokud termíny ještě nebyly načteny.
    func footerText(now: Date) -> String? {
        guard let fetchedAt else { return nil }
        let updated = TimetableViewModel.relativeText(since: fetchedAt, now: now)
        return String(localized: "Aktualizováno \(updated)")
    }

    /// Krátké datum ve tvaru „út 14. 10.“.
    /// - Parameter date: Datum k naformátování.
    /// - Returns: Naformátovaný text v češtině.
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.defaultDigits).locale(.czech))
    }

    /// Dlouhé datum ve tvaru „Úterý 14. října“ (s velkým počátečním písmenem).
    /// - Parameter date: Datum k naformátování.
    /// - Returns: Naformátovaný text v češtině.
    static func longDayText(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Časové rozmezí „9:00–11:00“, bez (platného) konce jen „9:00“.
    /// - Parameter term: Termín.
    /// - Returns: Text času.
    static func timeText(_ term: ExamTerm) -> String {
        guard let end = term.end, end > term.start else { return TimetableViewModel.time(term.start) }
        return "\(TimetableViewModel.time(term.start))–\(TimetableViewModel.time(end))"
    }

    /// Délka termínu ve tvaru „2 h“ nebo „1 h 30 min“.
    /// - Parameter term: Termín.
    /// - Returns: Text délky, nebo `nil`, pokud konec chybí nebo není po začátku.
    static func durationText(_ term: ExamTerm) -> String? {
        guard let end = term.end, end > term.start else { return nil }
        return TimetableViewModel.durationText(minutes: Int(end.timeIntervalSince(term.start) / 60))
    }

    /// Typ termínu: „Zkouška“, u opravného „Zkouška · opravný“.
    /// - Parameter term: Termín.
    /// - Returns: Text typu.
    static func typeText(_ term: ExamTerm) -> String {
        term.isRetake ? String(localized: "\(term.typeName) · opravný", comment: "Typ termínu ze STAGu + opravný termín") : term.typeName
    }

    /// Ikona typu termínu.
    /// - Parameter term: Termín.
    /// - Returns: Název SF Symbolu – pečeť pro zápočet, jinak čepice.
    static func symbol(for term: ExamTerm) -> String {
        term.taskType == .zapocet ? "checkmark.seal.fill" : "graduationcap.fill"
    }

    /// Obsazenost: „14/20 · volno 6“, „Plno · 18/18“, „7 zapsaných“.
    /// - Parameter term: Termín.
    /// - Returns: Text obsazenosti, nebo `nil`, pokud počet zapsaných není znám.
    static func occupancyText(_ term: ExamTerm) -> String? {
        switch (term.occupied, term.capacity) {
        case let (occupied?, capacity?):
            let free = term.freeSpots ?? 0
            return term.isFull
                ? String(localized: "Plno · \(occupied)/\(capacity)")
                : String(localized: "\(occupied)/\(capacity) · volno \(free)", comment: "Obsazenost termínu a počet volných míst")
        case let (occupied?, nil):
            return String(localized: "\(occupied) zapsaných", comment: "Počet studentů zapsaných na termín")
        default:
            return nil
        }
    }

    /// Zaplněnost termínu v rozsahu 0…1.
    /// - Parameter term: Termín.
    /// - Returns: Podíl obsazených míst, nebo `nil`, když je kapacita neznámá.
    static func occupancyFraction(_ term: ExamTerm) -> Double? {
        guard let occupied = term.occupied, let capacity = term.capacity, capacity > 0 else { return nil }
        return min(max(Double(occupied) / Double(capacity), 0), 1)
    }

    /// Barva obsazenosti: plno červeně, skoro plno (od 80 %) oranžově, jinak zeleně.
    /// - Parameter term: Termín.
    /// - Returns: Barva indikátoru.
    static func occupancyColor(_ term: ExamTerm) -> Color {
        if term.isFull { return .red }
        if let fraction = occupancyFraction(term), fraction >= 0.8 { return .orange }
        return .green
    }

    /// Určí stav přihlašování podle data otevření a uzávěrky.
    /// - Parameters:
    ///   - term: Termín.
    ///   - now: Referenční okamžik.
    /// - Returns: Stav přihlašování, nebo `nil`, pokud STAG neuvádí žádné z dat.
    static func registrationWindow(_ term: ExamTerm, now: Date = .now) -> ExamTermRegistrationWindow? {
        if let opens = term.registrationOpens, opens > now {
            return .opensLater(opens: opens, deadline: term.registrationDeadline)
        }
        if let deadline = term.registrationDeadline {
            return deadline > now ? .open(deadline: deadline) : .closed(deadline: deadline)
        }
        return term.registrationOpens == nil ? nil : .open(deadline: nil)
    }

    /// „Přihlašování od čt 8. 10. 8:00 do so 12. 10. 23:00“ / „Přihlásit se můžeš do …“ / „Přihlašování skončilo“.
    /// - Parameters:
    ///   - term: Termín.
    ///   - now: Referenční okamžik.
    /// - Returns: Popis stavu přihlašování, nebo `nil`, pokud není znám.
    static func registrationText(_ term: ExamTerm, now: Date = .now) -> String? {
        switch registrationWindow(term, now: now) {
        case let .opensLater(opens, deadline)?:
            let from = opens.deadlineFormatted
            guard let deadline else { return String(localized: "Přihlašování od \(from)") }
            let to = deadline.deadlineFormatted
            return String(localized: "Přihlašování od \(from) do \(to)")
        case let .open(deadline?)?:
            return String(localized: "Přihlásit se můžeš do \(deadline.deadlineFormatted)")
        case .open(nil)?:
            return String(localized: "Přihlašování je otevřené")
        case .closed?:
            return String(localized: "Přihlašování skončilo")
        case nil:
            return nil
        }
    }

    /// Zjistí, zda uzávěrka přihlašování je do 2 dnů – zvýrazníme ji.
    /// - Parameters:
    ///   - term: Termín.
    ///   - now: Referenční okamžik.
    /// - Returns: `true`, pokud je přihlašování otevřené a uzávěrka je za méně než 2 dny.
    static func isRegistrationClosingSoon(_ term: ExamTerm, now: Date = .now) -> Bool {
        guard case let .open(deadline?)? = registrationWindow(term, now: now) else { return false }
        return deadline.timeIntervalSince(now) < 2 * 24 * 60 * 60
    }

    /// „Odhlásit se lze do po 13. 10. 12:00“ / „Odhlásit se už nelze“.
    /// - Parameters:
    ///   - term: Termín.
    ///   - now: Referenční okamžik.
    /// - Returns: Text o odhlašování, nebo `nil`, pokud uzávěrka odhlášení není známá.
    static func unregisterText(_ term: ExamTerm, now: Date = .now) -> String? {
        guard let deadline = term.unregisterDeadline else { return nil }
        return deadline > now
            ? String(localized: "Odhlásit se lze do \(deadline.deadlineFormatted)")
            : String(localized: "Odhlásit se už nelze")
    }

    /// Důvod, proč se nelze zapsat (jen když nějaký STAG uvedl).
    /// - Parameter term: Termín.
    /// - Returns: Oříznutý důvod, nebo `nil`, pokud změna zápisu je povolená nebo důvod chybí.
    static func blockReasonText(_ term: ExamTerm) -> String? {
        guard !term.canChangeRegistration, let reason = term.blockReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return nil }
        return reason
    }

    /// Odpočet do termínu: „Za 9 dní“, „Zítra“, „Dnes v 9:00“.
    /// - Parameters:
    ///   - term: Termín.
    ///   - now: Referenční okamžik.
    /// - Returns: Text odpočtu.
    static func countdownText(_ term: ExamTerm, now: Date = .now) -> String {
        term.start.calendarDays(from: now) == 0
            ? String(localized: "Dnes v \(TimetableViewModel.time(term.start))")
            : Countdown.text(for: term.start, now: now)
    }

    // MARK: - Zápis na termín

    /// Která akce dává u termínu smysl: zapsaný → odhlásit, ve frontě → opustit frontu, plný → zapsat do fronty, jinak zapsat.
    ///
    /// Proběhlé a zrušené (nezapsané) termíny nic nenabízí.
    /// - Parameters:
    ///   - term: Termín.
    ///   - isQueued: Zda je student ve frontě čekatelů.
    ///   - now: Referenční okamžik.
    /// - Returns: Nabízená akce, nebo `nil`.
    static func registrationAction(for term: ExamTerm, isQueued: Bool, now: Date = .now) -> StagTermRegistrationAction? {
        guard term.isUpcoming(now: now) else { return nil }
        if term.isRegistered { return .unregister }
        if term.isCancelled { return nil }
        if isQueued { return .leaveQueue }
        return term.isFull ? .joinQueue : .register
    }

    /// Akce je povolená jen tehdy, když STAG změnu zápisu dovoluje (`lzeZapsatOdepsat`).
    ///
    /// Opuštění fronty necháváme vždy – rozhodne STAG a případný důvod ukážeme.
    /// - Parameters:
    ///   - action: Posuzovaná akce.
    ///   - term: Termín.
    /// - Returns: `true`, pokud má být tlačítko akce aktivní.
    static func isRegistrationActionEnabled(_ action: StagTermRegistrationAction, term: ExamTerm) -> Bool {
        action == .leaveQueue || term.canChangeRegistration
    }

    /// Shrnutí v potvrzovacím dialogu: předmět, typ, datum a čas, místnost + upozornění na změnu ve STAGu.
    /// - Parameters:
    ///   - action: Potvrzovaná akce.
    ///   - term: Termín.
    ///   - subjectName: Název předmětu, je-li znám.
    /// - Returns: Víceřádkový text zprávy dialogu.
    static func confirmationMessage(_ action: StagTermRegistrationAction, term: ExamTerm, subjectName: String?) -> String {
        var lines = [
            subjectName.map { "\(term.subjectCode) – \($0)" } ?? term.subjectCode,
            typeText(term),
            "\(longDayText(term.start)), \(timeText(term))"
        ]
        if let room = term.room, !room.isEmpty {
            lines.append(String(localized: "Místnost \(room)", comment: "Potvrzení zápisu: místnost termínu"))
        }
        lines.append("")
        lines.append(action.warningText)
        return lines.joined(separator: "\n")
    }

    /// Kód budovy z místnosti STAGu: „52/202“ → „52“ (bez lomítka nil – nevíme, co je budova).
    /// - Parameter room: Označení místnosti ze STAGu.
    /// - Returns: Kód budovy, nebo `nil`.
    static func buildingCode(from room: String?) -> String? {
        guard let room = room?.trimmingCharacters(in: .whitespaces), let slash = room.firstIndex(of: "/") else { return nil }
        let code = room[..<slash].trimmingCharacters(in: .whitespaces)
        return code.isEmpty ? nil : code
    }

    /// Počet termínů jako lokalizovaný text, např. „3 termíny“.
    /// - Parameter count: Počet termínů.
    /// - Returns: Lokalizovaný text s počtem.
    static func termCountText(_ count: Int) -> String {
        String(localized: "\(count) termínů", comment: "Počet termínů")
    }
}

// MARK: - Texty akcí zápisu

/// Texty a ikony akcí zápisu na termín pro UI.
///
/// Popisky tlačítek, potvrzovacích dialogů, upozornění a hlášek, které používají obrazovky termínů spolu s ``ExamTermsViewModel``.
extension StagTermRegistrationAction {
    /// Popisek tlačítka a položky kontextové nabídky.
    var title: String {
        switch self {
        case .register: String(localized: "Zapsat se na termín")
        case .unregister: String(localized: "Odhlásit se z termínu")
        case .joinQueue: String(localized: "Zapsat se do fronty")
        case .leaveQueue: String(localized: "Odhlásit se z fronty")
        }
    }

    /// Název SF Symbolu pro tlačítko akce.
    var symbol: String {
        switch self {
        case .register: "person.crop.circle.badge.plus"
        case .unregister: "person.crop.circle.badge.minus"
        case .joinQueue: "person.3.sequence.fill"
        case .leaveQueue: "person.crop.circle.badge.xmark"
        }
    }

    /// Odhlášení je destruktivní (místo může obsadit někdo jiný).
    var isDestructive: Bool { self == .unregister || self == .leaveQueue }

    /// Nadpis potvrzovacího dialogu.
    var confirmationTitle: String {
        switch self {
        case .register: String(localized: "Zapsat se na tento termín?")
        case .unregister: String(localized: "Odhlásit se z tohoto termínu?")
        case .joinQueue: String(localized: "Zapsat se do fronty čekatelů?")
        case .leaveQueue: String(localized: "Odhlásit se z fronty čekatelů?")
        }
    }

    /// Tlačítko v potvrzovacím dialogu.
    var confirmButtonTitle: String {
        switch self {
        case .register: String(localized: "Zapsat se")
        case .unregister: String(localized: "Odhlásit se")
        case .joinQueue: String(localized: "Zapsat do fronty")
        case .leaveQueue: String(localized: "Opustit frontu")
        }
    }

    /// Upozornění v dialogu – jde o ostrou změnu ve STAGu.
    var warningText: String {
        switch self {
        case .register:
            String(localized: "Zápis proběhne přímo v IS/STAG. Odhlásit se půjde jen do termínu odhlašování.")
        case .unregister:
            String(localized: "Odhlášení proběhne přímo v IS/STAG. Uvolněné místo může hned obsadit někdo jiný.")
        case .joinQueue:
            String(localized: "Zápis do fronty proběhne přímo v IS/STAG. Na samotný termín tím zapsaný nejsi – sleduj, jestli se uvolní místo.")
        case .leaveQueue:
            String(localized: "Odhlášení z fronty proběhne přímo v IS/STAG. O pořadí ve frontě přijdeš.")
        }
    }

    /// Hláška po úspěchu.
    var successText: String {
        switch self {
        case .register: String(localized: "Jsi zapsaný na termín. Zkoušku s připomínkou najdeš v Přehledu.")
        case .unregister: String(localized: "Z termínu jsi odhlášený.")
        case .joinQueue: String(localized: "Jsi ve frontě čekatelů na termín.")
        case .leaveQueue: String(localized: "Z fronty čekatelů jsi odhlášený.")
        }
    }

    /// Text při probíhající akci.
    var progressText: String {
        switch self {
        case .register: String(localized: "Zapisuji na termín…")
        case .unregister: String(localized: "Odhlašuji z termínu…")
        case .joinQueue: String(localized: "Zapisuji do fronty…")
        case .leaveQueue: String(localized: "Odhlašuji z fronty…")
        }
    }
}
