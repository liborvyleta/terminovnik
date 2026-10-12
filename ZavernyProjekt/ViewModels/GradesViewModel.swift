import Foundation
import Observation
import SwiftUI

/// Co má obrazovka Studijní výsledky právě zobrazit.
///
/// Stav odvozuje ``GradesViewModel/screenState`` z dat `GradeStore` a připojení účtu STAG; View podle něj volí mezi výzvou k připojení, načítáním, chybou, prázdným stavem a seznamem známek.
enum GradesScreenState: Equatable {
    /// Účet STAG není připojený (volitelně s důvodem, např. vypršelé přihlášení)
    case notConnected(message: String?)
    /// Známky se poprvé načítají
    case loading
    /// Načtení selhalo a nemáme žádná uložená data
    case failed(String)
    /// Připojeno, ale STAG zatím žádné předměty ani známky nevrátil
    case empty
    /// Známky jsou k dispozici
    case ready
}

/// ViewModel obrazovky Studijní výsledky.
///
/// Bere data z `GradeStore` (známky po semestrech, souhrn, stav načítání) a `StagAccountStore` (připojení účtu), umožňuje obnovení dat a připravuje texty (průměr, kredity, pokusy, body). Názvy a barvy doplňuje z předmětů uložených v aplikaci. Pro náhledy a snímky obrazovky lze vstříknout vlastní známky – pak se nikdy nevolá síť.
@Observable
final class GradesViewModel {
    /// Náhledový režim – data jsou vstříknutá, síť se nevolá.
    let isPreview: Bool
    /// Vstříknuté známky v náhledu; `nil` = nepřipojený účet.
    private let previewGrades: [SubjectGrade]?
    /// Čas posledního načtení v náhledu.
    private let previewFetchedAt: Date?

    /// Vytvoří ViewModel v ostrém režimu – data z `GradeStore.shared`.
    init() {
        isPreview = false
        previewGrades = nil
        previewFetchedAt = nil
    }

    /// Vytvoří ViewModel v náhledovém režimu pro #Preview a snímky obrazovky.
    /// - Parameters:
    ///   - previewGrades: Zobrazené známky; `nil` = nepřipojený účet.
    ///   - fetchedAt: Čas posledního načtení (patička „Aktualizováno…“); při `previewGrades == nil` se ignoruje.
    init(previewGrades: [SubjectGrade]?, fetchedAt: Date? = .now.addingTimeInterval(-6 * 60)) {
        isPreview = true
        self.previewGrades = previewGrades
        previewFetchedAt = previewGrades == nil ? nil : fetchedAt
    }

    // MARK: - Data ze store

    /// Všechny známky – vstříknuté v náhledu, jinak z `GradeStore`.
    var grades: [SubjectGrade] {
        isPreview ? (previewGrades ?? []) : GradeStore.shared.grades
    }

    /// Výsledky po semestrech, nejnovější první.
    var semesters: [GradeSemester] {
        isPreview ? grades.bySemester : GradeStore.shared.semesters
    }

    /// Souhrn za celé studium.
    var summary: GradeSummary {
        isPreview ? GradeSummary(grades: grades) : GradeStore.shared.overallSummary
    }

    /// Příznak, zda je účet STAG připojený (v náhledu podle toho, zda jsou vstříknuté známky).
    var isConnected: Bool {
        isPreview ? previewGrades != nil : StagAccountStore.shared.isConnected
    }

    /// Příznak probíhajícího načítání známek (v náhledu vždy `false`).
    var isLoading: Bool {
        isPreview ? false : GradeStore.shared.isLoading
    }

    /// Chybová hláška posledního načtení (v náhledu vždy `nil`).
    var errorMessage: String? {
        isPreview ? nil : GradeStore.shared.errorMessage
    }

    /// Čas posledního úspěšného načtení známek.
    var fetchedAt: Date? {
        isPreview ? previewFetchedAt : GradeStore.shared.fetchedAt
    }

    /// Stav obrazovky odvozený ze známek, připojení, načítání a chyby.
    var screenState: GradesScreenState {
        if !grades.isEmpty { return .ready }
        if !isConnected { return .notConnected(message: errorMessage) }
        if isLoading { return .loading }
        if let errorMessage { return .failed(errorMessage) }
        // Připojeno, ale známky ještě nedorazily – .task je právě načítá
        if fetchedAt == nil { return .loading }
        return .empty
    }

    // MARK: - Akce

    /// Vynuceně znovu načte známky ze STAGu (v náhledu nic nedělá).
    func refresh() async {
        guard !isPreview else { return }
        await GradeStore.shared.refresh()
    }

    /// Načte známky ze STAGu, pokud to `GradeStore` považuje za potřebné (v náhledu nic nedělá).
    func refreshIfNeeded() async {
        guard !isPreview else { return }
        await GradeStore.shared.refreshIfNeeded()
    }

    // MARK: - Předměty (název a barva)

    /// Název předmětu: ze STAGu, záložně z předmětů v aplikaci, jinak kód.
    /// - Parameters:
    ///   - grade: Hodnocení předmětu ze STAGu.
    ///   - subjects: Předměty uložené v aplikaci.
    /// - Returns: Název k zobrazení.
    func subjectName(for grade: SubjectGrade, subjects: [Subject]) -> String {
        if let name = grade.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let subject = subject(for: grade.code, in: subjects), !subject.name.isEmpty { return subject.name }
        return grade.code
    }

    /// Předmět v aplikaci se stejným kódem (pro barvu a odkaz na detail).
    /// - Parameters:
    ///   - code: Kód předmětu (porovnává se bez ohledu na velikost písmen).
    ///   - subjects: Předměty uložené v aplikaci.
    /// - Returns: Nalezený předmět, nebo `nil`.
    func subject(for code: String, in subjects: [Subject]) -> Subject? {
        subjects.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    /// Barva předmětu z aplikace, jinak deterministicky z palety (stejný kód = stejná barva).
    /// - Parameters:
    ///   - code: Kód předmětu.
    ///   - subjects: Předměty uložené v aplikaci.
    /// - Returns: Barva předmětu.
    func tint(for code: String, subjects: [Subject]) -> Color {
        if let subject = subject(for: code, in: subjects) { return subject.color }
        let seed = code.uppercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: SubjectPalette.hex(seed))
    }

    // MARK: - Texty

    /// Text patičky ve tvaru „Aktualizováno před 5 min“.
    /// - Parameter now: Referenční okamžik.
    /// - Returns: Text patičky, nebo `nil`, pokud známky ještě nebyly načteny.
    func footerText(now: Date) -> String? {
        guard let fetchedAt else { return nil }
        let updated = TimetableViewModel.relativeText(since: fetchedAt, now: now)
        return String(localized: "Aktualizováno \(updated)")
    }

    /// Průměr na dvě desetinná místa v českém formátu: „1,73“.
    /// - Parameter average: Průměr, nebo `nil`, pokud zatím není.
    /// - Returns: Naformátovaný průměr, nebo „–“.
    static func averageText(_ average: Double?) -> String {
        guard let average else { return "–" }
        return average.formatted(.number.precision(.fractionLength(2)).locale(.czech))
    }

    /// Barevná úroveň průměru (nil = zatím žádná známka).
    /// - Parameter average: Průměr, nebo `nil`.
    /// - Returns: Úroveň pro obarvení; bez průměru `.unknown`.
    static func averageLevel(_ average: Double?) -> GradeLevel {
        average.map(GradeLevel.forNumericValue) ?? .unknown
    }

    /// „17 kreditů“ – tvar podle počtu doplňuje String Catalog.
    /// - Parameter credits: Počet kreditů.
    /// - Returns: Lokalizovaný text.
    static func creditsText(_ credits: Int) -> String {
        String(localized: "\(credits) kreditů")
    }

    /// Kredity semestru: „11 kreditů“, když je vše získané, jinak „4 z 9 kreditů“.
    /// - Parameter semester: Semestr se známkami.
    /// - Returns: Lokalizovaný text kreditů.
    static func semesterCreditsText(_ semester: GradeSemester) -> String {
        let earned = semester.summary.earnedCredits
        let total = semester.grades.reduce(0) { $0 + ($1.credits ?? 0) }
        guard earned < total else { return creditsText(earned) }
        return String(localized: "\(earned) z \(total) kreditů", comment: "Získané kredity z celkového počtu v semestru")
    }

    /// Počet absolvovaných předmětů: „4 z 6 předmětů“.
    /// - Parameter summary: Souhrn hodnocení.
    /// - Returns: Lokalizovaný text.
    static func passedText(_ summary: GradeSummary) -> String {
        String(localized: "\(summary.passedCount) z \(summary.totalCount) předmětů", comment: "Absolvované předměty z celkového počtu")
    }

    /// Podíl absolvovaných předmětů 0…1.
    /// - Parameter summary: Souhrn hodnocení.
    /// - Returns: Podíl; bez předmětů 0.
    static func passedFraction(_ summary: GradeSummary) -> Double {
        summary.totalCount > 0 ? Double(summary.passedCount) / Double(summary.totalCount) : 0
    }

    /// Datum ve tvaru „3. 6. 2026“ (český formát).
    /// - Parameter date: Datum k naformátování.
    /// - Returns: Naformátovaný text.
    nonisolated static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.defaultDigits).year().locale(.czech))
    }

    /// „2. pokus“ – jen opravné pokusy (u řádného termínu nic).
    /// - Parameter part: Část hodnocení (zápočet nebo zkouška).
    /// - Returns: Text pokusu, nebo `nil` u prvního či neznámého pokusu.
    static func attemptText(_ part: GradePart) -> String? {
        guard let attempt = part.attempt, attempt > 1 else { return nil }
        return String(localized: "\(attempt). pokus", comment: "Pořadí pokusu u zápočtu nebo zkoušky")
    }

    /// „45 b.“ – body, pokud je zkoušející zadal.
    /// - Parameter part: Část hodnocení.
    /// - Returns: Text bodů, nebo `nil`, pokud body chybí.
    static func pointsText(_ part: GradePart) -> String? {
        guard let points = part.points?.trimmingCharacters(in: .whitespaces), !points.isEmpty else { return nil }
        return String(localized: "\(points) b.", comment: "Počet bodů z hodnocení")
    }
}
