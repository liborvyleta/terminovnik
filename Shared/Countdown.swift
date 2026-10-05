import SwiftUI

// Sdíleno mezi aplikací a widgetem – pracuje jen s datem, ne se SwiftData modelem.

/// Míra naléhavosti deadlinu – určuje barvu a ikonu odpočtu.
enum DeadlineUrgency {
    case done       // splněno
    case overdue    // po termínu
    case today      // dnes
    case soon       // do 3 dnů
    case upcoming   // později

    init(dueDate: Date, isCompleted: Bool = false, now: Date = .now) {
        if isCompleted {
            self = .done
        } else if dueDate < now {
            self = .overdue
        } else {
            switch dueDate.calendarDays(from: now) {
            case 0: self = .today
            case 1...3: self = .soon
            default: self = .upcoming
            }
        }
    }

    var color: Color {
        switch self {
        case .done: .green
        case .overdue: .red
        case .today: .red
        case .soon: .orange
        case .upcoming: .blue
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark"
        case .overdue: "exclamationmark.triangle.fill"
        case .today: "alarm.fill"
        case .soon: "hourglass"
        case .upcoming: "calendar"
        }
    }
}

/// Lidsky čitelný odpočet do termínu: „Dnes“, „Zítra“, „Za 5 dní“, „Před 2 dny“…
enum Countdown {
    static func text(for date: Date, isCompleted: Bool = false, now: Date = .now) -> String {
        if isCompleted { return "Splněno" }
        let days = date.calendarDays(from: now)
        switch days {
        case ..<(-1):
            return "Před \(-days) dny"
        case -1:
            return "Včera"
        case 0:
            return date < now ? "Dnes – prošlo" : "Dnes"
        case 1:
            return "Zítra"
        default:
            return "Za \(days) \(CzechPlural.days(days))"
        }
    }
}
