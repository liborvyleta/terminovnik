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
