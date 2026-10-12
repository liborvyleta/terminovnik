import Foundation
import Observation
import WatchConnectivity

/// Úložiště dat aplikace pro Apple Watch.
///
/// Přijímá application context, který přes WatchConnectivity posílá aplikace pro iPhone
/// (`WatchSync`), a to jak při aktivaci relace (`receivedApplicationContext`), tak živě
/// přes `session(_:didReceiveApplicationContext:)`. Z kontextu ponechá jen hodnoty typu
/// `Data`, `Date` a `Int`, dekóduje z nich rozvrh a deadliny a uloží ho do UserDefaults
/// hodinek. Při startu načte poslední uložený stav, takže aplikace funguje i bez spojení
/// s telefonem. Starší kontext nikdy nepřepíše novější.
@Observable
final class WatchStore: NSObject {
    /// Sdílená instance používaná aplikací.
    static let shared = WatchStore()

    /// Klíče application contextu.
    ///
    /// Hodnoty musí odpovídat `WatchSync.Key` v aplikaci pro iPhone, jinak hodinky
    /// přijatá data nerozpoznají.
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

    /// Udává, zda hodinky nemají žádná data k zobrazení.
    ///
    /// Platí, když rozvrh chybí nebo nemá žádné akce a zároveň není žádný deadline;
    /// aplikace pak zobrazí výzvu k otevření aplikace na iPhonu.
    var isEmpty: Bool {
        (timetable?.events.isEmpty ?? true) && deadlines.isEmpty
    }

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private static let storageKey = "watchContext.v1"

    /// Vytvoří sdílenou instanci a načte z UserDefaults naposledy uložený kontext.
    ///
    /// K iPhonu se nepřipojuje – to zajišťuje ``activate()``. V konfiguraci Debug
    /// s argumentem `-demo` místo toho naplní ukázková data a nic neukládá.
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

    /// Vytvoří instanci s pevnými daty pro náhledy a testy, bez WatchConnectivity a bez ukládání.
    ///
    /// - Parameters:
    ///   - timetable: Rozvrh, nebo `nil`, pokud rozvrh není k dispozici.
    ///   - deadlines: Deadliny k zobrazení.
    ///   - updatedAt: Čas poslední aktualizace dat; výchozí hodnota je aktuální čas.
    init(timetable: TimetableSnapshot?, deadlines: [WidgetDeadline], updatedAt: Date? = .now) {
        defaults = nil
        super.init()
        self.timetable = timetable
        self.deadlines = deadlines
        self.updatedAt = updatedAt
    }

    /// Aktivuje relaci WatchConnectivity a nastaví tuto instanci jako jejího delegáta.
    ///
    /// Nic neudělá u instance bez úložiště (náhledy, ukázkový režim), na zařízení bez
    /// podpory WatchConnectivity nebo pokud relace již delegáta má. Volá se jednou při startu aplikace.
    func activate() {
        guard defaults != nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Zpracování dat

    /// Vybere z kontextu jen hodnoty, které lze uložit do UserDefaults.
    ///
    /// - Parameter context: Application context přijatý z iPhonu.
    /// - Returns: Kontext obsahující pouze hodnoty typu `Data`, `Date` a `Int`.
    nonisolated static func storable(_ context: [String: Any]) -> [String: Any] {
        context.filter { $0.value is Data || $0.value is Date || $0.value is Int }
    }

    /// Zpracuje kontext přijatý z iPhonu: zobrazí jeho data a uloží ho do UserDefaults.
    ///
    /// Kontext odeslaný dříve než aktuálně zobrazená data se zahodí, stejně jako kontext
    /// v neznámém formátu.
    ///
    /// - Parameter context: Přijatý kontext s hodnotami vybranými pomocí ``storable(_:)``.
    private func receive(_ context: [String: Any]) {
        // Starší data nepřepíší novější (kontext z aktivace může přijít po živé aktualizaci)
        if let sentAt = context[Key.sentAt] as? Date, let updatedAt, sentAt < updatedAt { return }
        guard apply(context) else { return }
        defaults?.set(context, forKey: Self.storageKey)
    }

    /// Dekóduje kontext a nastaví z něj rozvrh, deadliny a čas aktualizace.
    ///
    /// Chybějící nebo nedekódovatelný rozvrh se nastaví na `nil` a deadliny na prázdné pole.
    ///
    /// - Parameter context: Kontext k dekódování.
    /// - Returns: `false`, pokud má kontext verzi vyšší než 1 (novější verze aplikace na iPhonu)
    ///   a data se nezměnila; jinak `true`.
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
    /// Po úspěšné aktivaci relace zpracuje poslední kontext, který iPhone poslal, zatímco aplikace neběžela.
    ///
    /// - Parameters:
    ///   - session: Relace WatchConnectivity.
    ///   - activationState: Výsledný stav aktivace; kontext se zpracuje jen ve stavu `.activated`.
    ///   - error: Chyba aktivace; nevyhodnocuje se.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        // Poslední kontext, který iPhone poslal, zatímco aplikace neběžela
        let context = Self.storable(session.receivedApplicationContext)
        guard !context.isEmpty else { return }
        nonisolated(unsafe) let sendable = context
        Task { @MainActor in self.receive(sendable) }
    }

    /// Zpracuje živě přijatý application context z iPhonu na hlavním vlákně.
    ///
    /// - Parameters:
    ///   - session: Relace WatchConnectivity.
    ///   - applicationContext: Přijatý kontext; ponechají se jen hodnoty vybrané pomocí ``storable(_:)``.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let context = Self.storable(applicationContext)
        Task { @MainActor in self.receive(context) }
    }
}

// MARK: - Výpočty pro obrazovky

extension WatchStore {
    /// Vrátí probíhající nebo nejbližší hodinu.
    ///
    /// - Parameter now: Okamžik, od kterého se hodina hledá; výchozí hodnota je aktuální čas.
    /// - Returns: Nejbližší výskyt hodiny, nebo `nil`, pokud rozvrh chybí nebo žádná hodina nenásleduje.
    func nextLesson(now: Date = .now) -> TimetableOccurrence? {
        timetable?.upcoming(after: now, limit: 1).first
    }

    /// Vrátí hodiny konané v daný den, včetně těch, které už skončily.
    ///
    /// - Parameter now: Okamžik určující den; výchozí hodnota je aktuální čas.
    /// - Returns: Výskyty hodin v daném dni, nebo prázdné pole, pokud rozvrh chybí.
    func todayLessons(now: Date = .now) -> [TimetableOccurrence] {
        timetable?.occurrences(on: now) ?? []
    }
}

#if DEBUG
// MARK: - Ukázkový režim (pouze Debug)

/// Ukázkový režim pro snímky obrazovky (pouze konfigurace Debug).
///
/// Spuštění s argumentem `-demo` naplní hodinky ukázkovými daty místo dat přijatých
/// přes WatchConnectivity. Argument `-page next|today|deadlines` určuje výchozí stránku.
enum DemoLaunch {
    /// Udává, zda byla aplikace spuštěna s argumentem `-demo`.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }

    /// Hodnota argumentu `-page`, nebo `nil`, pokud nebyl zadán.
    ///
    /// UserDefaults čte argumenty spuštění ve tvaru `-klíč hodnota`.
    static var page: String? {
        UserDefaults.standard.string(forKey: "page")
    }

    /// Ukázkový rozvrh, ve kterém se tři akce konají dnes: jedna už proběhla, další začíná
    /// za 20–34 minut a třetí po krátké přestávce. Časy jsou zaokrouhlené na čtvrthodiny,
    /// aby obrazovky „Další hodina“ i „Dnes“ vypadaly jako skutečný rozvrh v kteroukoli denní dobu.
    ///
    /// - Parameter now: Okamžik, ke kterému se rozvrh sestaví; výchozí hodnota je aktuální čas.
    /// - Returns: Upravená kopie `TimetableSnapshot.sample`.
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
