import Foundation
import ActivityKit
import SwiftData

/// Spouští, aktualizuje a ukončuje Live Activity (zamčená obrazovka + Dynamic Island).
///
/// Používá ho aplikace po načtení rozvrhu a při návratu do popředí, detail hodiny a Přehled.
/// Rozvrh čte z `TimetableSnapshot`, barvy předmětů ze SwiftData a evidenci ručně spuštěných aktivit
/// ukládá do `UserDefaults.standard`.
///
/// - Hodina z rozvrhu se spouští automaticky (``LiveActivityManager/updateLessonActivity(now:)``), když právě probíhá
///   nebo začíná do 60 minut, a také ručně z detailu hodiny (``LiveActivityManager/startLesson(_:)``).
/// - Zkouška / deadline se spouští ručně z kontextové nabídky na Přehledu (``LiveActivityManager/startExam(_:)``).
///
/// Vzhled aktivity kreslí widget (`StudyActivityAttributes` je sdílený typ).
/// - Important: V ukázkovém režimu (``DemoMode``) se žádné aktivity nespouštějí.
@MainActor
final class LiveActivityManager {
    /// Sdílená instance používaná celou aplikací.
    static let shared = LiveActivityManager()

    /// Klíč přepínače v Nastavení – automatické sledování hodin (výchozí zapnuto)
    static let lessonEnabledKey = "lessonLiveActivityEnabled"

    /// Za jak dlouho před začátkem se hodina spustí automaticky
    private let autoStartLead: TimeInterval = 60 * 60
    /// Nejdelší předstih pro ruční spuštění (Live Activity systém stejně ukončí po 8 h)
    private let manualStartLead: TimeInterval = 8 * 60 * 60
    /// Jak dlouho po skončení zůstane aktivita na zamčené obrazovce
    private let dismissalDelay: TimeInterval = 5 * 60
    /// Délka zkoušky, když v aplikaci není uvedená
    private let examDuration: TimeInterval = 2 * 60 * 60

    /// ID aktivit spuštěných ručně – automatika je neukončí, jen když už skončily
    private let manualIDsKey = "liveActivity.manualLessonIDs"

    /// Naplánované obnovení po skončení hodiny (funguje, dokud aplikace běží)
    private var refreshTask: Task<Void, Never>?

    /// Soukromý inicializátor – používá se jen ``LiveActivityManager/shared``.
    private init() {}

    // MARK: - Stav

    /// Má uživatel zapnuté automatické sledování hodin? (výchozí ano)
    var isLessonAutoEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.lessonEnabledKey) as? Bool ?? true
    }

    /// Povolil uživatel Živé aktivity v systémovém Nastavení?
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Zjistí, zda lze hodinu ručně sledovat – ještě neskončila a začíná nejpozději za 8 hodin.
    ///
    /// - Parameters:
    ///   - occurrence: Konkrétní výskyt hodiny z rozvrhu.
    ///   - now: Aktuální čas (pro testy).
    /// - Returns: `true`, pokud lze aktivitu spustit.
    func canStartLesson(_ occurrence: TimetableOccurrence, now: Date = .now) -> Bool {
        occurrence.end > now && occurrence.start <= now.addingTimeInterval(manualStartLead)
    }

    /// Zjistí, zda lze ke zkoušce / deadlinu spustit odpočet – nesplněný termín v budoucnu a nejpozději za 8 hodin.
    ///
    /// - Parameters:
    ///   - task: Zkouška nebo úkol.
    ///   - now: Aktuální čas (pro testy).
    /// - Returns: `true`, pokud lze odpočet spustit.
    func canStartExam(_ task: ExamTask, now: Date = .now) -> Bool {
        !task.isCompleted && task.dueDate > now && task.dueDate <= now.addingTimeInterval(manualStartLead)
    }

    /// Zjistí, zda se tato hodina už sleduje na zamčené obrazovce.
    ///
    /// - Parameter occurrence: Výskyt hodiny (porovnává se kód předmětu a začátek).
    /// - Returns: `true`, pokud pro hodinu běží aktivita.
    func isTracking(_ occurrence: TimetableOccurrence) -> Bool {
        let code = occurrence.event.subjectCode
        return runningActivities.contains {
            $0.attributes.kind == .lesson
                && $0.attributes.subjectCode == code
                && $0.content.state.start == occurrence.start
        }
    }

    // MARK: - Automatika pro hodiny

    /// Spustí / aktualizuje aktivitu pro hodinu, která probíhá nebo začíná do 60 minut.
    ///
    /// Volá se po načtení rozvrhu a při návratu aplikace do popředí. Vždy uklidí skončené hodiny;
    /// je-li automatika vypnutá, ukončí jen automaticky spuštěné aktivity. Jinak ukončí automatické aktivity,
    /// které neodpovídají aktuální hodině, spustí nebo aktualizuje tu správnou a naplánuje obnovení po jejím konci.
    ///
    /// - Parameter now: Aktuální čas (pro testy).
    func updateLessonActivity(now: Date = .now) {
        // Ukázkový režim: žádné živé aktivity z demo rozvrhu
        guard !DemoMode.isActive else { return }
        refreshTask?.cancel()
        refreshTask = nil

        // Hodiny, které už skončily, uklidíme vždy (i ty spuštěné ručně)
        let lessons = runningActivities.filter { $0.attributes.kind == .lesson }
        for activity in lessons where activity.content.state.end <= now {
            end(activity, now: now)
        }

        guard isLessonAutoEnabled, areActivitiesEnabled else {
            // Automatika je vypnutá – ukončíme jen automaticky spuštěné, ruční necháme doběhnout
            for activity in lessons where !isManual(activity) && activity.content.state.end > now {
                end(activity, now: now, immediately: true)
            }
            return
        }

        let candidate = TimetableSnapshot.load()?
            .upcoming(after: now, limit: 1)
            .first
            .flatMap { $0.start <= now.addingTimeInterval(autoStartLead) ? $0 : nil }

        // Automatické aktivity, které už neodpovídají aktuální hodině, ukončíme
        for activity in lessons where activity.content.state.end > now && !isManual(activity) {
            if let candidate, matches(activity, candidate) { continue }
            end(activity, now: now, immediately: true)
        }

        guard let candidate else { return }
        startOrUpdate(lessonRequest(for: candidate))
        scheduleRefresh(at: candidate.end.addingTimeInterval(1))
    }

    // MARK: - Ruční spuštění

    /// Ručně spustí sledování hodiny z detailu hodiny.
    ///
    /// Aktivitu označí jako ruční, takže ji automatika neukončí dřív, než hodina skončí.
    ///
    /// - Parameter occurrence: Výskyt hodiny z rozvrhu.
    /// - Returns: `true`, pokud aktivita běží.
    @discardableResult
    func startLesson(_ occurrence: TimetableOccurrence) -> Bool {
        guard canStartLesson(occurrence) else { return false }
        guard let activity = startOrUpdate(lessonRequest(for: occurrence)) else { return false }
        markManual(activity)
        return true
    }

    /// Spustí odpočet ke zkoušce / deadlinu.
    ///
    /// U zkoušky počítá s délkou 2 hodiny, u ostatních typů končí aktivita v okamžiku termínu.
    ///
    /// - Parameter task: Zkouška nebo úkol z Přehledu.
    /// - Returns: `true`, pokud aktivita běží.
    @discardableResult
    func startExam(_ task: ExamTask) -> Bool {
        guard canStartExam(task) else { return false }
        let start = task.dueDate
        let end = task.taskType == .zkouska ? start.addingTimeInterval(examDuration) : start
        let attributes = StudyActivityAttributes(
            kind: .exam,
            subjectCode: task.subject?.code ?? "",
            title: task.title,
            typeName: task.taskType.title,
            hexColor: task.subject?.hexColor ?? Self.fallbackHex
        )
        let state = StudyActivityAttributes.ContentState(start: start, end: end, location: Self.shortNote(task.note))
        return startOrUpdate(ActivityRequest(attributes: attributes, state: state)) != nil
    }

    /// Okamžitě ukončí všechny aktivity aplikace (hodiny i zkoušky) a smaže evidenci ručně spuštěných.
    func endAll() {
        refreshTask?.cancel()
        refreshTask = nil
        for activity in Activity<StudyActivityAttributes>.activities {
            end(activity, now: .now, immediately: true)
        }
        UserDefaults.standard.removeObject(forKey: manualIDsKey)
    }

    // MARK: - Ukázka pro snímky obrazovky

    #if DEBUG
    /// Spustí ukázkovou hodinu (první z `TimetableSnapshot.sample`), která začíná za 12 minut.
    ///
    /// Hodí se pro snímky obrazovky bez reálného rozvrhu. Dostupné jen v buildu DEBUG.
    func startDemoLesson() {
        guard let event = TimetableSnapshot.sample.events.first else { return }
        let duration = TimeInterval(((event.endMinutes ?? 60) - (event.startMinutes ?? 0)) * 60)
        let start = Date.now.addingTimeInterval(12 * 60)
        let occurrence = TimetableOccurrence(event: event, start: start, end: start.addingTimeInterval(max(duration, 15 * 60)))
        startLesson(occurrence)
    }
    #endif

    // MARK: - Spouštění a ukončování

    /// Data pro spuštění aktivity.
    ///
    /// Spojuje statické atributy a proměnný stav, aby se dala porovnat s běžícími aktivitami.
    private struct ActivityRequest {
        let attributes: StudyActivityAttributes
        let state: StudyActivityAttributes.ContentState
    }

    /// Barva aktivity, když předmět žádnou nemá.
    private static let fallbackHex = "#3E63DD"

    /// Aktivity aplikace, které ještě nejsou ukončené (aktivní nebo zastaralé).
    private var runningActivities: [Activity<StudyActivityAttributes>] {
        Activity<StudyActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    /// Sestaví požadavek na aktivitu pro hodinu z rozvrhu.
    ///
    /// Barvu bere z rozvrhu, pak z předmětu v aplikaci, jinak použije výchozí.
    ///
    /// - Parameter occurrence: Výskyt hodiny.
    /// - Returns: Atributy a stav aktivity typu hodina.
    private func lessonRequest(for occurrence: TimetableOccurrence) -> ActivityRequest {
        let event = occurrence.event
        let attributes = StudyActivityAttributes(
            kind: .lesson,
            subjectCode: event.subjectCode,
            title: event.subjectName,
            typeName: event.typeName,
            hexColor: event.hexColor ?? subjectHex(for: event.subjectCode) ?? Self.fallbackHex
        )
        let state = StudyActivityAttributes.ContentState(
            start: occurrence.start,
            end: occurrence.end,
            location: event.locationText
        )
        return ActivityRequest(attributes: attributes, state: state)
    }

    /// Spustí novou aktivitu, nebo aktualizuje už běžící stejnou (žádné duplicity).
    ///
    /// Aktualizace běžící aktivity proběhne asynchronně na pozadí jen při změně stavu.
    ///
    /// - Parameter request: Atributy a stav aktivity.
    /// - Returns: Běžící nebo nově spuštěnou aktivitu; `nil` v ukázkovém režimu, při vypnutých
    ///   Živých aktivitách nebo při selhání spuštění.
    @discardableResult
    private func startOrUpdate(_ request: ActivityRequest) -> Activity<StudyActivityAttributes>? {
        guard !DemoMode.isActive else { return nil }
        let content = ActivityContent(state: request.state, staleDate: request.state.end)

        if let existing = runningActivities.first(where: { matches($0, request) }) {
            if existing.content.state != request.state {
                Task { await existing.update(content) }
            }
            return existing
        }

        guard areActivitiesEnabled else {
            print("LiveActivity: Živé aktivity jsou v Nastavení iOS vypnuté")
            return nil
        }
        do {
            return try Activity.request(attributes: request.attributes, content: content, pushType: nil)
        } catch {
            print("LiveActivity: spuštění selhalo – \(error.localizedDescription)")
            return nil
        }
    }

    /// Ukončí aktivitu. Po skončení hodiny ji ještě pár minut nechá na zamčené obrazovce.
    ///
    /// Samotné ukončení proběhne asynchronně; aktivita se zároveň odebere z evidence ručních.
    ///
    /// - Parameters:
    ///   - activity: Ukončovaná aktivita.
    ///   - now: Aktuální čas pro výpočet, zda už prodleva uplynula.
    ///   - immediately: `true` = odstranit ze zamčené obrazovky hned.
    private func end(_ activity: Activity<StudyActivityAttributes>, now: Date, immediately: Bool = false) {
        let state = activity.content.state
        let dismissAt = state.end.addingTimeInterval(dismissalDelay)
        let policy: ActivityUIDismissalPolicy = (immediately || dismissAt <= now) ? .immediate : .after(dismissAt)
        let content = ActivityContent(state: state, staleDate: nil)
        unmarkManual(activity)
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// Naplánuje přepnutí na další hodinu po skončení té aktuální (jen pokud aplikace pořád běží).
    ///
    /// Vytvoří asynchronní úlohu, která po uplynutí doby zavolá ``LiveActivityManager/updateLessonActivity(now:)``.
    ///
    /// - Parameter date: Okamžik obnovení; v minulosti se nic neplánuje.
    private func scheduleRefresh(at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.updateLessonActivity()
        }
    }

    // MARK: - Porovnání

    /// Zjistí, zda běžící aktivita odpovídá požadavku (stejný druh, předmět a začátek).
    ///
    /// - Parameters:
    ///   - activity: Běžící aktivita.
    ///   - request: Požadavek na aktivitu.
    /// - Returns: `true`, pokud jde o tutéž aktivitu.
    private func matches(_ activity: Activity<StudyActivityAttributes>, _ request: ActivityRequest) -> Bool {
        activity.attributes.kind == request.attributes.kind
            && activity.attributes.subjectCode == request.attributes.subjectCode
            && activity.content.state.start == request.state.start
    }

    /// Zjistí, zda běžící aktivita patří k danému výskytu hodiny.
    ///
    /// - Parameters:
    ///   - activity: Běžící aktivita.
    ///   - occurrence: Výskyt hodiny z rozvrhu.
    /// - Returns: `true`, pokud jde o hodinu stejného předmětu se stejným začátkem.
    private func matches(_ activity: Activity<StudyActivityAttributes>, _ occurrence: TimetableOccurrence) -> Bool {
        activity.attributes.kind == .lesson
            && activity.attributes.subjectCode == occurrence.event.subjectCode
            && activity.content.state.start == occurrence.start
    }

    // MARK: - Ručně spuštěné aktivity

    /// ID ručně spuštěných aktivit uložená v `UserDefaults.standard`.
    private var manualIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: manualIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: manualIDsKey) }
    }

    /// Zjistí, zda byla aktivita spuštěna ručně.
    ///
    /// - Parameter activity: Kontrolovaná aktivita.
    /// - Returns: `true`, pokud je v evidenci ručních aktivit.
    private func isManual(_ activity: Activity<StudyActivityAttributes>) -> Bool {
        manualIDs.contains(activity.id)
    }

    /// Zapíše aktivitu do evidence ručních a zároveň z ní odstraní ID už neexistujících aktivit.
    ///
    /// - Parameter activity: Ručně spuštěná aktivita.
    private func markManual(_ activity: Activity<StudyActivityAttributes>) {
        // Uklidíme ID aktivit, které už v systému nejsou
        let alive = Set(Activity<StudyActivityAttributes>.activities.map(\.id))
        manualIDs = manualIDs.intersection(alive).union([activity.id])
    }

    /// Odebere aktivitu z evidence ručních (zapisuje jen při skutečné změně).
    ///
    /// - Parameter activity: Ukončovaná aktivita.
    private func unmarkManual(_ activity: Activity<StudyActivityAttributes>) {
        guard manualIDs.contains(activity.id) else { return }
        manualIDs.remove(activity.id)
    }

    // MARK: - Pomocné

    /// Najde barvu předmětu v aplikaci podle kódu.
    ///
    /// - Parameter code: Kód předmětu (přesná shoda).
    /// - Returns: Hex barva předmětu, nebo `nil`, pokud předmět neexistuje nebo dotaz selže.
    private func subjectHex(for code: String) -> String? {
        var descriptor = FetchDescriptor<Subject>(predicate: #Predicate { $0.code == code })
        descriptor.fetchLimit = 1
        return (try? PersistenceController.shared.mainContext.fetch(descriptor))?.first?.hexColor
    }

    /// Vrátí první řádek poznámky (místnost, pomůcky…), nejvýše 40 znaků.
    ///
    /// - Parameter note: Poznámka úkolu.
    /// - Returns: Oříznutý první řádek (delší zkrácený se „…“), nebo `nil`, pokud je prázdný.
    private static func shortNote(_ note: String) -> String? {
        guard let line = note.split(whereSeparator: \.isNewline).first?
            .trimmingCharacters(in: .whitespaces), !line.isEmpty else { return nil }
        return line.count > 40 ? String(line.prefix(39)) + "…" : line
    }
}
