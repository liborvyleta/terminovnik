import Foundation
import Testing
@testable import ZavernyProjekt

/// Testy detekce změn rozvrhu (`TimetableChangeDetector`).
///
/// Porovnávají dva snímky rozvrhu. Kalendář Europe/Prague, „teď“ = pondělí 5. 10. 2026 8:00.
@Suite("Změny rozvrhu")
struct TimetableChangeDetectorTests {
    let calendar = TestCalendar.prague
    let now = makeDate(2026, 10, 5, 8, 0)

    /// Vytvoří rozvrhovou akci předmětu AP9PT s nastavitelnými vlastnostmi.
    ///
    /// - Parameters:
    ///   - id: Identifikátor akce.
    ///   - weekday: Den v týdnu, nebo `nil`.
    ///   - start: Čas začátku.
    ///   - end: Čas konce.
    ///   - building: Budova.
    ///   - room: Místnost.
    ///   - teacher: Vyučující.
    ///   - parity: Parita týdne.
    ///   - to: Konec platnosti akce.
    ///   - single: Datum jednorázové akce.
    /// - Returns: Nová rozvrhová akce.
    private func event(
        id: String = "1",
        weekday: Int? = 2,
        start: String = "09:45",
        end: String = "11:15",
        building: String = "U52",
        room: String = "204",
        teacher: String = "Ing. Novák",
        parity: String = "Každý",
        to: Date? = nil,
        single: Date? = nil
    ) -> TimetableEvent {
        TimetableEvent(id: id, subjectCode: "AP9PT", department: "AUIUI", subjectName: "Mobilní technologie",
                       typeName: "Přednáška", typeShort: "Př", weekday: weekday, startTime: start, endTime: end,
                       building: building, room: room, teacher: teacher, weekParity: parity,
                       dateFrom: nil, dateTo: to, singleDate: single, hexColor: nil)
    }

    /// Zabalí akce do snímku rozvrhu staženého v čase `now`.
    ///
    /// - Parameters:
    ///   - events: Akce rozvrhu.
    ///   - semester: Semestr, výchozí ZS.
    ///   - year: Akademický rok, výchozí 2026.
    /// - Returns: Nový snímek rozvrhu.
    private func snapshot(_ events: [TimetableEvent], semester: String = "ZS", year: String = "2026") -> TimetableSnapshot {
        TimetableSnapshot(events: events, semester: semester, academicYear: year, fetchedAt: now)
    }

    /// Porovná dva seznamy akcí a vrátí zjištěné změny.
    ///
    /// - Parameters:
    ///   - old: Původní akce.
    ///   - new: Nové akce.
    /// - Returns: Změny nalezené `TimetableChangeDetector.diff`.
    private func diff(_ old: [TimetableEvent], _ new: [TimetableEvent]) -> [TimetableChange] {
        TimetableChangeDetector.diff(old: snapshot(old), new: snapshot(new), now: now, calendar: calendar)
    }

    @Test("Beze změny (i při jiném pořadí a vyučujícím) → nic")
    func noChange() {
        let old = [event(id: "1"), event(id: "2", weekday: 3)]
        let new = [event(id: "2", weekday: 3), event(id: "1", building: " U52 ", teacher: "doc. Novák")]
        #expect(diff(old, new).isEmpty)
    }

    @Test("Zmizelá akce → zrušená hodina s nejbližším výskytem")
    func cancelled() {
        let changes = diff([event()], [])
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .cancelled)
        #expect(changes.first?.date == makeDate(2026, 10, 6, 9, 45))
    }

    @Test("Zkrácená platnost → zrušený konkrétní výskyt")
    func cancelledOccurrence() {
        let changes = diff([event()], [event(to: makeDate(2026, 10, 7))])
        #expect(changes.map(\.kind) == [.cancelled])
        #expect(changes.first?.date == makeDate(2026, 10, 13, 9, 45))
    }

    @Test("Přesun času a dne")
    func movedTime() throws {
        let changes = diff([event()], [event(weekday: 3, start: "11:30", end: "13:00")])
        #expect(changes.map(\.kind) == [.moved])
        let text = TimetableChangeDetector.describe(try #require(changes.first), calendar: calendar)
        #expect(text.contains("út 9:45"))
        #expect(text.contains("st 11:30"))
    }

    @Test("Změna místnosti")
    func movedRoom() throws {
        let changes = diff([event()], [event(room: "105")])
        #expect(changes.map(\.kind) == [.moved])
        #expect(TimetableChangeDetector.describe(try #require(changes.first), calendar: calendar).contains("U52/105"))
    }

    @Test("Nová hodina")
    func added() {
        let changes = diff([event()], [event(), event(id: "2", weekday: 4)])
        #expect(changes.map(\.kind) == [.added])
        #expect(changes.first?.event.id == "2")
    }

    @Test("Jiný semestr nebo chybějící starý rozvrh → nic")
    func differentSemester() {
        let old = snapshot([event()], semester: "LS")
        let new = snapshot([event(weekday: 5)])
        #expect(TimetableChangeDetector.diff(old: old, new: new, now: now, calendar: calendar).isEmpty)
        #expect(TimetableChangeDetector.diff(old: nil, new: new, now: now, calendar: calendar).isEmpty)
        let otherYear = snapshot([event()], year: "2025")
        #expect(TimetableChangeDetector.diff(old: otherYear, new: new, now: now, calendar: calendar).isEmpty)
    }

    @Test("Proběhlé hodiny se ignorují")
    func pastIgnored() {
        let past = event(id: "p", weekday: nil, single: makeDate(2026, 10, 1))
        #expect(diff([past], []).isEmpty)
        #expect(diff([past], [event(id: "p", weekday: nil, room: "999", single: makeDate(2026, 10, 1))]).isEmpty)
        // Akce s platností jen do minulosti
        let ended = event(id: "e", to: makeDate(2026, 9, 30))
        #expect(diff([ended], []).isEmpty)
    }

    @Test("Víc změn → souhrnné oznámení, otisk nezávisí na pořadí")
    func summary() {
        let changes = diff([event(id: "1"), event(id: "2", weekday: 3)], [event(id: "2", weekday: 4), event(id: "3", weekday: 5)])
        #expect(changes.count == 3)
        let text = TimetableChangeDetector.notificationText(for: changes, calendar: calendar)
        #expect(text.title.contains("3"))
        #expect(text.body.split(separator: "\n").count == 3)
        #expect(TimetableChangeDetector.fingerprint(of: changes) == TimetableChangeDetector.fingerprint(of: changes.reversed()))
    }
}
