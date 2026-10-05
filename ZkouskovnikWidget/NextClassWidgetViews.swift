import SwiftUI
import WidgetKit

// Pohledy jednotlivých rodin widgetu „Další hodina“. Žádný z nich nečte `widgetFamily` –
// výběr dělá jen `NextClassWidgetView`, takže je lze vykreslit i samostatně (snímky mimo WidgetKit).

/// Kořenový pohled widgetu – podle rodiny vybere konkrétní rozvržení.
struct NextClassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextClassEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall: NextClassSmallView(entry: entry)
        case .systemMedium: NextClassMediumView(entry: entry)
        case .accessoryRectangular: NextClassRectangularView(entry: entry)
        case .accessoryInline: NextClassInlineView(entry: entry)
        case .accessoryCircular: NextClassCircularView(entry: entry)
        default: NextClassSmallView(entry: entry)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
            Color.clear
        default:
            // Systémové pozadí – funguje ve světlém i tmavém režimu.
            Rectangle().fill(.background)
        }
    }
}

// MARK: - Plocha: malý

/// Malý widget: nejbližší hodina – štítek, typ, název, velký čas, místnost a živý stav.
struct NextClassSmallView: View {
    let entry: NextClassEntry

    var body: some View {
        Group {
            if let occurrence = entry.soon.first {
                content(for: occurrence)
            } else {
                NextClassEmptyState(entry: entry, compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.locale, .czech)
    }

    private func content(for occurrence: TimetableOccurrence) -> some View {
        let event = occurrence.event

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 4) {
                WidgetSubjectBadge(code: event.subjectCode, hexColor: NextClassFormat.hex(for: occurrence))
                Spacer(minLength: 4)
                Text(event.typeName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(event.subjectName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .padding(.top, 4)

            Spacer(minLength: 0)

            Text(NextClassFormat.timeRange(occurrence))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let location = event.locationText {
                HStack(spacing: 3) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(location)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            NextClassStatusLine(occurrence: occurrence, entry: entry, showsProgress: true)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Plocha: střední

/// Střední widget: hlavička s dnem a živým stavem + další 3 hodiny (dnes, případně zítra).
struct NextClassMediumView: View {
    let entry: NextClassEntry

    var body: some View {
        let items = Array(entry.soon.prefix(3))
        // Štítek „Zítra“ u řádků má smysl, jen když seznam začíná dneškem.
        let startsToday = items.first.map(entry.isToday) ?? true

        VStack(alignment: .leading, spacing: 7) {
            NextClassHeader(entry: entry)

            if items.isEmpty {
                NextClassEmptyState(entry: entry, compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { occurrence in
                        NextClassRow(
                            occurrence: occurrence,
                            isOngoing: entry.isOngoing(occurrence),
                            showsTomorrow: startsToday && !entry.isToday(occurrence)
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, .czech)
    }
}

/// Hlavička: „Dnes · po 5. 10.“ vlevo, živý stav nejbližší hodiny vpravo.
struct NextClassHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: NextClassEntry

    var body: some View {
        let brand = WidgetBrand.color(for: colorScheme)
        let first = entry.soon.first
        let showsTomorrow = first.map { !entry.isToday($0) } ?? false
        let day = showsTomorrow
            ? Calendar.current.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
            : entry.date

        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.day.timeline.left")
                    .foregroundStyle(brand)
                Text(showsTomorrow ? "Zítra" : "Dnes")
                Text(NextClassFormat.dayText(day))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .layoutPriority(1)

            // Text s relativním časem si ve widgetu zabírá maximální šířku – zarovnáme ho doprava.
            Group {
                if let first {
                    if entry.isOngoing(first) {
                        Text("Probíhá · do \(NextClassFormat.time(first.end))")
                    } else if entry.isToday(first) {
                        Text("za \(first.start, style: .relative)")
                    } else {
                        Text("Dnes už volno")
                    }
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(brand)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.footnote.weight(.bold))
    }
}

/// Řádek: čas od–do, proužek v barvě předmětu, název, „kód · typ“ a místnost vpravo.
struct NextClassRow: View {
    let occurrence: TimetableOccurrence
    let isOngoing: Bool
    let showsTomorrow: Bool

    var body: some View {
        let event = occurrence.event
        let color = NextClassFormat.color(for: occurrence)

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(NextClassFormat.time(occurrence.start))
                    .font(.footnote.weight(.bold))
                Text(NextClassFormat.time(occurrence.end))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.subjectName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("\(event.subjectCode) · \(event.typeName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: 4)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let location = event.locationText {
                    HStack(spacing: 2) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                        Text(location)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                }
                if isOngoing {
                    Text("TEĎ")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(color))
                } else if showsTomorrow {
                    Text("Zítra")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
        }
    }
}

// MARK: - Zamčená obrazovka

/// Obdélníkový widget: „10:00 · AP9PT · 52/202“ tučně, název předmětu a stav.
struct NextClassRectangularView: View {
    let entry: NextClassEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let occurrence = entry.soon.first {
                Text("\(NextClassFormat.time(occurrence.start)) · \(NextClassFormat.codeAndRoom(occurrence))")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text(occurrence.event.subjectName)
                    .font(.subheadline)
                    .lineLimit(1)
                Group {
                    if entry.isOngoing(occurrence) {
                        Text("Probíhá · do \(NextClassFormat.time(occurrence.end))")
                    } else if entry.isToday(occurrence) {
                        Text("\(occurrence.event.typeName) · za \(occurrence.start, style: .relative)")
                    } else {
                        Text("Zítra · \(occurrence.event.typeName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if entry.hasTimetable {
                Text("Volno 🎉")
                    .font(.headline)
                    .widgetAccentable()
                Text("Dnes ani zítra žádná výuka")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let next = entry.next {
                    Text("Příště \(next.start.deadlineFormatted) · \(next.event.subjectCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text("Rozvrh nenačten")
                }
                .font(.headline)
                .widgetAccentable()
                Text("Otevři aplikaci a přihlas se do STAGu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.locale, .czech)
    }
}

/// Řádkový widget, např. „10:00 AP9PT · 52/202“.
struct NextClassInlineView: View {
    let entry: NextClassEntry

    var body: some View {
        if let occurrence = entry.soon.first {
            Label(title(for: occurrence), systemImage: entry.isOngoing(occurrence) ? "play.circle.fill" : "clock")
        } else if entry.hasTimetable {
            Text("Volno 🎉")
        } else {
            Label("Přihlas se do STAGu", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func title(for occurrence: TimetableOccurrence) -> String {
        let place = NextClassFormat.codeAndRoom(occurrence)
        if entry.isOngoing(occurrence) { return "Teď \(place)" }
        let time = NextClassFormat.time(occurrence.start)
        return entry.isToday(occurrence) ? "\(time) \(place)" : "Zítra \(time) \(place)"
    }
}

/// Kruhový widget: kód předmětu, čas začátku (nebo „teď“) a místnost.
struct NextClassCircularView: View {
    let entry: NextClassEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content
                .widgetAccentable()
                .padding(4)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let occurrence = entry.soon.first {
            let ongoing = entry.isOngoing(occurrence)
            let footer = ongoing
                ? "do \(NextClassFormat.time(occurrence.end))"
                : (entry.isToday(occurrence) ? occurrence.event.locationText ?? occurrence.event.typeShort : "zítra")

            VStack(spacing: 0) {
                Text(occurrence.event.subjectCode)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 44)
                Text(ongoing ? "teď" : NextClassFormat.time(occurrence.start))
                    .font(.system(size: ongoing ? 19 : 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(footer)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 46)
            }
        } else if entry.hasTimetable {
            VStack(spacing: 1) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Volno")
                    .font(.system(size: 10, weight: .semibold))
            }
        } else {
            VStack(spacing: 1) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                Text("STAG")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
    }
}

// MARK: - Sdílené prvky

/// Živý stav hodiny: „za 25 min“ (odpočet se hýbe sám), „Probíhá“ s průběhem, nebo „Zítra“.
struct NextClassStatusLine: View {
    let occurrence: TimetableOccurrence
    let entry: NextClassEntry
    var showsProgress = false

    var body: some View {
        let color = NextClassFormat.color(for: occurrence)

        Group {
            if entry.isOngoing(occurrence) {
                HStack(spacing: 6) {
                    Text("Probíhá")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .fixedSize()
                    if showsProgress {
                        ProgressView(timerInterval: occurrence.start...occurrence.end, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(color)
                    }
                }
            } else if entry.isToday(occurrence) {
                HStack(spacing: 3) {
                    Image(systemName: "clock.fill")
                    Text("za \(occurrence.start, style: .relative)")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "sunrise.fill")
                    Text("Zítra")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Prázdný stav: rozvrh nenačtený, nebo dnes a zítra volno (s nápovědou „Příště…“).
struct NextClassEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: NextClassEntry
    let compact: Bool

    var body: some View {
        if entry.hasTimetable {
            free
        } else {
            missing
        }
    }

    private var free: some View {
        VStack(spacing: compact ? 3 : 6) {
            Image(systemName: "sun.max.fill")
                .font(compact ? .title2 : .largeTitle)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
            Text("Volno 🎉")
                .font(compact ? .headline : .title3.weight(.bold))
            Text("Dnes ani zítra žádná výuka")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let next = entry.next {
                Text("Příště \(next.start.deadlineFormatted) · \(next.event.subjectCode)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NextClassFormat.color(for: next))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
            }
        }
        .environment(\.locale, .czech)
    }

    private var missing: some View {
        VStack(spacing: compact ? 4 : 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(compact ? .title : .system(size: 44))
                .foregroundStyle(WidgetBrand.color(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text("Rozvrh nenačten")
                .font(compact ? .subheadline.weight(.bold) : .title3.weight(.bold))
            Text("Otevři aplikaci a přihlas se do STAGu")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }
}

/// Formátování pro widget „Další hodina“ (česky, bez úvodní nuly: „8:00“).
enum NextClassFormat {
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(.czech))
    }

    /// „10:00–12:00“
    static func timeRange(_ occurrence: TimetableOccurrence) -> String {
        "\(time(occurrence.start))–\(time(occurrence.end))"
    }

    /// „po 5. 10.“
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.defaultDigits).locale(.czech))
    }

    /// „AP9PT · 52/202“ (bez místnosti jen kód)
    static func codeAndRoom(_ occurrence: TimetableOccurrence) -> String {
        [occurrence.event.subjectCode, occurrence.event.locationText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Barva předmětu z aplikace; když chybí, stabilní barva z palety podle kódu.
    static func hex(for occurrence: TimetableOccurrence) -> String {
        if let hex = occurrence.event.hexColor, !hex.isEmpty { return hex }
        let seed = occurrence.event.subjectCode.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return SubjectPalette.hex(seed)
    }

    static func color(for occurrence: TimetableOccurrence) -> Color {
        Color(hex: hex(for: occurrence))
    }
}
