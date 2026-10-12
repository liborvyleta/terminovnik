import SwiftUI
import Foundation

// Denní časová osa rozvrhu – jako den v aplikaci Kalendář.
// Vlevo hodiny, vodorovné čáry, bloky akcí umístěné podle času a červená čára „teď“.
// Komponenta má pevnou výšku, rodič ji vkládá do ScrollView.

/// Denní časová osa rozvrhu ve stylu aplikace Kalendář.
///
/// Zobrazuje sloupec hodin, vodorovné čáry celých a půlhodin, bloky akcí umístěné
/// podle času (překrývající se akce vedle sebe ve sloupcích) a u dnešního dne
/// červenou čáru „teď“. Data dostává od rodiče (výskyty z `TimetableViewModel`).
/// Klepnutím na blok uživatel otevře detail akce přes `onSelect`. Komponenta má
/// pevnou výšku a používá se v denním režimu záložky Rozvrh uvnitř `ScrollView`.
struct TimetableDayTimelineView: View {
    /// Výskyty akcí zobrazovaného dne.
    let occurrences: [TimetableOccurrence]
    /// Aktuální čas pro čáru „teď“ a stav akcí.
    let now: Date
    /// Zda zobrazovaný den je dnešní (jinak se nekreslí čára „teď“ ani stav akcí).
    let isToday: Bool
    /// Vrací barvu předmětu pro danou akci.
    let color: (TimetableEvent) -> Color
    /// Volá se po klepnutí na blok akce.
    let onSelect: (TimetableOccurrence) -> Void

    /// Vytvoří časovou osu dne.
    /// - Parameters:
    ///   - occurrences: Výskyty akcí zobrazovaného dne.
    ///   - now: Aktuální čas.
    ///   - isToday: Zda jde o dnešní den.
    ///   - color: Funkce vracející barvu předmětu akce.
    ///   - onSelect: Akce po klepnutí na blok výskytu.
    init(occurrences: [TimetableOccurrence], now: Date, isToday: Bool,
         color: @escaping (TimetableEvent) -> Color,
         onSelect: @escaping (TimetableOccurrence) -> Void) {
        self.occurrences = occurrences
        self.now = now
        self.isToday = isToday
        self.color = color
        self.onSelect = onSelect
    }

    /// Měřítko displeje pro výpočet tloušťky vlasové čáry.
    @Environment(\.displayScale) private var displayScale
    /// Základní výška hodiny škálovaná podle Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var scaledHourHeight: CGFloat = 64

    /// Šířka sloupce s hodinami.
    private let labelWidth: CGFloat = 50
    /// Odsazení nahoře a dole, aby se popisky krajních hodin neořízly.
    private let verticalInset: CGFloat = 10
    /// Odsazení bloků od pravého okraje.
    private let trailingInset: CGFloat = 4
    /// Mezera mezi sloupci překrývajících se akcí.
    private let columnGap: CGFloat = 3

    /// Kalendář pro výpočty času.
    private var calendar: Calendar { .current }

    /// Výška jedné hodiny (roste s Dynamic Type, ale jen v rozmezí 56–110 bodů).
    private var hourHeight: CGFloat { min(max(scaledHourHeight, 56), 110) }

    // MARK: - Rozsah osy

    /// První zobrazená hodina: nejpozději 8:00, dříve pokud nějaká akce začíná dřív.
    private var firstHour: Int {
        let earliest = occurrences.map { minutesOfDay($0.start) }.min() ?? 8 * 60
        return max(0, min(8, earliest / 60))
    }

    /// Poslední zobrazená hodina: nejméně 16:00, později podle konce nejpozdější akce (max. 24).
    private var lastHour: Int {
        let latest = occurrences.map { endMinutes(of: $0) }.max() ?? 16 * 60
        let rounded = Int((Double(latest) / 60).rounded(.up))
        return min(24, max(16, rounded, firstHour + 1))
    }

    /// Celková výška osy včetně horního a dolního odsazení.
    private var totalHeight: CGFloat {
        CGFloat(lastHour - firstHour) * hourHeight + verticalInset * 2
    }

    // MARK: - Tělo

    /// Mřížka hodin, bloky akcí a čára „teď“ ve vrstvách `ZStack` uvnitř `GeometryReader`.
    var body: some View {
        GeometryReader { proxy in
            let gridWidth = max(proxy.size.width - labelWidth - trailingInset, 0)
            ZStack(alignment: .topLeading) {
                hourGrid(width: proxy.size.width)
                    .accessibilityHidden(true)

                ForEach(Self.layout(occurrences)) { placed in
                    block(for: placed, gridWidth: gridWidth)
                }

                if let nowY = nowLineY {
                    nowIndicator(width: proxy.size.width, y: nowY)
                }
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: - Mřížka hodin

    /// Mřížka s čarami celých a půlhodin a popisky hodin.
    /// - Parameter width: Celková šířka osy.
    /// - Returns: Vrstva mřížky hodin.
    private func hourGrid(width: CGFloat) -> some View {
        let hairline = 1 / max(displayScale, 1)
        let lineWidth = max(width - labelWidth, 0)
        return ZStack(alignment: .topLeading) {
            ForEach(firstHour...lastHour, id: \.self) { hour in
                let y = yPosition(minutes: hour * 60)

                // Celá hodina
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: lineWidth, height: hairline)
                    .offset(x: labelWidth, y: y)

                // Půlhodina (slabší)
                if hour < lastHour {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.35))
                        .frame(width: lineWidth, height: hairline)
                        .offset(x: labelWidth, y: y + hourHeight / 2)
                }

                // Popisek hodiny – skrytý, pokud by kolidoval s bublinou „teď“
                Text(verbatim: "\(hour):00")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - 8, height: 14, alignment: .trailing)
                    .offset(y: y - 7)
                    .opacity(isNearNowLine(y) ? 0 : 1)
            }
        }
    }

    // MARK: - Blok akce

    /// Klikatelný blok akce umístěný podle času a sloupce.
    /// - Parameters:
    ///   - placed: Výskyt s přiřazeným sloupcem a počtem sloupců.
    ///   - gridWidth: Šířka oblasti pro bloky (bez sloupce hodin).
    /// - Returns: Tlačítko s blokem akce, které volá `onSelect`.
    private func block(for placed: PlacedOccurrence, gridWidth: CGFloat) -> some View {
        let occurrence = placed.occurrence
        let columnWidth = (gridWidth - columnGap * CGFloat(placed.columnCount - 1)) / CGFloat(placed.columnCount)
        let x = labelWidth + 4 + CGFloat(placed.column) * (columnWidth + columnGap)
        let top = yPosition(minutes: minutesOfDay(occurrence.start))
        let bottom = yPosition(minutes: endMinutes(of: occurrence))
        let height = max(bottom - top - 2, 22)

        return Button {
            onSelect(occurrence)
        } label: {
            TimetableTimelineBlock(
                occurrence: occurrence,
                tint: color(occurrence.event),
                height: height,
                timeText: timeRange(occurrence),
                state: state(of: occurrence)
            )
        }
        .buttonStyle(TimelineBlockButtonStyle())
        .frame(width: max(columnWidth - 4, 0), height: height)
        .offset(x: x, y: top + 1)
        .zIndex(state(of: occurrence) == .ongoing ? 1 : 0)
        .accessibilityLabel(accessibilityLabel(for: occurrence))
        .accessibilityHint("Zobrazí podrobnosti akce")
    }

    // MARK: - Čára „teď“

    /// Svislá pozice čáry „teď“, nebo `nil`, pokud den není dnešní či čas leží mimo osu.
    private var nowLineY: CGFloat? {
        guard isToday else { return nil }
        let minutes = minutesOfDay(now)
        guard minutes >= firstHour * 60, minutes <= lastHour * 60 else { return nil }
        return yPosition(minutes: minutes)
    }

    /// Červená čára „teď“ s bublinou aktuálního času.
    /// - Parameters:
    ///   - width: Celková šířka osy.
    ///   - y: Svislá pozice čáry.
    /// - Returns: Indikátor aktuálního času.
    private func nowIndicator(width: CGFloat, y: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(clockText(now))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red, in: Capsule())
                .fixedSize()
                .frame(width: labelWidth - 3, alignment: .trailing)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .offset(x: -1)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
        }
        .frame(width: width, height: 20, alignment: .leading)
        .offset(y: y - 10)
        .shadow(color: Color.red.opacity(0.25), radius: 2)
        .allowsHitTesting(false)
        .zIndex(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nyní \(clockText(now))")
    }

    /// Zjistí, zda je pozice blízko čáry „teď“ (popisek hodiny by kolidoval s bublinou).
    /// - Parameter y: Svislá pozice popisku hodiny.
    /// - Returns: `true`, pokud je vzdálenost menší než 12 bodů.
    private func isNearNowLine(_ y: CGFloat) -> Bool {
        guard let nowY = nowLineY else { return false }
        return abs(nowY - y) < 12
    }

    // MARK: - Stav akce

    /// Určí stav výskytu vůči aktuálnímu času.
    /// - Parameter occurrence: Posuzovaný výskyt.
    /// - Returns: `.past`, `.ongoing` nebo `.upcoming`; mimo dnešní den vždy `.upcoming`.
    private func state(of occurrence: TimetableOccurrence) -> TimelineBlockState {
        guard isToday else { return .upcoming }
        if occurrence.end <= now { return .past }
        if occurrence.start <= now { return .ongoing }
        return .upcoming
    }

    // MARK: - Výpočty

    /// Převede čas na počet minut od půlnoci.
    /// - Parameter date: Datum s časem.
    /// - Returns: Minuty od začátku dne.
    private func minutesOfDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Konec výskytu v minutách; akce přes půlnoc končí ve 24:00.
    /// - Parameter occurrence: Výskyt akce.
    /// - Returns: Minuty od půlnoci, nejméně rovné začátku.
    private func endMinutes(of occurrence: TimetableOccurrence) -> Int {
        if !calendar.isDate(occurrence.end, inSameDayAs: occurrence.start) { return 24 * 60 }
        return max(minutesOfDay(occurrence.end), minutesOfDay(occurrence.start))
    }

    /// Převede minuty dne na svislou pozici na ose.
    /// - Parameter minutes: Minuty od půlnoci.
    /// - Returns: Souřadnice y.
    private func yPosition(minutes: Int) -> CGFloat {
        verticalInset + CGFloat(minutes - firstHour * 60) / 60 * hourHeight
    }

    /// Naformátuje čas jako „H:MM“.
    /// - Parameter date: Datum s časem.
    /// - Returns: Text času.
    private func clockText(_ date: Date) -> String {
        let minutes = minutesOfDay(date)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Naformátuje časový rozsah výskytu „H:MM–H:MM“.
    /// - Parameter occurrence: Výskyt akce.
    /// - Returns: Text rozsahu.
    private func timeRange(_ occurrence: TimetableOccurrence) -> String {
        "\(clockText(occurrence.start))–\(clockText(occurrence.end))"
    }

    /// Sestaví popisek bloku pro VoiceOver.
    /// - Parameter occurrence: Výskyt akce.
    /// - Returns: Název, kód, typ, čas, místnost, vyučující, parita a stav oddělené čárkami.
    private func accessibilityLabel(for occurrence: TimetableOccurrence) -> String {
        let event = occurrence.event
        var parts = [
            event.subjectName,
            String(localized: "kód \(event.subjectCode)", comment: "VoiceOver: kód předmětu"),
            event.typeName,
            String(localized: "od \(clockText(occurrence.start)) do \(clockText(occurrence.end))", comment: "VoiceOver: čas akce od–do")
        ]
        if let location = event.locationText { parts.append(String(localized: "místnost \(location)", comment: "VoiceOver: místnost akce")) }
        if let teacher = event.teacher, !teacher.isEmpty { parts.append(String(localized: "vyučující \(teacher)", comment: "VoiceOver: vyučující akce")) }
        if let parity = event.parityText { parts.append(parity) }
        switch state(of: occurrence) {
        case .past: parts.append(String(localized: "proběhlo", comment: "VoiceOver: akce už proběhla"))
        case .ongoing: parts.append(String(localized: "právě probíhá", comment: "VoiceOver: akce právě probíhá"))
        case .upcoming: break
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Rozložení překrývajících se akcí

    /// Výskyt akce s přiřazeným sloupcem v rámci skupiny překrývajících se akcí.
    ///
    /// Výsledek `layout(_:)`, podle kterého `block(for:gridWidth:)` počítá šířku a posun bloku.
    struct PlacedOccurrence: Identifiable {
        /// Umístěný výskyt.
        let occurrence: TimetableOccurrence
        /// Index sloupce (od 0).
        let column: Int
        /// Počet sloupců ve skupině překryvů.
        let columnCount: Int
        /// Identifikátor převzatý z výskytu.
        var id: String { occurrence.id }
    }

    /// Překrývající se akce rozdělí do sloupců vedle sebe (každá skupina překryvů má vlastní počet sloupců).
    /// - Parameter items: Výskyty akcí dne.
    /// - Returns: Výskyty seřazené podle začátku s přiřazeným sloupcem a počtem sloupců.
    static func layout(_ items: [TimetableOccurrence]) -> [PlacedOccurrence] {
        let sorted = items.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [PlacedOccurrence] = []
        var cluster: [(occurrence: TimetableOccurrence, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(columnEnds.count, 1)
            result += cluster.map { PlacedOccurrence(occurrence: $0.occurrence, column: $0.column, columnCount: count) }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for occurrence in sorted {
            if !cluster.isEmpty, occurrence.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= occurrence.start }) {
                columnEnds[free] = occurrence.end
                cluster.append((occurrence, free))
            } else {
                columnEnds.append(occurrence.end)
                cluster.append((occurrence, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, occurrence.end)
        }
        flush()
        return result
    }
}

// MARK: - Stav bloku

/// Stav bloku vůči aktuálnímu času.
///
/// Ovlivňuje vzhled bloku v `TimetableTimelineBlock` (proběhlé jsou vybledlé, probíhající zvýrazněné).
private enum TimelineBlockState {
    case past, ongoing, upcoming
}

// MARK: - Vzhled bloku

/// Vzhled jednoho bloku akce na časové ose.
///
/// Zobrazuje název, kód, typ, čas, místnost a u vysokých bloků vyučujícího; obsah
/// se přizpůsobuje výšce bloku. Probíhající akce má obrys, stín a štítek „Probíhá“,
/// proběhlá je vybledlá. Používá se jako popisek tlačítka v `TimetableDayTimelineView`.
private struct TimetableTimelineBlock: View {
    /// Zobrazovaný výskyt.
    let occurrence: TimetableOccurrence
    /// Barva předmětu.
    let tint: Color
    /// Výška bloku, podle které se volí rozvržení obsahu.
    let height: CGFloat
    /// Předformátovaný časový rozsah.
    let timeText: String
    /// Stav akce vůči aktuálnímu času.
    let state: TimelineBlockState

    /// Světlý / tmavý režim pro sytost barevného podkladu.
    @Environment(\.colorScheme) private var colorScheme

    /// Akce rozvrhu, ke které výskyt patří.
    private var event: TimetableEvent { occurrence.event }
    /// Tvar bloku se zaoblenými rohy.
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    /// Obsah s barevným podkladem a proužkem, obrysem, štítkem „Probíhá“ a stínem podle stavu.
    var body: some View {
        content
            .padding(.leading, 11)
            .padding(.trailing, 6)
            .padding(.vertical, height < 34 ? 3 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack(alignment: .leading) {
                    Color(.secondarySystemGroupedBackground)
                    tint.opacity(colorScheme == .dark ? 0.3 : 0.18)
                    Rectangle()
                        .fill(tint)
                        .frame(width: 4)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(tint.opacity(state == .ongoing ? 0.95 : 0.22),
                                   lineWidth: state == .ongoing ? 2 : 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if state == .ongoing && height >= 34 {
                    ongoingBadge
                }
            }
            .shadow(color: state == .ongoing ? tint.opacity(0.4) : .black.opacity(0.04),
                    radius: state == .ongoing ? 8 : 1.5, y: state == .ongoing ? 3 : 1)
            .saturation(state == .past ? 0.35 : 1)
            .opacity(state == .past ? 0.55 : 1)
    }

    /// Obsah bloku rozvržený podle výšky (jeden řádek až plný výpis).
    @ViewBuilder
    private var content: some View {
        if height < 34 {
            // Velmi krátký blok – jediný řádek
            HStack(spacing: 4) {
                Text(event.subjectName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        } else if height < 56 {
            // Krátký blok – název a čas s místností
            VStack(alignment: .leading, spacing: 2) {
                title(lines: 1)
                detailLine
            }
        } else if height < 100 {
            // Hodinový blok – název, štítek s typem, čas a místnost
            VStack(alignment: .leading, spacing: 3) {
                title(lines: 1)
                tagLine
                detailLine
            }
        } else {
            // Dlouhý blok – vše na samostatných řádcích
            VStack(alignment: .leading, spacing: 4) {
                title(lines: 2)
                tagLine
                Label(timeText, systemImage: "clock")
                    .monospacedDigit()
                    .lineLimit(1)
                if let location = event.locationText {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                }
                if height >= 150, let teacher = event.teacher, !teacher.isEmpty {
                    Label(teacher, systemImage: "person")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(TimelineCompactLabelStyle())
        }
    }

    /// Název předmětu; u probíhající akce s místem vpravo pro štítek.
    /// - Parameter lines: Maximální počet řádků.
    /// - Returns: Text názvu.
    private func title(lines: Int) -> some View {
        Text(event.subjectName)
            .font(.footnote.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .padding(.trailing, state == .ongoing ? 58 : 0)
    }

    /// Řádek se štítkem kódu a typem akce.
    private var tagLine: some View {
        HStack(spacing: 5) {
            TimetableCodeTag(code: event.subjectCode, tint: tint)
            Text(event.typeName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Řádek s časem a místností.
    private var detailLine: some View {
        HStack(spacing: 6) {
            Text(timeText)
                .monospacedDigit()
                .lineLimit(1)
            if let location = event.locationText {
                Label(location, systemImage: "mappin.and.ellipse")
                    .labelStyle(TimelineCompactLabelStyle())
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Bílý štítek „Probíhá“ v pravém horním rohu bloku.
    private var ongoingBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
            Text("Probíhá")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.gradient, in: Capsule())
        .padding(5)
    }
}

/// Styl popisku s ikonou a textem těsně u sebe.
///
/// Používá se v blocích časové osy pro čas, místnost a vyučujícího.
private struct TimelineCompactLabelStyle: LabelStyle {
    /// Sestaví ikonu a text vedle sebe s malou mezerou.
    /// - Parameter configuration: Konfigurace popisku.
    /// - Returns: Vodorovně uspořádaný popisek.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

/// Styl tlačítka s jemným zmenšením bloku při stisku.
///
/// Používá se pro bloky akcí v `TimetableDayTimelineView`.
private struct TimelineBlockButtonStyle: ButtonStyle {
    /// Zmenší popisek při stisku a nastaví tvar oblasti klepnutí.
    /// - Parameter configuration: Konfigurace tlačítka.
    /// - Returns: Upravený popisek tlačítka.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Náhled

/// Pomocný pohled pro náhled časové osy s ukázkovými daty.
///
/// Používá ukázkový rozvrh `TimetableSnapshot.sample` doplněný o překrývající se akci.
private struct TimetableDayTimelinePreview: View {
    /// Nejbližší úterý, pro které se náhled zobrazuje.
    private let tuesday: Date
    /// Výskyty akcí v daném dni.
    private let occurrences: [TimetableOccurrence]

    /// Připraví ukázková data nejbližšího úterý včetně překrývající se akce.
    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let day = (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .first { TimetableEvent.weekday(of: $0, calendar: calendar) == 2 } ?? today
        tuesday = day

        var snapshot = TimetableSnapshot.sample
        // Překrývající se akce pro ukázku rozdělení do sloupců
        snapshot.events.append(
            TimetableEvent(id: "p1", subjectCode: "AP9DM", department: "AUIUI", subjectName: "Datamining",
                           typeName: "Seminář", typeShort: "Se", weekday: 2, startTime: "11:00", endTime: "12:30",
                           building: "53", room: "105", teacher: "Ing. Tomáš Kučera", weekParity: "Každý",
                           dateFrom: nil, dateTo: nil, singleDate: nil, hexColor: "#12A594")
        )
        occurrences = snapshot.occurrences(on: day, calendar: calendar)
    }

    var body: some View {
        ScrollView {
            TimetableDayTimelineView(
                occurrences: occurrences,
                now: Calendar.current.date(byAdding: .minute, value: 11 * 60 + 20, to: tuesday) ?? .now,
                isToday: true,
                color: { Color(hex: $0.hexColor ?? "#5B5BD6") },
                onSelect: { _ in }
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Světlý") {
    TimetableDayTimelinePreview()
}

#Preview("Tmavý") {
    TimetableDayTimelinePreview()
        .preferredColorScheme(.dark)
}
