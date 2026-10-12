import Foundation
import Observation
import WatchConnectivity

/// Data hodinek: přijímá application context z iPhonu (`WatchSync` v aplikaci pro iPhone),
/// ukládá ho do UserDefaults hodinek a při startu načte poslední známý stav,
/// takže aplikace funguje i bez spojení s telefonem.
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()

    /// Klíče application contextu – musí odpovídat `WatchSync.Key` v aplikaci pro iPhone
    enum Key {
        static let version = "v"
        static let deadlines = "deadlines"
        static let timetable = "timetable"
        static let sentAt = "sentAt"
    }

    /// Rozvrh (nil = uživatel není přihlášený do STAGu nebo data ještě nepřišla)
    private(set) var timetable: TimetableSnapshot?
    /// Nejbližší nesplněné deadliny seřazené od nejbližšího
    private(set) var deadlines: [WidgetDeadline] = []
    /// Kdy iPhone data naposledy poslal (nil = zatím nic nepřišlo)
    private(set) var updatedAt: Date?

    /// Žádná data – zobrazí se výzva k otevření aplikace na iPhonu
    var isEmpty: Bool {
        (timetable?.events.isEmpty ?? true) && deadlines.isEmpty
    }

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private static let storageKey = "watchContext.v1"

    /// Aplikace: načte uložená data a připojí se k iPhonu
    private override init() {
        #if DEBUG
        if DemoLaunch.isEnabled {
            // Ukázkový režim pro snímky obrazovky: pevná data, bez ukládání a bez WatchConnectivity
            defaults = nil
            super.init()
            timetable = DemoLaunch.timetable()
            deadlines = WidgetDeadline.watchSamples.filter { $0.dueDate > .now }
            updatedAt = .now
            return
        }
        #endif
        defaults = .standard
        super.init()
        if let stored = defaults?.dictionary(forKey: Self.storageKey) {
            apply(stored)
        }
    }

    /// Náhledy a testy: pevná data, bez WatchConnectivity a bez ukládání
    init(timetable: TimetableSnapshot?, deadlines: [WidgetDeadline], updatedAt: Date? = .now) {
        defaults = nil
        super.init()
        self.timetable = timetable
        self.deadlines = deadlines
        self.updatedAt = updatedAt
    }

    /// Aktivuje WatchConnectivity. Volá se jednou při startu aplikace.
    func activate() {
        guard defaults != nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Zpracování dat

    /// Vybere z kontextu jen hodnoty, které umíme uložit (Data, Date, Int)
    nonisolated static func storable(_ context: [String: Any]) -> [String: Any] {
        context.filter { $0.value is Data || $0.value is Date || $0.value is Int }
    }

    /// Přijatý kontext z iPhonu: uložit a zobrazit
    private func receive(_ context: [String: Any]) {
        // Starší data nepřepíší novější (kontext z aktivace může přijít po živé aktualizaci)
        if let sentAt = context[Key.sentAt] as? Date, let updatedAt, sentAt < updatedAt { return }
        guard apply(context) else { return }
        defaults?.set(context, forKey: Self.storageKey)
    }

    /// Dekóduje kontext. Vrací false, když formát neznáme (novější verze aplikace na iPhonu).
    @discardableResult
    private func apply(_ context: [String: Any]) -> Bool {
        if let version = context[Key.version] as? Int, version > 1 { return false }
        let decoder = JSONDecoder()
        timetable = (context[Key.timetable] as? Data).flatMap { try? decoder.decode(TimetableSnapshot.self, from: $0) }
        deadlines = (context[Key.deadlines] as? Data)
            .flatMap { try? decoder.decode(WidgetSnapshot.self, from: $0) }?
            .deadlines ?? []
        updatedAt = context[Key.sentAt] as? Date
        return true
    }
}

// MARK: - WCSessionDelegate

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        // Poslední kontext, který iPhone poslal, zatímco aplikace neběžela
        let context = Self.storable(session.receivedApplicationContext)
        guard !context.isEmpty else { return }
        nonisolated(unsafe) let sendable = context
        Task { @MainActor in self.receive(sendable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let context = Self.storable(applicationContext)
        Task { @MainActor in self.receive(context) }
    }
}

// MARK: - Výpočty pro obrazovky

extension WatchStore {
    /// Probíhající nebo nejbližší hodina
    func nextLesson(now: Date = .now) -> TimetableOccurrence? {
        timetable?.upcoming(after: now, limit: 1).first
    }

    /// Dnešní hodiny (včetně těch, které už skončily)
    func todayLessons(now: Date = .now) -> [TimetableOccurrence] {
        timetable?.occurrences(on: now) ?? []
    }
}

#if DEBUG
// MARK: - Ukázkový režim (pouze Debug)

/// Spuštění s argumentem `-demo` naplní hodinky ukázkovými daty pro snímky obrazovky.
/// Argument `-page next|today|deadlines` určuje výchozí stránku.
enum DemoLaunch {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }

    /// Hodnota argumentu `-page` (UserDefaults čte argumenty spuštění ve tvaru `-klíč hodnota`)
    static var page: String? {
        UserDefaults.standard.string(forKey: "page")
    }

    /// Ukázkový rozvrh, ve kterém se tři akce konají dnes: jedna už proběhla, další začíná
    /// za 20–34 minut a třetí po krátké přestávce. Časy jsou zaokrouhlené na čtvrthodiny,
    /// aby obrazovky „Další hodina“ i „Dnes“ vypadaly jako skutečný rozvrh v kteroukoli denní dobu.
    static func timetable(now: Date = .now) -> TimetableSnapshot {
        let sample = TimetableSnapshot.sample
        let calendar = Calendar.current
        // Calendar.weekday: 1 = neděle; TimetableEvent.weekday: 1 = pondělí
        let today = (calendar.component(.weekday, from: now) + 5) % 7 + 1
        let minutesNow = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        // Další hodina začíná na nejbližší čtvrthodinu alespoň 20 minut od teď;
        // celý blok (90 + 15 + 90 minut) musí skončit před půlnocí
        let next = min((minutesNow + 20 + 14) / 15 * 15, (24 * 60 - 1 - 195) / 15 * 15)
        let plan: [String: (from: Int, to: Int)] = [
            "s2": (-150, -60),   // proběhlá hodina
            "s1": (0, 90),       // další hodina
            "s4": (105, 195)     // následující hodina po přestávce
        ]
        let start = next

        func time(_ minutes: Int) -> String {
            String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }

        let events = sample.events.map { event -> TimetableEvent in
            guard let offset = plan[event.id] else { return event }
            return TimetableEvent(
                id: event.id, subjectCode: event.subjectCode, department: event.department,
                subjectName: event.subjectName, typeName: event.typeName, typeShort: event.typeShort,
                weekday: today, startTime: time(max(0, start + offset.from)), endTime: time(max(0, start + offset.to)),
                building: event.building, room: event.room, teacher: event.teacher,
                weekParity: event.weekParity, dateFrom: nil, dateTo: nil, singleDate: nil,
                hexColor: event.hexColor
            )
        }
        return TimetableSnapshot(events: events, semester: sample.semester,
                                 academicYear: sample.academicYear, fetchedAt: now)
    }
}
#endif
