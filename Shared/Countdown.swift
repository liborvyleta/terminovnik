import SwiftUI

// Sdíleno mezi aplikací, widgetem a hodinkami – pracuje jen s datem, ne se SwiftData modelem.

/// Míra naléhavosti deadlinu – určuje barvu a ikonu odpočtu.
///
/// Používá ji aplikace, widget i náhledy akcí Siri; varianta pro `ExamTask` je v `Countdown+ExamTask.swift`.
enum DeadlineUrgency {
    /// Povinnost je splněná.
    case done
    /// Termín uplynul a povinnost není splněná.
    case overdue
    /// Termín je dnes a ještě neuplynul.
    case today
    /// Termín za 1–3 kalendářní dny.
    case soon
    /// Termín za více než 3 dny.
    case upcoming

    /// Určí naléhavost podle termínu a stavu splnění.
    /// - Parameters:
    ///   - dueDate: Datum a čas termínu.
    ///   - isCompleted: Zda je povinnost splněná.
    ///   - now: Referenční okamžik, výchozí je aktuální čas.
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

    /// Barva odpočtu (zelená, červená, oranžová, modrá).
    var color: Color {
        switch self {
        case .done: .green
        case .overdue: .red
        case .today: .red
        case .soon: .orange
        case .upcoming: .blue
        }
    }

    /// Název SF Symbolu odpočtu.
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
///
/// Texty jsou v String Catalogu; tvary podle počtu („Za 2 dny“ / „Za 5 dní“) řeší plurálové varianty.
enum Countdown {
    /// Vrátí text odpočtu podle počtu kalendářních dní do termínu.
    /// - Parameters:
    ///   - date: Datum a čas termínu.
    ///   - isCompleted: Zda je povinnost splněná (pak vrací „Splněno“).
    ///   - now: Referenční okamžik, výchozí je aktuální čas.
    /// - Returns: Lokalizovaný text odpočtu.
    static func text(for date: Date, isCompleted: Bool = false, now: Date = .now) -> String {
        if isCompleted { return String(localized: "Splněno", comment: "Odpočet: povinnost je splněná") }
        let days = date.calendarDays(from: now)
        switch days {
        case ..<(-1):
            let daysAgo = -days
            return String(localized: "Před \(daysAgo) dny", comment: "Odpočet: termín byl před X dny (plurál)")
        case -1:
            return String(localized: "Včera", comment: "Odpočet: termín byl včera")
        case 0:
            return date < now
                ? String(localized: "Dnes – prošlo", comment: "Odpočet: termín byl dnes a už uplynul")
                : String(localized: "Dnes", comment: "Odpočet: termín je dnes")
        case 1:
            return String(localized: "Zítra", comment: "Odpočet: termín je zítra")
        default:
            return String(localized: "Za \(days) dní", comment: "Odpočet: termín je za X dní (plurál)")
        }
    }
}
