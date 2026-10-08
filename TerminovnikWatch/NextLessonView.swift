import SwiftUI

/// Karta „Další hodina“: probíhající nebo nejbližší hodina s odpočtem.
struct NextLessonView: View {
    let store: WatchStore

    var body: some View {
        // Každou minutu přepočítáme, která hodina je „další“ (odpočet samotný běží plynule)
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.timetable == nil {
            ContentUnavailableView {
                Label("Rozvrh není", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Přihlas se do STAGu v Termínovníku na iPhonu.")
            }
        } else if let lesson = store.nextLesson(now: now) {
            LessonCard(lesson: lesson, now: now)
                .containerBackground(lesson.color.gradient, for: .tabView)
        } else {
            ContentUnavailableView {
                Label("Žádná výuka", systemImage: "cup.and.saucer")
            } description: {
                Text("V nejbližších dvou týdnech nemáš žádnou hodinu.")
            }
        }
    }
}

/// Obsah karty jedné hodiny
private struct LessonCard: View {
    let lesson: TimetableOccurrence
    let now: Date

    private var isOngoing: Bool { lesson.start <= now && now < lesson.end }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(isOngoing ? "Právě probíhá" : "Další hodina")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(lesson.event.subjectName)
                    .font(.headline)
                    .lineLimit(3)

                Text(verbatim: "\(lesson.event.typeName) · \(lesson.event.subjectCode)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label {
                    Text(verbatim: "\(lesson.dayText(now: now)) \(lesson.timeRangeText)")
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.footnote)

                if let location = lesson.event.locationText {
                    Label {
                        Text(verbatim: location)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.footnote)
                }

                countdown
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Odpočet do začátku (nebo do konce probíhající hodiny)
    @ViewBuilder
    private var countdown: some View {
        if isOngoing {
            Text("Končí za \(Text(timerInterval: now...lesson.end, countsDown: true))")
        } else if lesson.start.timeIntervalSince(now) < 3600 {
            // Poslední hodina před začátkem – odpočet po sekundách
            Text("Začíná za \(Text(timerInterval: now...lesson.start, countsDown: true))")
        } else {
            Text("Začíná za \(Text(lesson.start, style: .relative))")
        }
    }
}

// MARK: - Pomocné texty

extension TimetableOccurrence {
    /// Barva předmětu z aplikace (šedá, pokud předmět v aplikaci není)
    var color: Color { Color(hex: event.hexColor ?? "#687076") }

    /// „10:00–12:00“
    var timeRangeText: String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(.app)
        return "\(start.formatted(style))–\(end.formatted(style))"
    }

    /// „Dnes“ / „Zítra“ / „Čtvrtek“
    func dayText(now: Date, calendar: Calendar = .current) -> String {
        switch start.calendarDays(from: now, calendar: calendar) {
        case 0: String(localized: "Dnes", comment: "Odpočet: termín je dnes")
        case 1: String(localized: "Zítra", comment: "Odpočet: termín je zítra")
        default: start.formatted(.dateTime.weekday(.wide).locale(.app)).localizedCapitalized
        }
    }
}

#Preview("Další hodina") {
    TabView {
        NextLessonView(store: WatchStore(timetable: .sample, deadlines: WidgetDeadline.watchSamples))
    }
    .tabViewStyle(.verticalPage)
}

#Preview("Bez rozvrhu") {
    NextLessonView(store: WatchStore(timetable: nil, deadlines: WidgetDeadline.watchSamples))
}
