import Foundation
import SwiftUI
import UIKit

// Týdenní mřížka rozvrhu – klasický rozvrh jako ve STAGu (dny ve sloupcích, hodiny v řádcích)
// v současném vizuálním stylu. Komponenta má pevnou výšku, rodič ji vkládá do `ScrollView`.

struct TimetableWeekGridView: View {
    private let days: [Date]
    private let occurrences: (Date) -> [TimetableOccurrence]
    private let now: Date
    private let color: (TimetableEvent) -> Color
    private let onSelect: (TimetableOccurrence) -> Void

    init(days: [Date],
         occurrences: @escaping (Date) -> [TimetableOccurrence],
         now: Date,
         color: @escaping (TimetableEvent) -> Color,
         onSelect: @escaping (TimetableOccurrence) -> Void) {
        self.days = days
        self.occurrences = occurrences
        self.now = now
        self.color = color
        self.onSelect = onSelect
    }

    @Environment(\.colorScheme) private var colorScheme

    private let calendar = Calendar.current

    // MARK: - Rozměry

    /// Výška jedné hodiny
    private let hourHeight: CGFloat = 52
    /// Výška hlavičky se dny
    private let headerHeight: CGFloat = 48
    /// Šířka levého sloupce s hodinami
    private let timeColumnWidth: CGFloat = 34
    /// Místo nad první čarou (aby se vešel popisek první hodiny)
    private let gridTopInset: CGFloat = 8
    /// Místo pod poslední čarou
    private let bottomInset: CGFloat = 10
    /// Vnitřní okraj karty
    private let cardPadding: CGFloat = 6

    private var isDark: Bool { colorScheme == .dark }
    private var gridTop: CGFloat { headerHeight + gridTopInset }

    // MARK: - Tělo

    var body: some View {
        let columns = days.map { day in
            GridDayColumn(date: day, items: Self.layout(occurrences(day)))
        }
        let hours = hourRange(for: columns)
        let gridHeight = CGFloat(hours.upperBound - hours.lowerBound) * hourHeight
        let totalHeight = gridTop + gridHeight + bottomInset
        let todayIndex = columns.firstIndex { calendar.isDate($0.date, inSameDayAs: now) }
        let nowY = todayIndex == nil ? nil : nowOffset(in: hours)

        GeometryReader { proxy in
            let columnWidth = max(0, (proxy.size.width - timeColumnWidth) / CGFloat(max(columns.count, 1)))

            ZStack(alignment: .topLeading) {
                if let todayIndex {
                    todayHighlight(index: todayIndex, columnWidth: columnWidth, height: totalHeight)
                }

                gridLines(hours: hours, columnCount: columns.count, columnWidth: columnWidth,
                          width: proxy.size.width, height: totalHeight)

                hourLabels(hours: hours, hiddenAround: nowY)

                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    dayHeader(column.date, isToday: index == todayIndex)
                        .frame(width: columnWidth, height: headerHeight)
                        .offset(x: timeColumnWidth + CGFloat(index) * columnWidth)

                    ForEach(column.items) { placed in
                        block(placed, columnIndex: index, columnWidth: columnWidth, hours: hours)
                    }
                }

                if let todayIndex, let nowY {
                    nowIndicator(x: timeColumnWidth + CGFloat(todayIndex) * columnWidth,
                                 y: nowY, columnWidth: columnWidth)
                }
            }
        }
        .frame(height: totalHeight)
        .padding(.horizontal, cardPadding)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Hlavička dne

    private func dayHeader(_ date: Date, isToday: Bool) -> some View {
        VStack(spacing: 3) {
            Text(GridFormat.shortWeekday(date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : Color(.secondaryLabel))
            Text(date, format: .dateTime.day())
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(minWidth: 22)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    if isToday {
                        Capsule().fill(Color.accentColor.gradient)
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isToday ? String(localized: "\(GridFormat.fullDate(date)), dnes", comment: "VoiceOver: datum v hlavičce sloupce, dnešní den") : GridFormat.fullDate(date))
        .accessibilityAddTraits(.isHeader)
    }

    /// Jemné podbarvení celého dnešního sloupce
    private func todayHighlight(index: Int, columnWidth: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(isDark ? 0.13 : 0.06))
            .frame(width: max(0, columnWidth - 2), height: height - 8)
            .offset(x: timeColumnWidth + CGFloat(index) * columnWidth + 1, y: 4)
            .accessibilityHidden(true)
    }

    // MARK: - Mřížka

    private func gridLines(hours: ClosedRange<Int>, columnCount: Int, columnWidth: CGFloat,
                           width: CGFloat, height: CGFloat) -> some View {
        let hourCount = hours.upperBound - hours.lowerBound
        return ZStack(alignment: .topLeading) {
            // Půlhodiny – čárkovaně
            Path { path in
                for hour in 0..<hourCount {
                    let y = gridTop + (CGFloat(hour) + 0.5) * hourHeight
                    path.move(to: CGPoint(x: timeColumnWidth, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color(.separator).opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

            // Celé hodiny
            Path { path in
                for hour in 0...hourCount {
                    let y = gridTop + CGFloat(hour) * hourHeight
                    path.move(to: CGPoint(x: timeColumnWidth - 4, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color(.separator).opacity(0.7), lineWidth: 0.5)

            // Svislé oddělovače dnů
            Path { path in
                for column in 0...columnCount {
                    let x = timeColumnWidth + CGFloat(column) * columnWidth
                    path.move(to: CGPoint(x: x, y: gridTop))
                    path.addLine(to: CGPoint(x: x, y: height - bottomInset))
                }
            }
            .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func hourLabels(hours: ClosedRange<Int>, hiddenAround nowY: CGFloat?) -> some View {
        ForEach(Array(hours), id: \.self) { hour in
            let y = gridTop + CGFloat(hour - hours.lowerBound) * hourHeight
            let isCovered = nowY.map { abs($0 - y) < 11 } ?? false
            Text(verbatim: "\(hour):00")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: timeColumnWidth - 7, height: 12, alignment: .trailing)
                .offset(y: y - 6)
                .opacity(isCovered ? 0 : 1)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Bloky akcí

    @ViewBuilder
    private func block(_ placed: GridPlacedOccurrence, columnIndex: Int, columnWidth: CGFloat,
                       hours: ClosedRange<Int>) -> some View {
        let occurrence = placed.occurrence
        let top = offset(for: occurrence.start, dayOf: occurrence.start, in: hours)
        let bottom = offset(for: occurrence.end, dayOf: occurrence.start, in: hours)
        let inset: CGFloat = 1.5
        let slotWidth = columnWidth / CGFloat(placed.columnCount)
        let width = max(0, slotWidth - inset * 2)
        let height = max(18, bottom - top - inset * 2)
        let x = timeColumnWidth + CGFloat(columnIndex) * columnWidth + CGFloat(placed.column) * slotWidth + inset

        Button {
            onSelect(occurrence)
        } label: {
            GridEventBlock(occurrence: occurrence,
                           tint: color(occurrence.event),
                           isPast: occurrence.end <= now,
                           isOngoing: occurrence.start <= now && now < occurrence.end,
                           isDark: isDark,
                           height: height)
        }
        .buttonStyle(GridBlockButtonStyle())
        .frame(width: width, height: height)
        .offset(x: x, y: top + inset)
        .accessibilityLabel(accessibilityLabel(for: occurrence))
        .accessibilityHint("Zobrazí podrobnosti akce")
    }

    private func accessibilityLabel(for occurrence: TimetableOccurrence) -> String {
        let event = occurrence.event
        var parts = [
            GridFormat.fullDate(occurrence.start),
            String(localized: "\(GridFormat.time(occurrence.start)) až \(GridFormat.time(occurrence.end))", comment: "VoiceOver: čas od–do"),
            "\(event.subjectName) (\(event.subjectCode))",
            event.typeName
        ]
        if let location = event.locationText {
            parts.append(String(localized: "místnost \(location)", comment: "VoiceOver: místnost akce"))
        }
        if occurrence.end <= now {
            parts.append(String(localized: "proběhlo", comment: "VoiceOver: akce už proběhla"))
        } else if occurrence.start <= now {
            parts.append(String(localized: "právě probíhá", comment: "VoiceOver: akce právě probíhá"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Čára „teď“

    private func nowIndicator(x: CGFloat, y: CGFloat, columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.red)
                .frame(width: columnWidth, height: 1.5)
                .offset(x: x, y: y - 0.75)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .offset(x: x - 4, y: y - 4)
            Text(GridFormat.time(now))
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .background(Color.red, in: Capsule())
                .frame(width: timeColumnWidth - 3, height: 14, alignment: .trailing)
                .offset(y: y - 7)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Výpočty

    /// Rozsah zobrazených hodin – podle nejdřívější a nejpozdější akce v týdnu, minimálně 8–16
    private func hourRange(for columns: [GridDayColumn]) -> ClosedRange<Int> {
        var first = 8
        var last = 16
        for column in columns {
            for placed in column.items {
                let start = minutesFromStartOfDay(placed.occurrence.start, dayOf: placed.occurrence.start)
                let end = minutesFromStartOfDay(placed.occurrence.end, dayOf: placed.occurrence.start)
                first = min(first, Int(start) / 60)
                last = max(last, Int((end / 60).rounded(.up)))
            }
        }
        first = max(0, first)
        last = min(24, max(last, first + 1))
        return first...last
    }

    private func minutesFromStartOfDay(_ date: Date, dayOf reference: Date) -> Double {
        let minutes = date.timeIntervalSince(calendar.startOfDay(for: reference)) / 60
        return min(max(minutes, 0), 24 * 60)
    }

    /// Svislá pozice času v mřížce
    private func offset(for date: Date, dayOf reference: Date, in hours: ClosedRange<Int>) -> CGFloat {
        let minutes = minutesFromStartOfDay(date, dayOf: reference) - Double(hours.lowerBound * 60)
        return gridTop + CGFloat(minutes / 60) * hourHeight
    }

    /// Pozice čáry „teď“, pokud aktuální čas spadá do zobrazeného rozsahu
    private func nowOffset(in hours: ClosedRange<Int>) -> CGFloat? {
        let minutes = minutesFromStartOfDay(now, dayOf: now)
        guard minutes >= Double(hours.lowerBound * 60), minutes <= Double(hours.upperBound * 60) else { return nil }
        return offset(for: now, dayOf: now, in: hours)
    }

    /// Rozmístí překrývající se akce vedle sebe – shluky navzájem se překrývajících akcí
    /// se rozdělí do sloupců, každá akce dostane první volný sloupec.
    static func layout(_ items: [TimetableOccurrence]) -> [GridPlacedOccurrence] {
        let sorted = items.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end > rhs.end : lhs.start < rhs.start
        }
        var result: [GridPlacedOccurrence] = []
        var cluster: [(occurrence: TimetableOccurrence, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(columnEnds.count, 1)
            result += cluster.map { GridPlacedOccurrence(occurrence: $0.occurrence, column: $0.column, columnCount: count) }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for item in sorted {
            if !cluster.isEmpty, item.start >= clusterEnd {
                flush()
            }
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = item.end
                cluster.append((item, free))
            } else {
                columnEnds.append(item.end)
                cluster.append((item, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, item.end)
        }
        flush()
        return result
    }
}

// MARK: - Pomocné typy

/// Jeden den (sloupec) mřížky s rozmístěnými akcemi
private struct GridDayColumn {
    let date: Date
    let items: [GridPlacedOccurrence]
}

/// Akce s přiděleným podsloupcem (kvůli překryvům)
struct GridPlacedOccurrence: Identifiable {
    let occurrence: TimetableOccurrence
    /// Index podsloupce v rámci shluku překrývajících se akcí
    let column: Int
    /// Počet podsloupců ve shluku
    let columnCount: Int

    var id: String { occurrence.id }
}

/// Barevný blok jedné akce v mřížce
private struct GridEventBlock: View {
    let occurrence: TimetableOccurrence
    let tint: Color
    let isPast: Bool
    let isOngoing: Bool
    let isDark: Bool
    let height: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        let event = occurrence.event

        VStack(alignment: .leading, spacing: 1) {
            Text(event.subjectCode)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.primary)
            if height >= 32, let location = event.locationText {
                Text(location)
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            if height >= 44 {
                Text(event.typeShort)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(isDark ? 0.35 : 0.22))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint)
                .frame(width: 3)
        }
        .clipShape(shape)
        .overlay {
            if isOngoing {
                shape.strokeBorder(tint, lineWidth: 1.5)
            }
        }
        .saturation(isPast ? 0.5 : 1)
        .opacity(isPast ? 0.5 : 1)
        .contentShape(shape)
    }
}

/// Jemné zmenšení bloku při stisku
private struct GridBlockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Formátování dat pro mřížku (v jazyce aplikace)
private enum GridFormat {
    private static let locale = Locale.czech

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEEEE"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        // Česky „EEEE d. MMMM“, v ostatních jazycích jejich obvyklé pořadí
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    /// „Po“, „Út“, …
    static func shortWeekday(_ date: Date) -> String {
        shortWeekdayFormatter.string(from: date).capitalized(with: locale)
    }

    /// „pondělí 5. října“
    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    /// „10:00“
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

// MARK: - Náhled

private struct TimetableWeekGridPreview: View {
    private let snapshot = TimetableSnapshot.sample

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let monday = calendar.date(byAdding: .day, value: 1 - TimetableEvent.weekday(of: today), to: today) ?? today
        return (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        ScrollView {
            TimetableWeekGridView(
                days: weekDays,
                occurrences: { snapshot.occurrences(on: $0) },
                now: .now,
                color: { Color(hex: $0.hexColor ?? "#5856D6") },
                onSelect: { _ in }
            )
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Týdenní mřížka – světlý") {
    TimetableWeekGridPreview()
        .preferredColorScheme(.light)
}

#Preview("Týdenní mřížka – tmavý") {
    TimetableWeekGridPreview()
        .preferredColorScheme(.dark)
}
