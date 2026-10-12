import Foundation
import Testing
@testable import ZavernyProjekt

/// Testy výpočtů nad rozvrhem.
///
/// Pokrývají výpočty nad `TimetableEvent` a `TimetableSnapshot`.
/// Kalendář Europe/Prague. Orientace: 5. 10. 2026 = pondělí (ISO týden 41, lichý), 12. 10. 2026 = pondělí (týden 42, sudý).
@Suite("Rozvrh")
struct TimetableTests {
    let calendar = TestCalendar.prague

    /// Vytvoří rozvrhovou akci (cvičení) s nastavitelnými vlastnostmi.
    ///
    /// - Parameters:
    ///   - id: Identifikátor akce.
    ///   - code: Zkratka předmětu.
    ///   - weekday: Den v týdnu, nebo `nil`.
    ///   - start: Čas začátku.
    ///   - end: Čas konce.
    ///   - parity: Parita týdne.
    ///   - from: Začátek platnosti.
    ///   - to: Konec platnosti.
    ///   - single: Datum jednorázové akce.
    ///   - building: Budova.
    ///   - room: Místnost.
    /// - Returns: Nová rozvrhová akce.
    private func event(
        id: String = "1",
        code: String = "AP9PT",
        weekday: Int? = 2,
        start: String? = "10:00",
        end: String? = "11:30",
        parity: String? = "Každý",
        from: Date? = nil,
        to: Date? = nil,
        single: Date? = nil,
        building: String? = "52",
        room: String? = "202"
    ) -> TimetableEvent {
        TimetableEvent(
            id: id, subjectCode: code, department: "AUIUI", subjectName: "Pokročilé mobilní technologie",
            typeName: "Cvičení", typeShort: "Cv", weekday: weekday, startTime: start, endTime: end,
            building: building, room: room, teacher: "Ing. Filip Vabroušek", weekParity: parity,
            dateFrom: from, dateTo: to, singleDate: single, hexColor: "#3E63DD"
        )
    }

    // MARK: - Den v týdnu

    @Test("weekday(of:) vrací 1 = pondělí … 7 = neděle")
    func weekdayOfDate() {
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 5, 9), calendar: calendar) == 1)
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 6, 0), calendar: calendar) == 2)
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 7, 23, 59), calendar: calendar) == 3)
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 10, 12), calendar: calendar) == 6)
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 11, 12), calendar: calendar) == 7)
    }

    @Test("weekday(of:) nezávisí na prvním dni týdne v kalendáři")
    func weekdayIndependentOfFirstWeekday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 5, 9), calendar: sundayFirst) == 1)
        #expect(TimetableEvent.weekday(of: makeDate(2026, 10, 11, 9), calendar: sundayFirst) == 7)
    }

    // MARK: - occurs(on:)

    @Test("Akce se koná jen ve svůj den v týdnu (v kteroukoli denní dobu)")
    func occursOnWeekday() {
        let tuesday = event(weekday: 2)
        #expect(tuesday.occurs(on: makeDate(2026, 10, 6, 0, 0), calendar: calendar))
        #expect(tuesday.occurs(on: makeDate(2026, 10, 6, 23, 30), calendar: calendar))
        #expect(tuesday.occurs(on: makeDate(2026, 10, 13, 8), calendar: calendar))
        #expect(!tuesday.occurs(on: makeDate(2026, 10, 5, 10), calendar: calendar))
        #expect(!tuesday.occurs(on: makeDate(2026, 10, 7, 10), calendar: calendar))
    }

    @Test("Platnost od–do je včetně krajních dnů")
    func occursWithinValidity() {
        let semester = event(
            weekday: 2,
            from: makeDate(2026, 9, 22),
            to: makeDate(2026, 12, 15)
        )
        #expect(!semester.occurs(on: makeDate(2026, 9, 15, 10), calendar: calendar))
        #expect(semester.occurs(on: makeDate(2026, 9, 22, 10), calendar: calendar))
        #expect(semester.occurs(on: makeDate(2026, 10, 6, 10), calendar: calendar))
        // dateTo je půlnoc, výuka odpoledne posledního dne se pořád počítá
        #expect(semester.occurs(on: makeDate(2026, 12, 15, 16), calendar: calendar))
        #expect(!semester.occurs(on: makeDate(2026, 12, 22, 10), calendar: calendar))
    }

    @Test("Jednorázová akce jen v konkrétní den, den v týdnu se ignoruje")
    func occursOnSingleDate() {
        let saturdayBlock = event(weekday: nil, single: makeDate(2026, 10, 10))
        #expect(saturdayBlock.occurs(on: makeDate(2026, 10, 10, 9), calendar: calendar))
        #expect(!saturdayBlock.occurs(on: makeDate(2026, 10, 17, 9), calendar: calendar))
        #expect(!saturdayBlock.occurs(on: makeDate(2026, 10, 11, 9), calendar: calendar))

        // Má-li akce zároveň den v týdnu, rozhoduje jednorázové datum
        let singleTuesday = event(weekday: 2, single: makeDate(2026, 10, 6))
        #expect(singleTuesday.occurs(on: makeDate(2026, 10, 6, 10), calendar: calendar))
        #expect(!singleTuesday.occurs(on: makeDate(2026, 10, 13, 10), calendar: calendar))
    }

    @Test("Akce bez dne i data se nekoná nikdy")
    func unscheduledNeverOccurs() {
        let unscheduled = event(weekday: nil, single: nil)
        for offset in 0..<7 {
            #expect(!unscheduled.occurs(on: makeDate(2026, 10, 5 + offset, 10), calendar: calendar))
        }
    }

    @Test("Sudý / lichý týden podle ISO čísla týdne")
    func occursByWeekParity() {
        let oddWeekTuesday = makeDate(2026, 10, 6, 10)   // ISO týden 41
        let evenWeekTuesday = makeDate(2026, 10, 13, 10) // ISO týden 42

        let even = event(weekday: 2, parity: "Sudý")
        #expect(!even.occurs(on: oddWeekTuesday, calendar: calendar))
        #expect(even.occurs(on: evenWeekTuesday, calendar: calendar))

        let odd = event(weekday: 2, parity: "Lichý")
        #expect(odd.occurs(on: oddWeekTuesday, calendar: calendar))
        #expect(!odd.occurs(on: evenWeekTuesday, calendar: calendar))

        for parity in ["Každý", "Jiný", nil] as [String?] {
            let other = event(weekday: 2, parity: parity)
            #expect(other.occurs(on: oddWeekTuesday, calendar: calendar))
            #expect(other.occurs(on: evenWeekTuesday, calendar: calendar))
        }
    }

    // MARK: - occurrence(on:)

    @Test("occurrence(on:) složí konkrétní začátek a konec")
    func occurrenceTimes() throws {
        let occurrence = try #require(event(start: "10:00", end: "11:30").occurrence(on: makeDate(2026, 10, 6, 7), calendar: calendar))
        #expect(occurrence.start == makeDate(2026, 10, 6, 10, 0))
        #expect(occurrence.end == makeDate(2026, 10, 6, 11, 30))
        #expect(occurrence.event.id == "1")
        #expect(occurrence.id == "1-\(occurrence.start.timeIntervalSince1970)")
    }

    @Test("occurrence(on:) je nil, když se akce nekoná nebo nemá platný čas")
    func occurrenceNil() {
        #expect(event().occurrence(on: makeDate(2026, 10, 7, 10), calendar: calendar) == nil)
        #expect(event(start: nil).occurrence(on: makeDate(2026, 10, 6), calendar: calendar) == nil)
        #expect(event(end: nil).occurrence(on: makeDate(2026, 10, 6), calendar: calendar) == nil)
        #expect(event(start: "deset").occurrence(on: makeDate(2026, 10, 6), calendar: calendar) == nil)
    }

    @Test("Časy v minutách od půlnoci")
    func startEndMinutes() {
        #expect(event(start: "08:30", end: "10:05").startMinutes == 510)
        #expect(event(start: "08:30", end: "10:05").endMinutes == 605)
        #expect(event(start: "7:00").startMinutes == 420)
        #expect(event(start: "").startMinutes == nil)
    }

    @Test("Výskyt v den změny času má správný čas na hodinách")
    func occurrenceOnDSTDay() throws {
        // Neděle 25. 10. 2026 – konec letního času, den má 25 hodin.
        let autumn = try #require(
            event(weekday: nil, start: "10:00", end: "11:30", single: makeDate(2026, 10, 25))
                .occurrence(on: makeDate(2026, 10, 25), calendar: calendar)
        )
        // Neděle 29. 3. 2026 – začátek letního času, den má 23 hodin.
        let spring = try #require(
            event(weekday: nil, start: "10:00", end: "11:30", single: makeDate(2026, 3, 29))
                .occurrence(on: makeDate(2026, 3, 29), calendar: calendar)
        )
        #expect(calendar.component(.hour, from: autumn.start) == 10)
        #expect(calendar.component(.hour, from: spring.start) == 10)
    }

    // MARK: - Místo a parita

    @Test("locationText skládá budovu a místnost")
    func locationText() {
        #expect(event(building: "52", room: "202").locationText == "52/202")
        #expect(event(building: nil, room: "202").locationText == "202")
        #expect(event(building: "52", room: nil).locationText == "52")
        #expect(event(building: "", room: "202").locationText == "202")
        #expect(event(building: "52", room: "").locationText == "52")
        #expect(event(building: "", room: "").locationText == nil)
        #expect(event(building: nil, room: nil).locationText == nil)
    }

    @Test("parityText jen pro sudý a lichý týden")
    func parityText() {
        #expect(event(parity: "Sudý").parityText == "Sudý týden")
        #expect(event(parity: "Lichý").parityText == "Lichý týden")
        #expect(event(parity: "Každý").parityText == nil)
        #expect(event(parity: nil).parityText == nil)
    }

    // MARK: - TimetableSnapshot

    private var snapshot: TimetableSnapshot {
        TimetableSnapshot(
            events: [
                event(id: "lecture", weekday: 2, start: "12:00", end: "13:00"),
                event(id: "lab", weekday: 2, start: "10:00", end: "12:00"),
                event(id: "wednesday", weekday: 3, start: "09:00", end: "11:00"),
                event(id: "monday", weekday: 1, start: "08:00", end: "10:00"),
                event(id: "noTime", weekday: 2, start: nil, end: nil),
                event(id: "unscheduled", weekday: nil, start: nil, end: nil)
            ],
            semester: "ZS",
            academicYear: "2026",
            fetchedAt: makeDate(2026, 10, 1)
        )
    }

    @Test("occurrences(on:) vrací jen akce toho dne seřazené podle začátku")
    func occurrencesOnDay() {
        let tuesday = snapshot.occurrences(on: makeDate(2026, 10, 6, 15), calendar: calendar)
        #expect(tuesday.map(\.event.id) == ["lab", "lecture"])

        let thursday = snapshot.occurrences(on: makeDate(2026, 10, 8), calendar: calendar)
        #expect(thursday.isEmpty)
    }

    @Test("upcoming zahrne probíhající hodinu a vynechá skončené")
    func upcomingIncludesOngoing() {
        let during = snapshot.upcoming(after: makeDate(2026, 10, 6, 11), limit: 3, calendar: calendar)
        #expect(during.map(\.event.id) == ["lab", "lecture", "wednesday"])

        let afterLab = snapshot.upcoming(after: makeDate(2026, 10, 6, 12, 30), limit: 2, calendar: calendar)
        #expect(afterLab.map(\.event.id) == ["lecture", "wednesday"])

        // Přesně v okamžiku konce hodina už neprobíhá
        let atEnd = snapshot.upcoming(after: makeDate(2026, 10, 6, 13), limit: 1, calendar: calendar)
        #expect(atEnd.map(\.event.id) == ["wednesday"])
    }

    @Test("upcoming dodrží limit a pokračuje do dalšího týdne")
    func upcomingLimitAndNextWeek() {
        let one = snapshot.upcoming(after: makeDate(2026, 10, 6, 8), limit: 1, calendar: calendar)
        #expect(one.map(\.event.id) == ["lab"])

        let friday = snapshot.upcoming(after: makeDate(2026, 10, 9, 18), limit: 4, calendar: calendar)
        #expect(friday.map(\.event.id) == ["monday", "lab", "lecture", "wednesday"])
        #expect(friday.first?.start == makeDate(2026, 10, 12, 8))
    }

    @Test("upcoming respektuje daysAhead a prázdný rozvrh")
    func upcomingDaysAhead() {
        let mondayOnly = TimetableSnapshot(
            events: [event(id: "monday", weekday: 1, start: "08:00", end: "10:00")],
            semester: "ZS", academicYear: "2026", fetchedAt: makeDate(2026, 10, 1)
        )
        // Ze středy 7. 10. je nejbližší pondělí za 5 dní
        #expect(mondayOnly.upcoming(after: makeDate(2026, 10, 7, 12), daysAhead: 4, calendar: calendar).isEmpty)
        #expect(mondayOnly.upcoming(after: makeDate(2026, 10, 7, 12), daysAhead: 5, calendar: calendar).count == 1)

        let empty = TimetableSnapshot(events: [], semester: "ZS", academicYear: "2026", fetchedAt: .now)
        #expect(empty.upcoming(after: makeDate(2026, 10, 7), calendar: calendar).isEmpty)
    }

    @Test("unscheduledEvents = akce bez dne v týdnu i bez data")
    func unscheduledEvents() {
        #expect(snapshot.unscheduledEvents.map(\.id) == ["unscheduled"])

        let withSingle = TimetableSnapshot(
            events: [event(id: "block", weekday: nil, single: makeDate(2026, 10, 10))],
            semester: "ZS", academicYear: "2026", fetchedAt: .now
        )
        #expect(withSingle.unscheduledEvents.isEmpty)
    }

    @Test("Snapshot přežije JSON (ukládá se do App Group jako JSON)")
    func snapshotCodableRoundTrip() throws {
        let original = TimetableSnapshot(
            events: [event(id: "a", from: makeDate(2026, 9, 22), to: makeDate(2026, 12, 15)),
                     event(id: "b", weekday: nil, single: makeDate(2026, 10, 10))],
            semester: "ZS", academicYear: "2026", fetchedAt: makeDate(2026, 10, 1, 8)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimetableSnapshot.self, from: data)
        #expect(decoded.events == original.events)
        #expect(decoded.semester == "ZS")
        #expect(decoded.academicYear == "2026")
        #expect(decoded.fetchedAt == original.fetchedAt)
    }

    @Test("Ukázkový rozvrh má každou akci s dnem i časem")
    func sampleSnapshot() {
        let sample = TimetableSnapshot.sample
        #expect(!sample.events.isEmpty)
        #expect(sample.unscheduledEvents.isEmpty)
        #expect(Set(sample.events.map(\.id)).count == sample.events.count)
        #expect(sample.events.allSatisfy { $0.startMinutes != nil && ($0.endMinutes ?? 0) > ($0.startMinutes ?? 0) })
    }
}
