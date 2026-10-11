import Foundation
import Observation
import UserNotifications

/// Známky a studijní výsledky ze STAGu načtené přes uložený účet.
///
/// - Spojuje známky ze zápočtů a zkoušek (getZnamkyByStudent) s přehledem předmětů,
///   kredity a výslednou známkou (getStudentPredmetyAbsolvoval).
/// - Ukládá se do App Group (funguje offline).
/// - Nová nebo změněná známka vyvolá lokální oznámení (při otevření aplikace i při kontrole na pozadí).
@Observable
final class GradeStore {
    static let shared = GradeStore()

    /// Klíč přepínače v Nastavení – upozornění na nové známky (výchozí zapnuto)
    nonisolated static let alertsEnabledKey = "gradeAlertsEnabled"

    private(set) var grades: [SubjectGrade] = []
    private(set) var fetchedAt: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Jak starý seznam se při otevření aplikace obnoví
    private let maxAge: TimeInterval = 30 * 60

    private enum Keys {
        static let snapshot = "grades.v1"
        static let seen = "grades.seen"
    }

    private struct Snapshot: Codable {
        var grades: [SubjectGrade]
        var fetchedAt: Date
    }

    private init() {
        restoreFromCache()
    }

    private func restoreFromCache() {
        grades = []
        fetchedAt = nil
        if let data = AppGroup.defaults?.data(forKey: Keys.snapshot),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            grades = snapshot.grades
            fetchedAt = snapshot.fetchedAt
        }
    }

    // MARK: - Dotazy

    var hasGrades: Bool { !grades.isEmpty }

    /// Souhrn za celé studium
    var overallSummary: GradeSummary { GradeSummary(grades: grades) }

    /// Výsledky po semestrech, nejnovější první
    var semesters: [GradeSemester] { grades.bySemester }

    /// Nejnovější hodnocení předmětu podle kódu (předmět se může opakovat v různých letech)
    func grade(forSubjectCode code: String) -> SubjectGrade? {
        grades.filter { $0.code.caseInsensitiveCompare(code) == .orderedSame }
            .max { $0.semesterSortKey < $1.semesterSortKey }
    }

    // MARK: - Načítání

    /// Načte známky ze STAGu a upozorní na nové. Vrací počet nových známek.
    @discardableResult
    func refresh() async -> Int {
        if DemoMode.isActive { return 0 }
        guard let account = StagAccountStore.shared.account,
              let service = StagAccountStore.shared.makeService() else {
            errorMessage = String(localized: "Pro načtení známek se přihlas do IS/STAG.")
            return 0
        }
        guard !isLoading else { return 0 }
        isLoading = true
        defer { isLoading = false }

        do {
            // Obě služby běží souběžně; přehled předmětů je doplňkový – jeho výpadek známky nezablokuje
            async let recordsTask = service.studentGrades(osCislo: account.osCislo)
            async let passedTask = service.studentPassedSubjects(osCislo: account.osCislo)
            let records = try await recordsTask
            let passed = (try? await passedTask) ?? []

            let merged = Self.merge(records: records, passed: passed)
            let changed = detectNewGrades(in: merged)
            grades = merged
            fetchedAt = .now
            errorMessage = nil
            persist()
            if !changed.isEmpty { await notify(about: changed) }
            return changed.count
        } catch StagError.unauthorized {
            StagAccountStore.shared.signOut()
            errorMessage = String(localized: "Přihlášení do STAGu vypršelo, přihlas se znovu.")
        } catch {
            errorMessage = error.localizedDescription
        }
        return 0
    }

    /// Obnoví známky, pokud je uživatel přihlášený a seznam je starší než půl hodiny.
    func refreshIfNeeded() async {
        guard StagAccountStore.shared.isConnected else { return }
        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge { return }
        await refresh()
    }

    /// Smaže uložené známky (odhlášení ze STAGu, smazání dat)
    func clear() {
        grades = []
        fetchedAt = nil
        errorMessage = nil
        guard !DemoMode.isActive else { return }
        AppGroup.defaults?.removeObject(forKey: Keys.snapshot)
        AppGroup.defaults?.removeObject(forKey: Keys.seen)
    }

    // MARK: - Spojení služeb

    /// Spojí známky ze zápočtů/zkoušek s přehledem absolvovaných předmětů (klíč katedra/kód/rok/semestr).
    nonisolated static func merge(records: [StagGradeRecord], passed: [StagPassedSubject]) -> [SubjectGrade] {
        func key(_ department: String?, _ code: String?, _ year: String?, _ semester: String?) -> String {
            [department, code, year, semester].map { ($0 ?? "").uppercased() }.joined(separator: "/")
        }
        var result: [String: SubjectGrade] = [:]

        for subject in passed {
            guard let code = subject.zkratka else { continue }
            let id = key(subject.katedra, code, subject.rok, subject.semestr)
            result[id] = SubjectGrade(
                code: code, department: subject.katedra ?? "", year: subject.rok ?? "", semester: subject.semestr ?? "",
                name: subject.nazevPredmetu, credits: subject.pocetKreditu,
                creditTest: nil, exam: nil, finalGrade: subject.znamka,
                isPassed: subject.absolvoval ?? false, isRecognized: false
            )
        }

        for record in records {
            guard let code = record.zkratka else { continue }
            let id = key(record.katedra, code, record.rok, record.semestr)
            var grade = result[id] ?? SubjectGrade(
                code: code, department: record.katedra ?? "", year: record.rok ?? "", semester: record.semestr ?? "",
                name: nil, credits: nil, creditTest: nil, exam: nil, finalGrade: nil, isPassed: false, isRecognized: false
            )
            grade.creditTest = record.creditTest ?? grade.creditTest
            grade.exam = record.exam ?? grade.exam
            grade.isRecognized = record.predmetUznany ?? grade.isRecognized
            if let state = record.stavAbsolvovani?.uppercased(), ["A", "ANO", "S", "SPLNĚNO"].contains(state) {
                grade.isPassed = true
            }
            result[id] = grade
        }
        return Array(result.values)
    }

    // MARK: - Nové známky

    /// Vrátí nové nebo změněné známky. Při úplně prvním načtení nic nehlásí.
    private func detectNewGrades(in fresh: [SubjectGrade]) -> [SubjectGrade] {
        let defaults = AppGroup.defaults
        let isFirstSync = defaults?.object(forKey: Keys.seen) == nil
        let seen = Set(defaults?.stringArray(forKey: Keys.seen) ?? [])
        func signature(_ grade: SubjectGrade) -> String {
            "\(grade.id)|\(grade.creditTest?.result ?? "")|\(grade.exam?.result ?? "")|\(grade.finalGrade ?? "")"
        }
        let graded = fresh.filter { $0.displayGrade != nil }
        let changed = isFirstSync ? [] : graded.filter { !seen.contains(signature($0)) }
        defaults?.set(graded.map(signature), forKey: Keys.seen)
        return changed
    }

    private func notify(about changed: [SubjectGrade]) async {
        let enabled = UserDefaults.standard.object(forKey: Self.alertsEnabledKey) as? Bool ?? true
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        if changed.count == 1, let grade = changed.first, let value = grade.displayGrade {
            content.title = String(localized: "Nová známka: \(grade.code) – \(value)")
            content.body = grade.name ?? grade.code
        } else {
            let codes = changed.map(\.code).sorted().joined(separator: ", ")
            content.title = String(localized: "Máš \(changed.count) nových známek")
            content.body = codes
        }
        let request = UNNotificationRequest(identifier: "grade-new-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func persist() {
        guard !DemoMode.isActive else { return }
        guard let fetchedAt, let data = try? JSONEncoder().encode(Snapshot(grades: grades, fetchedAt: fetchedAt)) else { return }
        AppGroup.defaults?.set(data, forKey: Keys.snapshot)
    }
}

// Ukázkový režim – data jen v paměti, nic se neukládá
extension GradeStore {
    func loadDemo(_ grades: [SubjectGrade]) {
        self.grades = grades
        fetchedAt = .now
        errorMessage = nil
    }

    /// Po ukončení dema vrátí skutečné známky z App Group
    func reloadAfterDemo() {
        errorMessage = nil
        restoreFromCache()
    }
}
