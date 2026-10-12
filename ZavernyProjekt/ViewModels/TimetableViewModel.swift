import Foundation
import Observation
import SwiftData

/// Co má záložka Rozvrh právě zobrazit.
///
/// Stav odvozuje ``TimetableViewModel/screenState`` z dat `TimetableStore` a připojení účtu STAG; View podle něj volí mezi výzvou k připojení, načítáním, chybou, prázdným stavem a rozvrhem.
enum TimetableScreenState: Equatable {
    /// Účet STAG není připojený (volitelně s důvodem, např. vypršelé přihlášení)
    case notConnected(message: String?)
    /// Rozvrh se poprvé načítá
    case loading
    /// Načtení selhalo a nemáme žádná uložená data
    case failed(String)
    /// Rozvrh je načtený, ale nemá žádné akce
    case empty
    /// Rozvrh je k dispozici
    case ready
}

/// Jeden den ve výběru dní nahoře (Po–Pá, víkend jen s výukou).
///
/// Seznam dní sestavuje ``TimetableViewModel/weekDays``.
nonisolated struct TimetableDay: Identifiable, Hashable {
    let date: Date
    /// 1 = pondělí … 7 = neděle – zároveň stabilní identita (animace výběru mezi týdny).
    let weekday: Int
    /// Identifikátor – den v týdnu.
    var id: Int { weekday }
}

/// Akce otevřená v detailu – z konkrétního dne (s výskytem) nebo bez pevného termínu.
///
/// Slouží jako položka pro prezentaci detailu akce rozvrhu.
nonisolated struct TimetableSelection: Identifiable, Hashable {
    let event: TimetableEvent
    let occurrence: TimetableOccurrence?
    /// Identifikátor – výskytu, záložně akce.
    var id: String { occurrence?.id ?? event.id }
}

/// ViewModel záložky Rozvrh.
///
/// Drží zvolený den a týden, počítá dny pro výběr nahoře, navigaci po dnech a týdnech a texty nadpisů, a vybírá data ze `TimetableStore` (připojení účtu z `StagAccountStore`). Statické pomocné funkce pro časy, barvy a odpočty využívají i další obrazovky (Zkoušky, Výsledky). Pro náhledy a snímky obrazovky lze vstříknout vlastní rozvrh – pak se nikdy nevolá síť.
@Observable
final class TimetableViewModel {
    /// Zvolený den (vždy půlnoc).
    private(set) var selectedDay: Date

    /// Náhledový režim – data jsou vstříknutá, síť se nevolá.
    let isPreview: Bool
    /// Vstříknutý rozvrh v náhledu; `nil` = nepřipojený účet.
    private let previewSnapshot: TimetableSnapshot?
    /// Kalendář pro výpočty dní a týdnů.
    private let calendar: Calendar

    /// Vytvoří ViewModel v ostrém režimu – data z `TimetableStore.shared`; počáteční den je výchozí den.
    /// - Parameter calendar: Kalendář pro výpočty dní.
    init(calendar: Calendar = .current) {
        self.isPreview = false
        self.previewSnapshot = nil
        self.calendar = calendar
        self.selectedDay = calendar.startOfDay(for: .now)
        self.selectedDay = defaultDay(now: .now)
    }

    /// Vytvoří ViewModel v náhledovém režimu pro #Preview a snímky obrazovky.
    /// - Parameters:
    ///   - previewSnapshot: Zobrazený rozvrh; `nil` = nepřipojený účet.
    ///   - selectedDay: Počáteční den (výchozí je dnešek, o víkendu bez výuky pondělí).
    ///   - calendar: Kalendář pro výpočty dní.
    init(previewSnapshot: TimetableSnapshot?, selectedDay: Date? = nil, calendar: Calendar = .current) {
        self.isPreview = true
        self.previewSnapshot = previewSnapshot
        self.calendar = calendar
        self.selectedDay = calendar.startOfDay(for: selectedDay ?? .now)
        if selectedDay == nil {
            self.selectedDay = defaultDay(now: .now)
        }
    }

    // MARK: - Data ze store

    /// Rozvrh – vstříknutý v náhledu, jinak z `TimetableStore`.
    var snapshot: TimetableSnapshot? {
        isPreview ? previewSnapshot : TimetableStore.shared.snapshot
    }

    /// Příznak, zda je účet STAG připojený (v náhledu podle toho, zda je vstříknutý rozvrh).
    var isConnected: Bool {
        isPreview ? previewSnapshot != nil : StagAccountStore.shared.isConnected
    }

    /// Příznak probíhajícího načítání rozvrhu (v náhledu vždy `false`).
    var isLoading: Bool {
        isPreview ? false : TimetableStore.shared.isLoading
    }

    /// Chybová hláška posledního načtení (v náhledu vždy `nil`).
    var errorMessage: String? {
        isPreview ? nil : TimetableStore.shared.errorMessage
    }

    /// Příznak, zda rozvrh obsahuje aspoň jednu akci.
    var hasTimetable: Bool { !(snapshot?.events.isEmpty ?? true) }

    /// Stav obrazovky odvozený z rozvrhu, připojení, načítání a chyby.
    var screenState: TimetableScreenState {
        if hasTimetable { return .ready }
        if !isConnected { return .notConnected(message: errorMessage) }
        if isLoading { return .loading }
        if let errorMessage { return .failed(errorMessage) }
        // Připojeno, ale rozvrh ještě nedorazil – .task ho právě načítá
        if snapshot == nil { return .loading }
        return .empty
    }

    /// Vynuceně znovu načte rozvrh ze STAGu (v náhledu nic nedělá).
    /// - Parameter context: SwiftData kontext předávaný do `TimetableStore`.
    func refresh(context: ModelContext) async {
        guard !isPreview else { return }
        await TimetableStore.shared.refresh(context: context)
    }

    /// Načte rozvrh ze STAGu, pokud to `TimetableStore` považuje za potřebné (v náhledu nic nedělá).
    /// - Parameter context: SwiftData kontext předávaný do `TimetableStore`.
    func refreshIfNeeded(context: ModelContext) async {
        guard !isPreview else { return }
        await TimetableStore.shared.refreshIfNeeded(context: context)
    }

    // MARK: - Výskyty

    /// Výskyty akcí rozvrhu v daném dni.
    /// - Parameter day: Den.
    /// - Returns: Výskyty, bez rozvrhu prázdné pole.
    func occurrences(on day: Date) -> [TimetableOccurrence] {
        snapshot?.occurrences(on: day, calendar: calendar) ?? []
    }

    /// Výskyty akcí ve zvoleném dni.
    var selectedOccurrences: [TimetableOccurrence] { occurrences(on: selectedDay) }

    /// Zjistí, zda má den nějakou výuku.
    /// - Parameter day: Den.
    /// - Returns: `true`, pokud v daném dni existuje výskyt.
    func hasLessons(on day: Date) -> Bool { !occurrences(on: day).isEmpty }

    /// Akce bez pevného dne a času seřazené podle předmětu.
    var unscheduledEvents: [TimetableEvent] {
        (snapshot?.unscheduledEvents ?? []).sorted {
            ($0.subjectCode, $0.typeName) < ($1.subjectCode, $1.typeName)
        }
    }

    /// Hodina pro kartu „Teď probíhá / Další hodina“.
    ///
    /// Jen u dneška nebo když nejbližší hodina připadá na zvolený den (např. pondělí po víkendu).
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Zvýrazněný výskyt, nebo `nil`.
    func highlightedOccurrence(now: Date) -> TimetableOccurrence? {
        guard let next = snapshot?.upcoming(after: now, limit: 1, calendar: calendar).first else { return nil }
        let isSelectedToday = calendar.isDate(selectedDay, inSameDayAs: now)
        return isSelectedToday || calendar.isDate(next.start, inSameDayAs: selectedDay) ? next : nil
    }

    /// Nejbližší den s výukou po zvoleném dni (hledá 21 dní dopředu; pro text u volného dne).
    var nextLessonDay: Date? {
        for offset in 1...21 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: selectedDay) else { continue }
            if hasLessons(on: day) { return day }
        }
        return nil
    }

    // MARK: - Navigace po dnech a týdnech

    /// Pondělí zobrazeného týdne.
    var weekStart: Date { monday(of: selectedDay) }

    /// Dny pro výběr nahoře: Po–Pá vždy, So a Ne jen s výukou (nebo pokud jsou zvolené).
    var weekDays: [TimetableDay] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let isWorkday = offset < 5
            guard isWorkday || hasLessons(on: date) || calendar.isDate(date, inSameDayAs: selectedDay) else { return nil }
            return TimetableDay(date: date, weekday: offset + 1)
        }
    }

    /// Zjistí, zda je den zvolený.
    /// - Parameter day: Den.
    /// - Returns: `true`, pokud jde o stejný den jako ``selectedDay``.
    func isSelected(_ day: Date) -> Bool { calendar.isDate(day, inSameDayAs: selectedDay) }

    /// Zvolí den (uloží se jeho půlnoc).
    /// - Parameter day: Nově zvolený den.
    func select(_ day: Date) { selectedDay = calendar.startOfDay(for: day) }

    /// Posune výběr o týden zpět.
    func showPreviousWeek() { moveWeek(by: -1) }

    /// Posune výběr o týden dopředu.
    func showNextWeek() { moveWeek(by: 1) }

    /// Skok na dnešek (o víkendu bez výuky na pondělí dalšího týdne).
    /// - Parameter now: Referenční okamžik.
    func showToday(now: Date = .now) { selectedDay = defaultDay(now: now) }

    /// Je zobrazený výchozí den? (tlačítko „Dnes“ pak není potřeba)
    /// - Parameter now: Referenční okamžik.
    /// - Returns: `true`, pokud je zvolený výchozí den.
    func isShowingDefaultDay(now: Date = .now) -> Bool {
        calendar.isDate(selectedDay, inSameDayAs: defaultDay(now: now))
    }

    /// Dnešek, o víkendu bez výuky pondělí příštího týdne.
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Výchozí den (půlnoc).
    func defaultDay(now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = TimetableEvent.weekday(of: today, calendar: calendar)
        guard weekday >= 6, !hasLessons(on: today) else { return today }
        return calendar.date(byAdding: .day, value: 8 - weekday, to: today) ?? today
    }

    /// Posun o týden se zachováním dne v týdnu (víkend bez výuky → pondělí).
    /// - Parameter weeks: Počet týdnů (záporný = zpět).
    private func moveWeek(by weeks: Int) {
        guard let target = calendar.date(byAdding: .day, value: 7 * weeks, to: selectedDay) else { return }
        let weekday = TimetableEvent.weekday(of: target, calendar: calendar)
        selectedDay = weekday >= 6 && !hasLessons(on: target) ? monday(of: target) : target
    }

    /// Pondělí týdne, do kterého datum patří.
    /// - Parameter date: Libovolné datum.
    /// - Returns: Půlnoc pondělí.
    private func monday(of date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = TimetableEvent.weekday(of: day, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1 - weekday, to: day) ?? day
    }

    // MARK: - Texty

    /// Lokalizované zkratky dnů v týdnu od pondělí.
    private static let weekdaySymbols = [
        String(localized: "Po", comment: "Zkratka dne v týdnu: pondělí"),
        String(localized: "Út", comment: "Zkratka dne v týdnu: úterý"),
        String(localized: "St", comment: "Zkratka dne v týdnu: středa"),
        String(localized: "Čt", comment: "Zkratka dne v týdnu: čtvrtek"),
        String(localized: "Pá", comment: "Zkratka dne v týdnu: pátek"),
        String(localized: "So", comment: "Zkratka dne v týdnu: sobota"),
        String(localized: "Ne", comment: "Zkratka dne v týdnu: neděle"),
    ]

    /// Zkratka dne v týdnu: „Po“, „Út“…
    /// - Parameter day: Den.
    /// - Returns: Lokalizovaná zkratka.
    func weekdaySymbol(_ day: Date) -> String {
        Self.weekdaySymbols[TimetableEvent.weekday(of: day, calendar: calendar) - 1]
    }

    /// Číslo dne v měsíci jako text.
    /// - Parameter day: Den.
    /// - Returns: Např. „14“.
    func dayNumber(_ day: Date) -> String { "\(calendar.component(.day, from: day))" }

    /// Zjistí, zda je den dnešek.
    /// - Parameters:
    ///   - day: Den.
    ///   - now: Referenční okamžik.
    /// - Returns: `true`, pokud jde o stejný den jako `now`.
    func isToday(_ day: Date, now: Date = .now) -> Bool { calendar.isDate(day, inSameDayAs: now) }

    /// Nadpis týdne: „Tento týden · lichý“, „Příští týden · sudý“, „Týden 45 · lichý“.
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Název týdne s paritou podle ISO čísla týdne.
    func weekTitle(now: Date = .now) -> String {
        let days = calendar.dateComponents([.day], from: monday(of: now), to: weekStart).day ?? 0
        let name = switch days / 7 {
        case 0: String(localized: "Tento týden")
        case 1: String(localized: "Příští týden")
        case -1: String(localized: "Minulý týden")
        default: String(localized: "Týden \(isoWeek)", comment: "Číslo týdne v roce (ISO)")
        }
        let parity = isoWeek % 2 == 0
            ? String(localized: "sudý", comment: "Sudý týden (rozvrh)")
            : String(localized: "lichý", comment: "Lichý týden (rozvrh)")
        return "\(name) · \(parity)"
    }

    /// „5. – 9. října“, přes hranici měsíce „28. září – 2. října“.
    var weekRangeText: String {
        let end = weekDays.last?.date ?? weekStart
        // Intervalový formát podle jazyka aplikace: „5.–9. října“ / „5–9 October“
        let style = Date.IntervalFormatStyle().day().month(.wide).locale(.app)
        return (weekStart..<end).formatted(style)
    }

    /// Nadpis sekce dne: „Dnes · úterý 6. října“, „Zítra · …“, jinak „Čtvrtek 8. října“.
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Nadpis zvoleného dne.
    func dayTitle(now: Date = .now) -> String {
        let text = selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))
        switch selectedDay.calendarDays(from: now, calendar: calendar) {
        case 0: return String(localized: "Dnes · \(text)")
        case 1: return String(localized: "Zítra · \(text)")
        default: return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    /// Počet akcí zvoleného dne: „3 akce“, „5 akcí“.
    var lessonCountText: String {
        let count = selectedOccurrences.count
        return String(localized: "\(count) akcí", comment: "Počet akcí rozvrhu ve dni")
    }

    /// „Rozvrh ZS 2026/2027 · aktualizováno před 5 min“.
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Text patičky, nebo `nil` bez rozvrhu.
    func footerText(now: Date) -> String? {
        guard let snapshot else { return nil }
        let years = Int(snapshot.academicYear).map { "\($0)/\($0 + 1)" } ?? snapshot.academicYear
        let updated = Self.relativeText(since: snapshot.fetchedAt, now: now)
        return String(localized: "Rozvrh \(snapshot.semester) \(years) · aktualizováno \(updated)", comment: "Patička rozvrhu: semestr, akademický rok, kdy aktualizováno")
    }

    /// ISO číslo zobrazeného týdne.
    private var isoWeek: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: weekStart)
    }

    // MARK: - Pomocné výpočty pro řádky a kartu

    /// Barva akce: živě z předmětu se stejným kódem, záložně uložená v rozvrhu, jinak z palety podle kódu.
    /// - Parameters:
    ///   - event: Akce rozvrhu.
    ///   - subjectColors: Barvy předmětů v aplikaci podle kódu (velkými písmeny).
    /// - Returns: Barva v hex zápisu.
    static func hexColor(for event: TimetableEvent, subjectColors: [String: String]) -> String {
        if let hex = subjectColors[event.subjectCode.uppercased()] { return hex }
        if let hex = event.hexColor, !hex.isEmpty { return hex }
        // Deterministický index (hashValue se mezi spuštěními mění)
        let seed = event.subjectCode.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return SubjectPalette.hex(seed)
    }

    /// Ikona typu akce.
    /// - Parameter event: Akce rozvrhu.
    /// - Returns: Název SF Symbolu podle zkratky typu (přednáška, cvičení, seminář, jiné).
    static func symbol(for event: TimetableEvent) -> String {
        switch event.typeShort {
        case "Př": "graduationcap.fill"
        case "Cv": "laptopcomputer"
        case "Se": "person.3.fill"
        default: "book.closed.fill"
        }
    }

    /// Časové rozmezí výskytu: „10:00–12:00“.
    /// - Parameter occurrence: Výskyt akce.
    /// - Returns: Text rozmezí.
    static func timeRange(of occurrence: TimetableOccurrence) -> String {
        "\(occurrence.start.formatted(timeFormat))–\(occurrence.end.formatted(timeFormat))"
    }

    /// Čas ve tvaru „10:00“.
    /// - Parameter date: Okamžik.
    /// - Returns: Naformátovaný čas.
    static func time(_ date: Date) -> String { date.formatted(timeFormat) }

    /// Odpočet pro kartu: „za 25 min“, „probíhá ještě 40 min“, „zítra v 8:00“, „čt v 13:00“.
    /// - Parameters:
    ///   - occurrence: Výskyt akce.
    ///   - now: Referenční okamžik.
    /// - Returns: Text odpočtu.
    static func countdownText(for occurrence: TimetableOccurrence, now: Date) -> String {
        if occurrence.start <= now {
            let remaining = durationText(minutes: minutes(from: now, to: occurrence.end))
            return String(localized: "probíhá ještě \(remaining)")
        }
        switch occurrence.start.calendarDays(from: now) {
        case 0:
            let remaining = durationText(minutes: minutes(from: now, to: occurrence.start))
            return String(localized: "za \(remaining)", comment: "Za jak dlouho začne hodina")
        case 1:
            return String(localized: "zítra v \(time(occurrence.start))")
        default:
            let weekday = occurrence.start.formatted(.dateTime.weekday(.abbreviated).locale(.czech))
            return String(localized: "\(weekday) v \(time(occurrence.start))", comment: "Zkratka dne v týdnu a čas: „čt v 13:00“")
        }
    }

    /// Podíl uplynulé části probíhající hodiny (0…1).
    /// - Parameters:
    ///   - occurrence: Výskyt akce.
    ///   - now: Referenční okamžik.
    /// - Returns: Podíl v rozsahu 0…1; při nulové délce 0.
    static func progress(of occurrence: TimetableOccurrence, now: Date) -> Double {
        let total = occurrence.end.timeIntervalSince(occurrence.start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(occurrence.start) / total, 0), 1)
    }

    /// Délka: „25 min“, „1 h 30 min“, „2 h“ (minimálně 1 min).
    /// - Parameter minutes: Délka v minutách.
    /// - Returns: Lokalizovaný text.
    static func durationText(minutes: Int) -> String {
        guard minutes >= 60 else { return String(localized: "\(max(minutes, 1)) min", comment: "Délka v minutách") }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0
            ? String(localized: "\(hours) h", comment: "Délka v hodinách")
            : String(localized: "\(hours) h \(rest) min", comment: "Délka v hodinách a minutách")
    }

    /// „právě teď“, „před 5 min“, „před 3 h“, jinak datum a čas.
    /// - Parameters:
    ///   - date: Minulý okamžik.
    ///   - now: Referenční okamžik.
    /// - Returns: Relativní text.
    static func relativeText(since date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return String(localized: "právě teď")
        case ..<60: return String(localized: "před \(minutes) min", comment: "Před kolika minutami")
        case ..<(24 * 60): return String(localized: "před \(minutes / 60) h", comment: "Před kolika hodinami")
        default: return date.formatted(.dateTime.day().month(.defaultDigits).hour().minute().locale(.czech))
        }
    }

    /// Formát času „HH:mm“ v češtině.
    private static let timeFormat = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(.czech)

    /// Počet minut mezi dvěma okamžiky zaokrouhlený nahoru.
    /// - Parameters:
    ///   - start: Počátek.
    ///   - end: Konec.
    /// - Returns: Počet minut.
    private static func minutes(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded(.up))
    }
}
