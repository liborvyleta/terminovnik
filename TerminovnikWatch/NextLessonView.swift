import SwiftUI

/// Stránka „Další hodina“ s probíhající nebo nejbližší hodinou a odpočtem.
///
/// Hodinu vybírá z rozvrhu, který ``WatchStore`` dekódoval z kontextu přijatého z iPhonu
/// přes WatchConnectivity; výběr se přepočítává každou minutu.
struct NextLessonView: View {
    /// Zdroj dat přijatých z iPhonu.
    let store: WatchStore

    /// Obsah stránky obnovovaný každou minutu.
    var body: some View {
        // Každou minutu přepočítáme, která hodina je „další“ (odpočet samotný běží plynule)
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    /// Sestaví obsah stránky pro daný okamžik.
    ///
    /// - Parameter now: Aktuální čas, ke kterému se hledá další hodina.
    /// - Returns: Kartu hodiny, nebo prázdný stav, když rozvrh chybí nebo žádná hodina nenásleduje.
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

/// Karta jedné hodiny.
///
/// Zobrazuje název předmětu, typ, den a čas, místnost a odpočet do začátku nebo do konce hodiny.
private struct LessonCard: View {
    /// Zobrazovaný výskyt hodiny.
    let lesson: TimetableOccurrence
    /// Aktuální čas, ke kterému se počítá odpočet.
    let now: Date

    /// Udává, zda hodina právě probíhá.
    private var isOngoing: Bool { lesson.start <= now && now < lesson.end }

    /// Obsah karty.
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

    /// Odpočet do začátku hodiny, nebo do konce probíhající hodiny.
    ///
    /// Během poslední hodiny před začátkem a během výuky běží po sekundách, jinak je relativní.
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
    /// Barva předmětu z aplikace, nebo šedá, pokud předmět barvu nemá.
    var color: Color { Color(hex: event.hexColor ?? "#687076") }

    /// Časový rozsah hodiny ve formátu „10:00–12:00“.
    var timeRangeText: String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(.app)
        return "\(start.formatted(style))–\(end.formatted(style))"
    }

    /// Vrátí označení dne, kdy hodina začíná: „Dnes“, „Zítra“, nebo název dne v týdnu („Čtvrtek“).
    ///
    /// - Parameters:
    ///   - now: Aktuální čas, vůči kterému se počítá rozdíl dnů.
    ///   - calendar: Kalendář pro výpočet; výchozí hodnota je aktuální kalendář.
    /// - Returns: Lokalizované označení dne.
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
    .tabViewStyle(.page)
}

#Preview("Bez rozvrhu") {
    NextLessonView(store: WatchStore(timetable: nil, deadlines: WidgetDeadline.watchSamples))
}
