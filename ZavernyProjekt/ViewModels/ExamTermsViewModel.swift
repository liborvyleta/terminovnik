import Foundation
import Observation
import SwiftData
import SwiftUI

/// Co má záložka Zkoušky právě zobrazit
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

/// Přepínač nahoře: zapsané × vypsané termíny
enum ExamTermsSegment: String, CaseIterable, Identifiable {
    case registered
    case available

    var id: Self { self }

    var title: String {
        switch self {
        case .registered: String(localized: "Zapsané", comment: "Segment: zapsané termíny")
        case .available: String(localized: "Vypsané", comment: "Segment: vypsané termíny")
        }
    }
}

/// Vypsané termíny jednoho předmětu
nonisolated struct ExamTermGroup: Identifiable, Hashable {
    let subjectCode: String
    let terms: [ExamTerm]
    var id: String { subjectCode }
}

/// Stav přihlašování na termín (pro řádek a detail)
enum ExamTermRegistrationWindow: Equatable {
    /// Přihlašování ještě nezačalo
    case opensLater(opens: Date, deadline: Date?)
    /// Přihlásit se lze (do uzávěrky, pokud je známá)
    case open(deadline: Date?)
    /// Uzávěrka přihlašování už minula
    case closed(deadline: Date)

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
/// Vybírá data z `ExamTermStore` (zapsané termíny, vypsané seskupené po předmětech, nové termíny)
/// a připravuje texty pro řádky. Pro náhledy a snímky obrazovky lze vstříknout vlastní termíny –
/// pak se nikdy nevolá síť.
@Observable
final class ExamTermsViewModel {
    /// Náhledový režim – data jsou vstříknutá, síť se nevolá
    let isPreview: Bool
    /// V náhledu se zápis jen simuluje (mění se vstříknuté termíny), proto `var`
    private var previewTerms: [ExamTerm]?
    private var previewQueuedIDs: Set<String> = []
    private var previewPending: ExamTermStore.PendingRegistration?
    private let previewNewTermIDs: Set<String>
    private let previewFetchedAt: Date?

    /// Ručně zvolený segment; `nil` = automaticky (Zapsané, pokud nějaké jsou)
    private var chosenSegment: ExamTermsSegment?

    /// Ostrý režim – data z `ExamTermStore.shared`
    init() {
        isPreview = false
        previewTerms = nil
        previewNewTermIDs = []
        previewFetchedAt = nil
    }

    /// Náhledový režim pro #Preview a snímky obrazovky.
    /// - Parameters:
    ///   - previewTerms: zobrazené termíny; `nil` = nepřipojený účet
    ///   - newTermIDs: termíny se štítkem „Nový“
    ///   - fetchedAt: čas posledního načtení (patička „Aktualizováno…“)
    init(previewTerms: [ExamTerm]?, newTermIDs: Set<String> = [], fetchedAt: Date? = .now.addingTimeInterval(-4 * 60)) {
        isPreview = true
        self.previewTerms = previewTerms
        previewNewTermIDs = newTermIDs
        previewFetchedAt = previewTerms == nil ? nil : fetchedAt
    }

    // MARK: - Data ze store

    var terms: [ExamTerm] {
        isPreview ? (previewTerms ?? []) : ExamTermStore.shared.terms
    }

    /// Zapsané nadcházející termíny od nejbližšího (i zrušené – student o nich musí vědět)
    var registeredTerms: [ExamTerm] {
        isPreview
            ? terms.filter { $0.isRegistered && $0.isUpcoming() }.sorted { $0.start < $1.start }
            : ExamTermStore.shared.registeredTerms
    }

    /// Vypsané nadcházející termíny bez zrušených, na které student není zapsaný
    var availableTerms: [ExamTerm] {
        isPreview
            ? terms.filter { !$0.isRegistered && !$0.isCancelled && $0.isUpcoming() }.sorted { $0.start < $1.start }
            : ExamTermStore.shared.availableTerms
    }

    var newTermIDs: Set<String> {
        isPreview ? previewNewTermIDs : ExamTermStore.shared.newTermIDs
    }

    var isConnected: Bool {
        isPreview ? previewTerms != nil : StagAccountStore.shared.isConnected
    }

    var isLoading: Bool {
        isPreview ? false : ExamTermStore.shared.isLoading
    }

    var errorMessage: String? {
        isPreview ? nil : ExamTermStore.shared.errorMessage
    }

    var fetchedAt: Date? {
        isPreview ? previewFetchedAt : ExamTermStore.shared.fetchedAt
    }

    func isNew(_ term: ExamTerm) -> Bool { newTermIDs.contains(term.id) }

    /// Aktuální podoba termínu (po zápisu/obnovení se mění) – záložně ta předaná
    func latest(_ term: ExamTerm) -> ExamTerm {
        terms.first { $0.id == term.id } ?? term
    }

    /// Student je ve frontě čekatelů (zapsal se do ní z aplikace)
    func isQueued(_ term: ExamTerm) -> Bool {
        isPreview ? previewQueuedIDs.contains(term.id) : ExamTermStore.shared.isQueued(term)
    }

    /// Právě probíhající změna zápisu
    var pendingRegistration: ExamTermStore.PendingRegistration? {
        isPreview ? previewPending : ExamTermStore.shared.pendingRegistration
    }

    func isRegistrationPending(_ term: ExamTerm) -> Bool { pendingRegistration?.termID == term.id }

    /// Akce, kterou lze u termínu nabídnout (zápis / odhlášení / fronta)
    func registrationAction(for term: ExamTerm, now: Date = .now) -> StagTermRegistrationAction? {
        Self.registrationAction(for: term, isQueued: isQueued(term), now: now)
    }

    /// Počet nových vypsaných termínů (štítek u segmentu)
    var newAvailableCount: Int { availableTerms.filter(isNew).count }

    /// Vypsané termíny seskupené po předmětech; předměty podle nejbližšího termínu
    var availableGroups: [ExamTermGroup] {
        let grouped = Dictionary(grouping: availableTerms) { $0.subjectCode.uppercased() }
        return grouped
            .map { ExamTermGroup(subjectCode: $0.key, terms: $0.value.sorted { $0.start < $1.start }) }
            .sorted { ($0.terms.first?.start ?? .distantFuture) < ($1.terms.first?.start ?? .distantFuture) }
    }

    var hasTerms: Bool { !registeredTerms.isEmpty || !availableTerms.isEmpty }

    var screenState: ExamTermsScreenState {
        if hasTerms { return .ready }
        if !isConnected { return .notConnected(message: errorMessage) }
        if isLoading { return .loading }
        if let errorMessage { return .failed(errorMessage) }
        // Připojeno, ale termíny ještě nedorazily – .task je právě načítá
        if fetchedAt == nil { return .loading }
        return .empty
    }

    /// Zvolený segment – dokud uživatel nevybere sám, ukazujeme Zapsané (jsou-li nějaké)
    var segment: ExamTermsSegment {
        get { chosenSegment ?? (registeredTerms.isEmpty ? .available : .registered) }
        set { chosenSegment = newValue }
    }

    // MARK: - Akce

    func refresh(context: ModelContext) async {
        guard !isPreview else { return }
        await ExamTermStore.shared.refresh(context: context)
    }

    func refreshIfNeeded(context: ModelContext) async {
        guard !isPreview else { return }
        await ExamTermStore.shared.refreshIfNeeded(context: context)
    }

    /// Provede změnu zápisu ve STAGu – OSTRÁ operace, volat jen po potvrzení uživatelem v dialogu.
    /// V náhledovém režimu se nic neposílá, změna se jen nasimuluje na vstříknutých termínech.
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

    /// Uživatel si nové termíny prohlédl – štítky „Nový“ zmizí
    func markAllSeen() {
        guard !isPreview else { return }
        ExamTermStore.shared.markAllSeen()
    }

    // MARK: - Předměty (název a barva)

    /// Názvy a barvy předmětů z rozvrhu – záloha, když předmět v aplikaci chybí
    private var timetableSubjects: [String: (name: String, hex: String?)] {
        let events = isPreview ? TimetableSnapshot.sample.events : TimetableStore.shared.events
        var result: [String: (name: String, hex: String?)] = [:]
        for event in events where result[event.subjectCode.uppercased()] == nil {
            result[event.subjectCode.uppercased()] = (event.subjectName, event.hexColor)
        }
        return result
    }

    /// Název předmětu: z předmětů v aplikaci, záložně z rozvrhu
    func subjectName(for code: String, subjects: [Subject]) -> String? {
        let key = code.uppercased()
        if let subject = subjects.first(where: { $0.code.uppercased() == key }), !subject.name.isEmpty {
            return subject.name
        }
        return timetableSubjects[key]?.name
    }

    /// Barva předmětu: z aplikace, záložně z rozvrhu, jinak deterministicky z palety
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

    /// „Aktualizováno před 5 min“
    func footerText(now: Date) -> String? {
        guard let fetchedAt else { return nil }
        let updated = TimetableViewModel.relativeText(since: fetchedAt, now: now)
        return String(localized: "Aktualizováno \(updated)")
    }

    /// „út 14. 10.“
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.defaultDigits).locale(.czech))
    }

    /// „Úterý 14. října“
    static func longDayText(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// „9:00–11:00“, bez konce jen „9:00“
    static func timeText(_ term: ExamTerm) -> String {
        guard let end = term.end, end > term.start else { return TimetableViewModel.time(term.start) }
        return "\(TimetableViewModel.time(term.start))–\(TimetableViewModel.time(end))"
    }

    /// „2 h“, „1 h 30 min“
    static func durationText(_ term: ExamTerm) -> String? {
        guard let end = term.end, end > term.start else { return nil }
        return TimetableViewModel.durationText(minutes: Int(end.timeIntervalSince(term.start) / 60))
    }

    /// „Zkouška“, „Zkouška · opravný“
    static func typeText(_ term: ExamTerm) -> String {
        term.isRetake ? String(localized: "\(term.typeName) · opravný", comment: "Typ termínu ze STAGu + opravný termín") : term.typeName
    }

    /// Ikona typu termínu
    static func symbol(for term: ExamTerm) -> String {
        term.taskType == .zapocet ? "checkmark.seal.fill" : "graduationcap.fill"
    }

    /// Obsazenost: „14/20 · volno 6“, „Plno · 18/18“, „7 zapsaných“
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

    /// Zaplněnost 0…1 (nil = kapacita neznámá)
    static func occupancyFraction(_ term: ExamTerm) -> Double? {
        guard let occupied = term.occupied, let capacity = term.capacity, capacity > 0 else { return nil }
        return min(max(Double(occupied) / Double(capacity), 0), 1)
    }

    /// Barva obsazenosti: plno červeně, skoro plno oranžově, jinak zeleně
    static func occupancyColor(_ term: ExamTerm) -> Color {
        if term.isFull { return .red }
        if let fraction = occupancyFraction(term), fraction >= 0.8 { return .orange }
        return .green
    }

    static func registrationWindow(_ term: ExamTerm, now: Date = .now) -> ExamTermRegistrationWindow? {
        if let opens = term.registrationOpens, opens > now {
            return .opensLater(opens: opens, deadline: term.registrationDeadline)
        }
        if let deadline = term.registrationDeadline {
            return deadline > now ? .open(deadline: deadline) : .closed(deadline: deadline)
        }
        return term.registrationOpens == nil ? nil : .open(deadline: nil)
    }

    /// „Přihlašování od čt 8. 10. 8:00 do so 12. 10. 23:00“ / „Přihlásit se můžeš do …“ / „Přihlašování skončilo“
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

    /// Uzávěrka přihlašování je do 2 dnů – zvýrazníme ji
    static func isRegistrationClosingSoon(_ term: ExamTerm, now: Date = .now) -> Bool {
        guard case let .open(deadline?)? = registrationWindow(term, now: now) else { return false }
        return deadline.timeIntervalSince(now) < 2 * 24 * 60 * 60
    }

    /// „Odhlásit se lze do po 13. 10. 12:00“ / „Odhlásit se už nelze“
    static func unregisterText(_ term: ExamTerm, now: Date = .now) -> String? {
        guard let deadline = term.unregisterDeadline else { return nil }
        return deadline > now
            ? String(localized: "Odhlásit se lze do \(deadline.deadlineFormatted)")
            : String(localized: "Odhlásit se už nelze")
    }

    /// Důvod, proč se nelze zapsat (jen když nějaký STAG uvedl)
    static func blockReasonText(_ term: ExamTerm) -> String? {
        guard !term.canChangeRegistration, let reason = term.blockReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return nil }
        return reason
    }

    /// „Za 9 dní“, „Zítra“, „Dnes v 9:00“
    static func countdownText(_ term: ExamTerm, now: Date = .now) -> String {
        term.start.calendarDays(from: now) == 0
            ? String(localized: "Dnes v \(TimetableViewModel.time(term.start))")
            : Countdown.text(for: term.start, now: now)
    }

    // MARK: - Zápis na termín

    /// Která akce dává u termínu smysl: zapsaný → odhlásit, ve frontě → opustit frontu,
    /// plný → zapsat do fronty, jinak zapsat. Proběhlé a zrušené (nezapsané) termíny nic nenabízí.
    static func registrationAction(for term: ExamTerm, isQueued: Bool, now: Date = .now) -> StagTermRegistrationAction? {
        guard term.isUpcoming(now: now) else { return nil }
        if term.isRegistered { return .unregister }
        if term.isCancelled { return nil }
        if isQueued { return .leaveQueue }
        return term.isFull ? .joinQueue : .register
    }

    /// Akce je povolená jen tehdy, když STAG změnu zápisu dovoluje (`lzeZapsatOdepsat`).
    /// Opuštění fronty necháváme vždy – rozhodne STAG a případný důvod ukážeme.
    static func isRegistrationActionEnabled(_ action: StagTermRegistrationAction, term: ExamTerm) -> Bool {
        action == .leaveQueue || term.canChangeRegistration
    }

    /// Shrnutí v potvrzovacím dialogu: předmět, typ, datum a čas, místnost + upozornění na změnu ve STAGu
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

    /// Kód budovy z místnosti STAGu: „52/202“ → „52“ (bez lomítka nil – nevíme, co je budova)
    static func buildingCode(from room: String?) -> String? {
        guard let room = room?.trimmingCharacters(in: .whitespaces), let slash = room.firstIndex(of: "/") else { return nil }
        let code = room[..<slash].trimmingCharacters(in: .whitespaces)
        return code.isEmpty ? nil : code
    }

    /// „3 termíny“
    static func termCountText(_ count: Int) -> String {
        String(localized: "\(count) termínů", comment: "Počet termínů")
    }
}

// MARK: - Texty akcí zápisu

extension StagTermRegistrationAction {
    /// Popisek tlačítka a položky kontextové nabídky
    var title: String {
        switch self {
        case .register: String(localized: "Zapsat se na termín")
        case .unregister: String(localized: "Odhlásit se z termínu")
        case .joinQueue: String(localized: "Zapsat se do fronty")
        case .leaveQueue: String(localized: "Odhlásit se z fronty")
        }
    }

    var symbol: String {
        switch self {
        case .register: "person.crop.circle.badge.plus"
        case .unregister: "person.crop.circle.badge.minus"
        case .joinQueue: "person.3.sequence.fill"
        case .leaveQueue: "person.crop.circle.badge.xmark"
        }
    }

    /// Odhlášení je destruktivní (místo může obsadit někdo jiný)
    var isDestructive: Bool { self == .unregister || self == .leaveQueue }

    /// Nadpis potvrzovacího dialogu
    var confirmationTitle: String {
        switch self {
        case .register: String(localized: "Zapsat se na tento termín?")
        case .unregister: String(localized: "Odhlásit se z tohoto termínu?")
        case .joinQueue: String(localized: "Zapsat se do fronty čekatelů?")
        case .leaveQueue: String(localized: "Odhlásit se z fronty čekatelů?")
        }
    }

    /// Tlačítko v potvrzovacím dialogu
    var confirmButtonTitle: String {
        switch self {
        case .register: String(localized: "Zapsat se")
        case .unregister: String(localized: "Odhlásit se")
        case .joinQueue: String(localized: "Zapsat do fronty")
        case .leaveQueue: String(localized: "Opustit frontu")
        }
    }

    /// Upozornění v dialogu – jde o ostrou změnu ve STAGu
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

    /// Hláška po úspěchu
    var successText: String {
        switch self {
        case .register: String(localized: "Jsi zapsaný na termín. Zkoušku s připomínkou najdeš v Přehledu.")
        case .unregister: String(localized: "Z termínu jsi odhlášený.")
        case .joinQueue: String(localized: "Jsi ve frontě čekatelů na termín.")
        case .leaveQueue: String(localized: "Z fronty čekatelů jsi odhlášený.")
        }
    }

    /// Text při probíhající akci
    var progressText: String {
        switch self {
        case .register: String(localized: "Zapisuji na termín…")
        case .unregister: String(localized: "Odhlašuji z termínu…")
        case .joinQueue: String(localized: "Zapisuji do fronty…")
        case .leaveQueue: String(localized: "Odhlašuji z fronty…")
        }
    }
}
