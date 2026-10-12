import Foundation
import WatchConnectivity

/// Posílá data do aplikace Termínovník na Apple Watch přes WatchConnectivity.
///
/// Hodinky nemají přístup k SwiftData ani k App Group iPhonu, proto dostávají stejné „snímky“
/// jako widget: nejbližší deadliny (`WidgetSnapshot`) a rozvrh (`TimetableSnapshot`).
/// Používá se `updateApplicationContext` – systém doručí vždy jen nejnovější stav,
/// i když hodinky zrovna nejsou v dosahu (přenese se, jakmile se spojí).
///
/// Formát kontextu (klíče musí odpovídat `WatchStore` v cíli hodinek):
/// - `"v"`: verze formátu (Int)
/// - `"deadlines"`: JSON `WidgetSnapshot` (Data)
/// - `"timetable"`: JSON `TimetableSnapshot` (Data) – chybí, pokud rozvrh není (odhlášení ze STAGu)
/// - `"sentAt"`: okamžik odeslání (Date)
///
/// Volá ho ``WidgetSync/refresh(from:)`` a sám sleduje změny `UserDefaults` (uložení rozvrhu do App Group).
final class WatchSync: NSObject {
    /// Sdílená instance (delegát relace)
    static let shared = WatchSync()

    /// Klíče a verze application contextu
    enum Key {
        /// Verze formátu (Int)
        static let version = "v"
        /// JSON `WidgetSnapshot` (Data)
        static let deadlines = "deadlines"
        /// JSON `TimetableSnapshot` (Data), volitelně
        static let timetable = "timetable"
        /// Okamžik odeslání (Date)
        static let sentAt = "sentAt"
    }
    /// Aktuální verze formátu kontextu – musí odpovídat `WatchStore` na hodinkách
    static let formatVersion = 1

    /// Kolik deadlinů hodinky dostanou (zobrazí se seznam, víc nemá na malém displeji smysl)
    static let deadlineLimit = 10
    /// Nejvýše tolik rozvrhových akcí – pojistka proti příliš velkému kontextu
    static let eventLimit = 150

    /// Výchozí relace WatchConnectivity, nebo `nil`, pokud zařízení WatchConnectivity nepodporuje.
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Podpis naposledy odeslaných dat (bez časových razítek) – stejná data neposíláme znovu
    private var lastSignature: Data?
    /// Odložené odeslání po změně v UserDefaults (rozvrh se ukládá asynchronně po stažení ze STAGu)
    private var debounceTask: Task<Void, Never>?
    /// Pozorovatel `UserDefaults.didChangeNotification` (aktivní jen se spárovanými hodinkami)
    private var defaultsObserver: NSObjectProtocol?
    /// Spárované hodinky s nainstalovanou aplikací. Zjišťuje se jen po aktivaci a při změně stavu –
    /// dotaz na `isPaired` bez hodinek (simulátor) zahlcuje konzoli hláškou „WCSession is not paired“.
    private var hasWatchApp = false

    /// Soukromý inicializátor – používá se jen ``shared``.
    private override init() {
        super.init()
    }

    /// Aktivuje relaci WatchConnectivity. Volá se jednou při startu aplikace.
    ///
    /// Opakované volání (delegát už nastaven) nebo nepodporované zařízení nic nedělá.
    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()

    }

    /// Odešle hodinkám aktuální deadliny a rozvrh z App Group.
    ///
    /// Neodesílá před aktivací relace, bez spárovaných hodinek s aplikací ani když se podpis dat nezměnil.
    /// - Parameter force: odeslat i tehdy, když se data od minula nezměnila
    /// - Note: V ukázkovém režimu se nic neodesílá – hodinky ukazují skutečná data.
    func push(force: Bool = false) {
        guard !DemoMode.isActive else { return }
        guard let session else { return }
        // Před dokončením aktivace neposíláme – po aktivaci se data odešlou automaticky
        guard session.activationState == .activated else { return }
        // Bez spárovaných hodinek s nainstalovanou aplikací nemá odesílání smysl
        guard hasWatchApp else { return }

        let deadlines = WidgetSnapshot.load() ?? WidgetSnapshot(deadlines: [], generatedAt: .now)
        let timetable = TimetableSnapshot.load()
        let payload = Self.payload(deadlines: deadlines, timetable: timetable)

        if !force, let signature = payload.signature, signature == lastSignature { return }

        do {
            try session.updateApplicationContext(payload.context)
            lastSignature = payload.signature
        } catch {
            // Selhání se neošetřuje – podpis se neuložil, takže další push pošle aktuální stav
        }
    }

    /// Načte stav hodinek (jen z callbacků relace) a podle něj zapne nebo vypne sledování změn.
    ///
    /// Nakonec vždy vynutí odeslání aktuálních dat.
    /// - Parameter session: relace, ze které se čte `isPaired` a `isWatchAppInstalled`
    private func updateWatchState(_ session: WCSession) {
        hasWatchApp = session.isPaired && session.isWatchAppInstalled
        if hasWatchApp, defaultsObserver == nil {
            // Rozvrh i deadliny se ukládají do App Group – po každé změně (uložení rozvrhu ze STAGu,
            // smazání po odhlášení…) pošleme hodinkám aktuální stav. Odeslání je odložené a stejná
            // data se neposílají znovu, takže časté změny jiných nastavení nevadí.
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { WatchSync.shared.schedulePush() }
            }
        } else if !hasWatchApp, let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
            defaultsObserver = nil
            debounceTask?.cancel()
        }
        push(force: true)
    }

    /// Naplánuje odložené (1 s) odeslání; předchozí čekající odeslání zruší.
    private func schedulePush() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    // MARK: - Sestavení dat

    /// Application context a podpis dat (pro rozpoznání změny).
    ///
    /// Deadliny ořízne na ``deadlineLimit``, rozvrh přes ``trimmed(_:now:calendar:)``; JSON se kóduje se seřazenými klíči.
    /// - Parameters:
    ///   - deadlines: snímek deadlinů z widgetu
    ///   - timetable: snímek rozvrhu, nebo `nil` bez rozvrhu
    ///   - now: okamžik odeslání a referenční čas pro ořez rozvrhu
    /// - Returns: Slovník pro `updateApplicationContext` a podpis obsahu bez časových razítek.
    static func payload(deadlines: WidgetSnapshot, timetable: TimetableSnapshot?, now: Date = .now)
        -> (context: [String: Any], signature: Data?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let trimmedDeadlines = WidgetSnapshot(
            deadlines: Array(deadlines.deadlines.prefix(deadlineLimit)),
            generatedAt: deadlines.generatedAt
        )
        let trimmedTimetable = timetable.map { trimmed($0, now: now) }

        var context: [String: Any] = [
            Key.version: formatVersion,
            Key.sentAt: now
        ]
        if let data = try? encoder.encode(trimmedDeadlines) {
            context[Key.deadlines] = data
        }
        if let trimmedTimetable, let data = try? encoder.encode(trimmedTimetable) {
            context[Key.timetable] = data
        }

        // Podpis bez časových razítek – jen obsah, který hodinky zobrazují
        var signature = (try? encoder.encode(trimmedDeadlines.deadlines)) ?? Data()
        signature.append((try? encoder.encode(trimmedTimetable?.events ?? [])) ?? Data())
        signature.append(Data((trimmedTimetable == nil ? "-" : "+").utf8))
        return (context, signature)
    }

    /// Rozvrh bez akcí, které hodinky nikdy nezobrazí: skončené akce, jednorázové akce v minulosti
    /// a akce bez pevného dne a času. Omezí i počet akcí, aby kontext zůstal malý.
    /// - Parameters:
    ///   - snapshot: původní rozvrh
    ///   - now: referenční okamžik („dnes“)
    ///   - calendar: kalendář pro výpočet začátku dne
    /// - Returns: Kopie rozvrhu s nejvýše ``eventLimit`` akcemi.
    static func trimmed(_ snapshot: TimetableSnapshot, now: Date, calendar: Calendar = .current) -> TimetableSnapshot {
        let today = calendar.startOfDay(for: now)
        let events = snapshot.events.filter { event in
            if let singleDate = event.singleDate {
                return calendar.startOfDay(for: singleDate) >= today
            }
            guard event.weekday != nil, event.startTime != nil, event.endTime != nil else { return false }
            if let dateTo = event.dateTo, calendar.startOfDay(for: dateTo) < today { return false }
            return true
        }
        var result = snapshot
        result.events = Array(events.prefix(eventLimit))
        return result
    }
}

// MARK: - WCSessionDelegate

extension WatchSync: WCSessionDelegate {
    /// Dokončení aktivace relace – po úspěchu na hlavním vlákně zjistí stav hodinek a odešle data.
    /// - Parameters:
    ///   - session: aktivovaná relace
    ///   - activationState: výsledný stav aktivace
    ///   - error: chyba aktivace (neošetřuje se)
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            // Po aktivaci zjistíme stav hodinek a pošleme aktuální data (hodinky mohly přijít o data)
            self.updateWatchState(session)
        }
    }

    /// Změna spárování / instalace aplikace na hodinkách → poslat data znovu.
    /// - Parameter session: relace se změněným stavem
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateWatchState(session) }
    }

    /// Relace přestala být aktivní (přepínání hodinek) – není potřeba nic dělat.
    /// - Parameter session: neaktivní relace
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Přepnutí na jiné hodinky – relaci je potřeba znovu aktivovat.
    /// - Parameter session: deaktivovaná relace
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
