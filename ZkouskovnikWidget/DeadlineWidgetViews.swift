import SwiftUI
import WidgetKit

// Pohledy jednotlivých rodin widgetu. Žádný z nich nečte `widgetFamily` –
// výběr dělá jen `DeadlineWidgetView`, takže je lze vykreslit i samostatně.

/// Kořenový pohled widgetu – podle rodiny vybere konkrétní rozvržení.
struct DeadlineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeadlineEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall: SmallDeadlineView(entry: entry)
        case .systemMedium: MediumDeadlineView(entry: entry)
        case .systemLarge, .systemExtraLarge: LargeDeadlineView(entry: entry)
        case .accessoryRectangular: RectangularDeadlineView(entry: entry)
        case .accessoryCircular: CircularDeadlineView(entry: entry)
        case .accessoryInline: InlineDeadlineView(entry: entry)
        default: SmallDeadlineView(entry: entry)
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

/// Malý widget: nejbližší deadline s velkým barevným odpočtem.
struct SmallDeadlineView: View {
    let entry: DeadlineEntry

    var body: some View {
        if let deadline = entry.nearest {
            let urgency = DeadlineUrgency(dueDate: deadline.dueDate, now: entry.date)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 4) {
                    WidgetSubjectBadge(code: deadline.subjectCode, hexColor: deadline.hexColor)
                    Spacer(minLength: 4)
                    Image(systemName: urgency.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(urgency.color)
                }

                HStack(spacing: 3) {
                    Image(systemName: deadline.typeSymbol)
                    Text(deadline.typeTitle)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)

                Text(deadline.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(Countdown.text(for: deadline.dueDate, now: entry.date))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(urgency.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(deadline.dueDate.deadlineFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyState(compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Plocha: střední a velký

/// Střední widget: hlavička a 3 nejbližší deadliny.
struct MediumDeadlineView: View {
    let entry: DeadlineEntry

    var body: some View {
        WidgetDeadlineList(entry: entry, maxRows: 3, isLarge: false)
    }
}

/// Velký widget: hlavička a 6 nejbližších deadlinů.
struct LargeDeadlineView: View {
    let entry: DeadlineEntry

    var body: some View {
        WidgetDeadlineList(entry: entry, maxRows: 6, isLarge: true)
    }
}

/// Společné rozvržení seznamu pro střední a velký widget.
struct WidgetDeadlineList: View {
    let entry: DeadlineEntry
    let maxRows: Int
    let isLarge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 10 : 6) {
            WidgetListHeader(count: entry.deadlines.count, isLarge: isLarge)

            if entry.deadlines.isEmpty {
                WidgetEmptyState(compact: !isLarge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: isLarge ? 6 : 5) {
                    ForEach(Array(entry.deadlines.prefix(maxRows).enumerated()), id: \.element.id) { index, deadline in
                        if isLarge && index > 0 {
                            Divider().padding(.leading, 10)
                        }
                        WidgetDeadlineRow(deadline: deadline, now: entry.date, isLarge: isLarge)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Hlavička „Nejbližší deadliny“ s počtem.
struct WidgetListHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    let isLarge: Bool

    var body: some View {
        let brand = WidgetBrand.color(for: colorScheme)

        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(brand)
            Text("Nejbližší deadliny")
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(brand))
            }
        }
        .font(isLarge ? .headline : .footnote.weight(.bold))
    }
}

/// Řádek seznamu: barevný proužek předmětu, název, „kód · typ“ a odpočet vpravo.
struct WidgetDeadlineRow: View {
    let deadline: WidgetDeadline
    let now: Date
    let isLarge: Bool

    var body: some View {
        let urgency = DeadlineUrgency(dueDate: deadline.dueDate, now: now)

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(deadline.title)
                    .font(isLarge ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                    .lineLimit(1)
                Text("\(deadline.subjectCode) · \(deadline.typeTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Countdown.text(for: deadline.dueDate, now: now))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(urgency.color)
                    .lineLimit(1)
                if isLarge {
                    Text(deadline.dueDate.deadlineFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color(hex: deadline.hexColor))
                .frame(width: 4)
        }
    }
}

// MARK: - Zamčená obrazovka

/// Obdélníkový widget: „KÓD · odpočet“, název a datum.
struct RectangularDeadlineView: View {
    let entry: DeadlineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let deadline = entry.nearest {
                Text("\(deadline.subjectCode) · \(Countdown.text(for: deadline.dueDate, now: entry.date))")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Text(deadline.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(deadline.dueDate.deadlineFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Vše hotovo")
                }
                .font(.headline)
                .widgetAccentable()
                Text("Žádné nadcházející deadliny")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kruhový widget: počet dní do nejbližšího deadlinu (nebo „Dnes“).
struct CircularDeadlineView: View {
    let entry: DeadlineEntry

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
        if let deadline = entry.nearest {
            let days = deadline.dueDate.calendarDays(from: entry.date)

            VStack(spacing: 0) {
                Text(deadline.subjectCode)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 44)

                if deadline.dueDate < entry.date {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.vertical, 1)
                    Text("Prošlo")
                        .font(.system(size: 10, weight: .semibold))
                } else if days == 0 {
                    Text("Dnes")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                    Text(deadline.dueDate.formatted(.dateTime.hour().minute().locale(.app)))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                } else {
                    Text("\(days)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(Self.dayUnit(days))
                        .font(.system(size: 10, weight: .medium))
                }
            }
        } else {
            VStack(spacing: 1) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                Text("Hotovo")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
    }

    /// Jednotka pod velkým číslem: „den / dny / dní“ (anglicky „day / days“).
    /// Vezme lokalizovanou frázi „%lld dní“ (plurálové varianty v katalogu) a odebere z ní číslo,
    /// takže stačí jeden klíč s počtem místo samostatného slova bez kontextu.
    private static func dayUnit(_ days: Int) -> String {
        let phrase = String(localized: "\(days) dní", comment: "Počet dní, např. „5 dní“ (plurál)")
        guard let range = phrase.range(of: String(days)) else { return phrase }
        var unit = phrase
        unit.removeSubrange(range)
        return unit.trimmingCharacters(in: .whitespaces)
    }
}

/// Řádkový widget, např. „AP9PT: Zítra · Zápočtový test“.
struct InlineDeadlineView: View {
    let entry: DeadlineEntry

    var body: some View {
        if let deadline = entry.nearest {
            Text("\(deadline.subjectCode): \(Countdown.text(for: deadline.dueDate, now: entry.date)) · \(deadline.title)")
        } else {
            Text("Vše hotovo – žádné deadliny")
        }
    }
}

// MARK: - Sdílené prvky

/// Štítek předmětu – kapsle v barvě předmětu s bílým kódem.
struct WidgetSubjectBadge: View {
    let code: String
    let hexColor: String

    var body: some View {
        Text(code)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color(hex: hexColor)))
    }
}

/// Prázdný stav – žádné nesplněné deadliny.
struct WidgetEmptyState: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(compact ? .title : .system(size: 44))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("Vše hotovo")
                .font(compact ? .subheadline.weight(.bold) : .title3.weight(.bold))
            Text("Žádné nadcházející deadliny")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

/// Barva značky Termínovníku – indigo, v tmavém režimu světlejší.
enum WidgetBrand {
    static let light = Color(hex: "#4F46E5")
    static let dark = Color(hex: "#818CF8")

    static func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}
