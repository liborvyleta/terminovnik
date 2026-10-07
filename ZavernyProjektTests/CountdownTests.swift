import Foundation
import Testing
@testable import ZavernyProjekt

/// Odpočet do termínu (`Countdown`), naléhavost (`DeadlineUrgency`) a počítání kalendářních dní.
/// Countdown i DeadlineUrgency interně používají `Calendar.current`, proto data stavíme v kalendáři zařízení.
@Suite("Odpočet a naléhavost termínů")
struct CountdownTests {
    let calendar = TestCalendar.device
    /// Středa 7. 10. 2026 12:00
    var now: Date { makeDate(2026, 10, 7, 12, 0, calendar: calendar) }

    private func day(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 10) -> Date {
        makeDate(2026, month, day, hour, minute, calendar: calendar)
    }

    // MARK: - Countdown.text

    @Test("Dnes – termín později během dne i přesně teď")
    func todayLater() {
        #expect(Countdown.text(for: day(7, 18), now: now) == "Dnes")
        #expect(Countdown.text(for: day(7, 23, 59), now: now) == "Dnes")
        #expect(Countdown.text(for: now, now: now) == "Dnes")
    }

    @Test("Dnes – prošlo: termín dnes, ale už uplynul")
    func todayPassed() {
        #expect(Countdown.text(for: day(7, 8), now: now) == "Dnes – prošlo")
        #expect(Countdown.text(for: now.addingTimeInterval(-1), now: now) == "Dnes – prošlo")
    }

    @Test("Zítra a Včera se počítají podle kalendářních dní, ne po 24 hodinách")
    func tomorrowAndYesterday() {
        #expect(Countdown.text(for: day(8, 0, 5), now: now) == "Zítra")
        #expect(Countdown.text(for: day(8, 23, 59), now: now) == "Zítra")
        #expect(Countdown.text(for: day(6, 23, 59), now: now) == "Včera")
        #expect(Countdown.text(for: day(6, 0, 1), now: now) == "Včera")

        // Těsně před půlnocí: termín za 2 minuty po půlnoci je už „Zítra“
        let lateEvening = day(7, 23, 59)
        #expect(Countdown.text(for: day(8, 0, 1), now: lateEvening) == "Zítra")
    }

    @Test("Za X dní a Před X dny")
    func daysAheadAndAgo() {
        #expect(Countdown.text(for: day(12), now: now) == "Za 5 dní")
        #expect(Countdown.text(for: day(17, 8), now: now) == "Za 10 dní")
        #expect(Countdown.text(for: day(2), now: now) == "Před 5 dny")
        #expect(Countdown.text(for: day(5, 8), now: now) == "Před 2 dny")
        #expect(Countdown.text(for: day(30, 9, month: 9), now: now) == "Před 7 dny")
    }

    @Test("Za 2–4 dny – plurálová varianta ze String Catalogu")
    func pluralFewDays() {
        // Zdrojový řetězec je „Za %lld dní“; tvar „dny“ pro 2–4 musí dodat plurálová varianta katalogu.
        #expect(Countdown.text(for: day(9), now: now) == "Za 2 dny")
        #expect(Countdown.text(for: day(11), now: now) == "Za 4 dny")
    }

    @Test("Splněný úkol má vždy text Splněno")
    func completed() {
        #expect(Countdown.text(for: day(1), isCompleted: true, now: now) == "Splněno")
        #expect(Countdown.text(for: day(7, 8), isCompleted: true, now: now) == "Splněno")
        #expect(Countdown.text(for: day(20), isCompleted: true, now: now) == "Splněno")
    }

    // MARK: - DeadlineUrgency

    @Test("Splněno má přednost i před termínem po splatnosti")
    func urgencyDone() {
        #expect(DeadlineUrgency(dueDate: day(1), isCompleted: true, now: now) == .done)
        #expect(DeadlineUrgency(dueDate: day(20), isCompleted: true, now: now) == .done)
    }

    @Test("Po termínu – i o sekundu, i v rámci dneška")
    func urgencyOverdue() {
        #expect(DeadlineUrgency(dueDate: now.addingTimeInterval(-1), now: now) == .overdue)
        #expect(DeadlineUrgency(dueDate: day(7, 8), now: now) == .overdue)
        #expect(DeadlineUrgency(dueDate: day(1), now: now) == .overdue)
    }

    @Test("Hranice dnes / brzy (1–3 dny) / později")
    func urgencyBoundaries() {
        #expect(DeadlineUrgency(dueDate: now, now: now) == .today)
        #expect(DeadlineUrgency(dueDate: day(7, 23, 59), now: now) == .today)
        #expect(DeadlineUrgency(dueDate: day(8, 0, 0), now: now) == .soon)
        #expect(DeadlineUrgency(dueDate: day(10, 23, 59), now: now) == .soon)
        #expect(DeadlineUrgency(dueDate: day(11, 0, 0), now: now) == .upcoming)
        #expect(DeadlineUrgency(dueDate: day(30), now: now) == .upcoming)
    }

    @Test("Každá naléhavost má vlastní symbol")
    func urgencySymbols() {
        let all: [DeadlineUrgency] = [.done, .overdue, .today, .soon, .upcoming]
        #expect(Set(all.map(\.symbol)).count == all.count)
        #expect(DeadlineUrgency.overdue.symbol == "exclamationmark.triangle.fill")
        #expect(DeadlineUrgency.done.symbol == "checkmark")
    }

    // MARK: - Date.calendarDays

    @Test("calendarDays počítá od půlnoci")
    func calendarDaysMidnight() {
        let prague = TestCalendar.prague
        let morning = makeDate(2026, 10, 7, 0, 0)
        let evening = makeDate(2026, 10, 7, 23, 59)
        let nextNight = makeDate(2026, 10, 8, 0, 1)

        #expect(evening.calendarDays(from: morning, calendar: prague) == 0)
        #expect(nextNight.calendarDays(from: evening, calendar: prague) == 1)
        #expect(evening.calendarDays(from: nextNight, calendar: prague) == -1)
        #expect(makeDate(2026, 10, 17, 1).calendarDays(from: evening, calendar: prague) == 10)
    }

    @Test("calendarDays přes změnu času a přelom roku")
    func calendarDaysDSTAndYear() {
        let prague = TestCalendar.prague
        // Konec letního času 25. 10. 2026 (den má 25 hodin)
        #expect(makeDate(2026, 10, 26, 12).calendarDays(from: makeDate(2026, 10, 24, 12), calendar: prague) == 2)
        #expect(makeDate(2026, 10, 26, 0).calendarDays(from: makeDate(2026, 10, 25, 23, 30), calendar: prague) == 1)
        // Začátek letního času 29. 3. 2026 (den má 23 hodin)
        #expect(makeDate(2026, 3, 30, 0, 30).calendarDays(from: makeDate(2026, 3, 28, 23), calendar: prague) == 2)
        // Přelom roku
        #expect(makeDate(2027, 1, 1, 0, 10).calendarDays(from: makeDate(2026, 12, 31, 23, 50), calendar: prague) == 1)
    }

    // MARK: - CzechPlural

    @Test("České tvary podle počtu")
    func czechPlural() {
        #expect(CzechPlural.credits(1) == "kredit")
        #expect(CzechPlural.credits(2) == "kredity")
        #expect(CzechPlural.credits(4) == "kredity")
        #expect(CzechPlural.credits(5) == "kreditů")
        #expect(CzechPlural.credits(0) == "kreditů")
        #expect(CzechPlural.tasks(3) == "úkoly")
        #expect(CzechPlural.days(-2) == "dny")
        #expect(CzechPlural.days(11) == "dní")
    }
}
