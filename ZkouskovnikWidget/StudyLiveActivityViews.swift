import ActivityKit
import SwiftUI
import WidgetKit

// Pohledy Live Activity „Hodina / zkouška“. Žádný z nich nepotřebuje `ActivityViewContext`,
// takže je lze vykreslit i mimo widget (snímky obrazovky, #Preview, ImageRenderer).
//
// Live Activity se sama nepřekresluje – stav (před začátkem / probíhá / termín) se určí
// v okamžiku vykreslení a živé hodnoty obstarají jen `Text(timerInterval:)`
// a `ProgressView(timerInterval:)`. Přechod „Začíná za“ → „Končí za“ zajistí aplikace aktualizací.

// MARK: - Stav

/// Fáze sledované hodiny / zkoušky vůči aktuálnímu času.
///
/// Určuje popisky, cíl odpočtu a ikony v pohledech Live Activity.
enum StudyActivityPhase: Equatable {
    /// Hodina nebo zkouška s délkou ještě nezačala.
    case upcoming
    /// Probíhá (start ≤ teď < end).
    case ongoing
    /// Deadline bez délky (end ≤ start), termín ještě nenastal.
    case deadline
    /// Skončilo, nebo termín už nastal.
    case finished

    /// Určí fázi ze stavu aktivity a aktuálního času.
    ///
    /// - Parameters:
    ///   - attributes: Neměnné údaje aktivity; pro výpočet se nepoužívají.
    ///   - state: Stav se začátkem a koncem.
    ///   - now: Okamžik, vůči kterému se fáze určuje; výchozí je aktuální čas.
    init(attributes: StudyActivityAttributes, state: StudyActivityAttributes.ContentState, now: Date = .now) {
        let isPointInTime = state.end <= state.start
        if isPointInTime {
            self = now < state.start ? .deadline : .finished
        } else if now < state.start {
            self = .upcoming
        } else if now < state.end {
            self = .ongoing
        } else {
            self = .finished
        }
    }
}

/// Vše, co pohledy Live Activity potřebují – spočítané jednou pro jedno vykreslení.
///
/// Odvozuje fázi, popisky, cíl a rozsah odpočtu, text času a ikony.
struct StudyActivityModel {
    /// Neměnné údaje aktivity.
    let attributes: StudyActivityAttributes
    /// Proměnný stav aktivity.
    let state: StudyActivityAttributes.ContentState
    /// Okamžik vykreslení.
    let now: Date
    /// Fáze odvozená ze stavu a `now`.
    let phase: StudyActivityPhase

    /// Vytvoří model a spočítá fázi.
    ///
    /// - Parameters:
    ///   - attributes: Neměnné údaje aktivity.
    ///   - state: Proměnný stav aktivity.
    ///   - now: Okamžik vykreslení; výchozí je aktuální čas.
    init(attributes: StudyActivityAttributes, state: StudyActivityAttributes.ContentState, now: Date = .now) {
        self.attributes = attributes
        self.state = state
        self.now = now
        self.phase = StudyActivityPhase(attributes: attributes, state: state, now: now)
    }

    /// Popisek nad odpočtem na zamčené obrazovce.
    ///
    /// - Returns: „Začíná za“, „Končí za“, „Do termínu“, nebo „Termín nastal“ / „Skončilo“.
    var countdownLabel: String {
        switch phase {
        case .upcoming: String(localized: "Začíná za", comment: "Live Activity: popisek nad odpočtem do začátku hodiny")
        case .ongoing: String(localized: "Končí za", comment: "Live Activity: popisek nad odpočtem do konce hodiny")
        case .deadline: String(localized: "Do termínu", comment: "Live Activity: popisek nad odpočtem do termínu zkoušky")
        case .finished:
            attributes.kind == .exam && state.end <= state.start
                ? String(localized: "Termín nastal", comment: "Live Activity: termín zkoušky už nastal")
                : String(localized: "Skončilo", comment: "Live Activity: hodina skončila")
        }
    }

    /// Kratší popisek pro Dynamic Island.
    ///
    /// - Returns: „za“, „končí za“, „do termínu“, nebo „konec“.
    var shortLabel: String {
        switch phase {
        case .upcoming: String(localized: "za", comment: "Dynamic Island: krátký popisek nad odpočtem do začátku („za 12:00“)")
        case .ongoing: String(localized: "končí za", comment: "Dynamic Island: krátký popisek nad odpočtem do konce")
        case .deadline: String(localized: "do termínu", comment: "Dynamic Island: krátký popisek nad odpočtem do termínu")
        case .finished: String(localized: "konec", comment: "Dynamic Island: hodina skončila")
        }
    }

    /// Cíl odpočtu.
    ///
    /// - Returns: Začátek před hodinou nebo termínem, konec během hodiny, `nil` po skončení.
    var countdownTarget: Date? {
        switch phase {
        case .upcoming, .deadline: state.start
        case .ongoing: state.end
        case .finished: nil
        }
    }

    /// Bezpečný rozsah pro `Text(timerInterval:)` – dolní mez nikdy nepřeskočí horní.
    ///
    /// - Returns: Rozsah od `min(now, cíl)` do cíle, nebo `nil` bez cíle.
    var countdownRange: ClosedRange<Date>? {
        guard let target = countdownTarget else { return nil }
        return min(now, target)...target
    }

    /// Rozsah hodiny pro `ProgressView(timerInterval:)`.
    ///
    /// - Returns: Rozsah od začátku do konce (nejméně do začátku).
    var lessonRange: ClosedRange<Date> {
        state.start...max(state.start, state.end)
    }

    /// Zda zobrazit průběh hodiny.
    ///
    /// - Returns: `true` jen ve fázi `.ongoing`.
    var showsProgress: Bool { phase == .ongoing }

    /// Zbývající sekundy do cíle – určují šířku odpočtu („12:00“ vs. „1:12:00“).
    ///
    /// - Returns: Nezáporný počet sekund; bez cíle 0.
    var remaining: TimeInterval {
        guard let target = countdownTarget else { return 0 }
        return max(0, target.timeIntervalSince(now))
    }

    /// Text času hodiny nebo termínu.
    ///
    /// U hodiny „10:00–12:00“ (jiný den s předponou dne), u deadlinu „dnes 14:30“ / „st 7. 10. 9:00“.
    ///
    /// - Returns: Naformátovaný text.
    var timeText: String {
        if state.end <= state.start {
            return StudyActivityFormat.dayAndTime(state.start, now: now)
        } else {
            let range = "\(StudyActivityFormat.time(state.start))–\(StudyActivityFormat.time(state.end))"
            return Calendar.current.isDate(state.start, inSameDayAs: now)
                ? range
                : "\(StudyActivityFormat.dayPrefix(state.start, now: now)) \(range)"
        }
    }

    /// SF Symbol podle typu akce.
    ///
    /// - Returns: Název symbolu z `StudyActivityFormat.symbol(typeName:kind:)`.
    var typeSymbol: String {
        StudyActivityFormat.symbol(typeName: attributes.typeName, kind: attributes.kind)
    }

    /// SF Symbol podle fáze.
    ///
    /// - Returns: Hodiny, přehrávání, symbol typu u deadlinu, nebo fajfka po skončení.
    var phaseSymbol: String {
        switch phase {
        case .upcoming: "clock.fill"
        case .ongoing: "play.circle.fill"
        case .deadline: typeSymbol
        case .finished: "checkmark.circle.fill"
        }
    }
}

// MARK: - Zamčená obrazovka

/// Obsah Live Activity na zamčené obrazovce a v banneru.
///
/// Vlevo štítek + typ, název a místnost, vpravo velký živý odpočet s časem, u probíhající
/// hodiny pod tím průběh. Bez ActivityKit kontextu – jde vykreslit i mimo widget.
/// `drawsBackground` přidá vlastní zaoblené pozadí (pro snímky mimo zamčenou obrazovku,
/// kde nepůsobí `activityBackgroundTint`).
struct StudyActivityLockScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Neměnné údaje aktivity.
    let attributes: StudyActivityAttributes
    /// Proměnný stav aktivity.
    let state: StudyActivityAttributes.ContentState
    /// Zda vykreslit vlastní zaoblené pozadí; výchozí je `false`.
    var drawsBackground = false

    /// Obsah pohledu `StudyActivityLockScreenView` sestavený z jeho vstupních hodnot.
    var body: some View {
        let model = StudyActivityModel(attributes: attributes, state: state)
        let accent = StudyActivityStyle.accent(attributes.hexColor, scheme: colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                details(model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                countdown(model, accent: accent)
            }

            if model.showsProgress {
                StudyActivityProgressBar(model: model, tint: accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            if drawsBackground {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(StudyActivityStyle.background(attributes.hexColor, scheme: colorScheme))
            }
        }
        .environment(\.locale, .app)
    }

    /// Levý sloupec s předmětem, typem, názvem a místností.
    ///
    /// - Parameter model: Vypočtený model aktivity pro jedno vykreslení.
    /// - Returns: Svislé rozvržení detailů.
    private func details(_ model: StudyActivityModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                WidgetSubjectBadge(code: attributes.subjectCode, hexColor: attributes.hexColor)
                Label(attributes.typeName, systemImage: model.typeSymbol)
                    .labelStyle(StudyActivityCompactLabelStyle())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(attributes.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            if let location = state.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .labelStyle(StudyActivityCompactLabelStyle())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Pravý sloupec s popiskem, živým odpočtem (nebo ikonou fáze) a časem.
    ///
    /// - Parameters:
    ///   - model: Vypočtený model aktivity pro jedno vykreslení.
    ///   - accent: Barva odpočtu.
    /// - Returns: Svislé rozvržení odpočtu s pevnou šířkou.
    private func countdown(_ model: StudyActivityModel, accent: Color) -> some View {
        let size: CGFloat = 34
        let width = StudyActivityFormat.timerWidth(remaining: model.remaining, fontSize: size)

        return VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                if model.phase == .deadline {
                    Image(systemName: model.typeSymbol)
                }
                Text(model.countdownLabel)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Group {
                if let range = model.countdownRange {
                    Text(timerInterval: range, countsDown: true)
                        .multilineTextAlignment(.trailing)
                        .frame(width: width, alignment: .trailing)
                } else {
                    Image(systemName: model.phaseSymbol)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(model.timeText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Průběh hodiny v barvě předmětu, volitelně s časy po stranách.
///
/// Plní se sám pomocí `ProgressView(timerInterval:)`.
struct StudyActivityProgressBar: View {
    /// Vypočtený model aktivity pro jedno vykreslení.
    let model: StudyActivityModel
    /// Barva ukazatele průběhu.
    let tint: Color
    /// Zda zobrazit čas začátku a konce; výchozí je `true`.
    var showsTimes = true

    /// Obsah pohledu `StudyActivityProgressBar` sestavený z jeho vstupních hodnot.
    var body: some View {
        HStack(spacing: 8) {
            if showsTimes {
                Text(StudyActivityFormat.time(model.state.start))
            }
            ProgressView(timerInterval: model.lessonRange, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
            if showsTimes {
                Text(StudyActivityFormat.time(model.state.end))
            }
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

/// Styl popisku s ikonou a textem těsně u sebe.
///
/// Systémový `Label` má ve widgetech velkou mezeru.
struct StudyActivityCompactLabelStyle: LabelStyle {
    /// Vykreslí ikonu a text vedle sebe s mezerou 3 body.
    ///
    /// - Parameter configuration: Konfigurace popisku s ikonou a textem.
    /// - Returns: Vodorovné rozvržení popisku.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Dynamic Island

/// Rozbalený Dynamic Island, levá oblast.
///
/// Štítek předmětu a typ akce.
struct StudyIslandLeadingView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandLeadingView` sestavený z jeho vstupních hodnot.
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetSubjectBadge(code: model.attributes.subjectCode, hexColor: model.attributes.hexColor)
            Label(model.attributes.typeName, systemImage: model.typeSymbol)
                .labelStyle(StudyActivityCompactLabelStyle())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rozbalený Dynamic Island, pravá oblast.
///
/// Krátký popisek a velký živý odpočet (nebo ikona fáze).
struct StudyIslandTrailingView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandTrailingView` sestavený z jeho vstupních hodnot.
    var body: some View {
        let accent = StudyActivityStyle.vivid(model.attributes.hexColor)
        let size: CGFloat = 24

        VStack(alignment: .trailing, spacing: 0) {
            Text(model.shortLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Group {
                if let range = model.countdownRange {
                    Text(timerInterval: range, countsDown: true)
                        .multilineTextAlignment(.trailing)
                        .frame(width: StudyActivityFormat.timerWidth(remaining: model.remaining, fontSize: size),
                               alignment: .trailing)
                } else {
                    Image(systemName: model.phaseSymbol)
                }
            }
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Rozbalený Dynamic Island, středová oblast.
///
/// Název předmětu.
struct StudyIslandCenterView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandCenterView` sestavený z jeho vstupních hodnot.
    var body: some View {
        Text(model.attributes.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
}

/// Rozbalený Dynamic Island, spodní oblast.
///
/// Místnost a čas, u probíhající hodiny průběh.
struct StudyIslandBottomView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandBottomView` sestavený z jeho vstupních hodnot.
    var body: some View {
        let accent = StudyActivityStyle.vivid(model.attributes.hexColor)

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let location = model.state.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .labelStyle(StudyActivityCompactLabelStyle())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.25)))
                }
                Spacer(minLength: 4)
                Label(model.timeText, systemImage: model.phase == .deadline ? "calendar" : "clock")
                    .labelStyle(StudyActivityCompactLabelStyle())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)

            if model.showsProgress {
                StudyActivityProgressBar(model: model, tint: accent, showsTimes: false)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

/// Kompaktní Dynamic Island, levá strana.
///
/// Ikona typu a kód předmětu v barvě předmětu.
struct StudyIslandCompactLeadingView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandCompactLeadingView` sestavený z jeho vstupních hodnot.
    var body: some View {
        let accent = StudyActivityStyle.vivid(model.attributes.hexColor)

        HStack(spacing: 4) {
            Image(systemName: model.typeSymbol)
                .font(.system(size: 11, weight: .bold))
            Text(model.attributes.subjectCode)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(accent)
        .frame(maxWidth: 70, alignment: .leading)
        .padding(.leading, 2)
    }
}

/// Kompaktní Dynamic Island, pravá strana.
///
/// Krátký odpočet s pevnou šířkou, po skončení ikona fáze.
struct StudyIslandCompactTrailingView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandCompactTrailingView` sestavený z jeho vstupních hodnot.
    var body: some View {
        let accent = StudyActivityStyle.vivid(model.attributes.hexColor)
        let size: CGFloat = 14

        Group {
            if let range = model.countdownRange {
                Text(timerInterval: range, countsDown: true)
                    .multilineTextAlignment(.trailing)
                    .frame(width: StudyActivityFormat.timerWidth(remaining: model.remaining, fontSize: size))
            } else {
                Image(systemName: model.phaseSymbol)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(accent)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.trailing, 2)
    }
}

/// Minimální Dynamic Island.
///
/// Kroužek v barvě předmětu s ikonou typu, během hodiny s ikonou přehrávání.
struct StudyIslandMinimalView: View {
    let model: StudyActivityModel

    /// Obsah pohledu `StudyIslandMinimalView` sestavený z jeho vstupních hodnot.
    var body: some View {
        ZStack {
            Circle()
                .fill(StudyActivityStyle.vivid(model.attributes.hexColor))
            Image(systemName: model.phase == .ongoing ? "play.fill" : model.typeSymbol)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Styl a formátování

/// Barvy Live Activity odvozené z barvy předmětu.
///
/// Čitelné ve světlém i tmavém režimu.
enum StudyActivityStyle {
    /// Barva odpočtu: v tmavém režimu zesvětlená, aby měla kontrast.
    ///
    /// - Parameters:
    ///   - hex: Barva předmětu v hexadecimálním zápisu.
    ///   - scheme: Aktuální barevný režim.
    /// - Returns: Barva zvýraznění.
    static func accent(_ hex: String, scheme: ColorScheme) -> Color {
        scheme == .dark ? vivid(hex) : Color(hex: hex)
    }

    /// Zesvětlená barva předmětu pro černé pozadí (Dynamic Island, tmavý režim).
    ///
    /// - Parameter hex: Barva předmětu v hexadecimálním zápisu.
    /// - Returns: Barva smíchaná z 30 % s bílou.
    static func vivid(_ hex: String) -> Color {
        mixed(hex, with: (1, 1, 1), amount: 0.3)
    }

    /// Jemně tónované neprůhledné pozadí zamčené obrazovky.
    ///
    /// - Parameters:
    ///   - hex: Barva předmětu v hexadecimálním zápisu.
    ///   - scheme: Aktuální barevný režim.
    /// - Returns: Barva pozadí.
    static func background(_ hex: String, scheme: ColorScheme) -> Color {
        scheme == .dark
            ? mixed(hex, with: (0.11, 0.11, 0.12), amount: 0.82)
            : mixed(hex, with: (1, 1, 1), amount: 0.9)
    }

    /// Smíchá barvu předmětu s jinou barvou.
    ///
    /// - Parameters:
    ///   - hex: Barva předmětu v hexadecimálním zápisu.
    ///   - other: Druhá barva jako složky RGB v rozsahu 0–1.
    ///   - amount: Podíl druhé barvy (0–1).
    /// - Returns: Neprůhledná výsledná barva v sRGB.
    private static func mixed(_ hex: String, with other: (Double, Double, Double), amount: Double) -> Color {
        let base = rgb(hex)
        return Color(
            .sRGB,
            red: base.0 + (other.0 - base.0) * amount,
            green: base.1 + (other.1 - base.1) * amount,
            blue: base.2 + (other.2 - base.2) * amount,
            opacity: 1
        )
    }

    /// Převede hexadecimální zápis na složky RGB.
    ///
    /// - Parameter hex: Barva ve tvaru „#RRGGBB“ nebo „RRGGBB“.
    /// - Returns: Složky v rozsahu 0–1; při neplatném zápisu šedá (0,5; 0,5; 0,5).
    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return (0.5, 0.5, 0.5) }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

/// Formátování pro Live Activity.
///
/// Používá jazyk aplikace (česky bez úvodní nuly: „8:00“).
enum StudyActivityFormat {
    /// Naformátuje čas na hodiny a minuty.
    ///
    /// - Parameter date: Formátované datum.
    /// - Returns: Čas, např. „8:00“.
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(.app))
    }

    /// Předpona dne: „dnes“, „zítra“, nebo „st 7. 10.“.
    ///
    /// - Parameters:
    ///   - date: Formátované datum.
    ///   - now: Aktuální okamžik pro určení dneška.
    /// - Returns: Text předpony.
    static func dayPrefix(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "dnes") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "zítra")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.defaultDigits).locale(.app))
    }

    /// Den a čas, např. „dnes 14:30“.
    ///
    /// - Parameters:
    ///   - date: Formátované datum.
    ///   - now: Aktuální okamžik pro určení dneška.
    /// - Returns: Předpona dne a čas.
    static func dayAndTime(_ date: Date, now: Date) -> String {
        "\(dayPrefix(date, now: now)) \(time(date))"
    }

    /// Šířka pro `Text(timerInterval:)`, který jinak zabere celý dostupný prostor.
    ///
    /// Odhad pro „9:59“ / „59:59“ / „9:59:59“ / „99:59:59“ podle zbývajícího času.
    ///
    /// - Parameters:
    ///   - remaining: Zbývající čas v sekundách.
    ///   - fontSize: Velikost písma odpočtu.
    /// - Returns: Šířka v bodech zaokrouhlená nahoru.
    static func timerWidth(remaining: TimeInterval, fontSize: CGFloat) -> CGFloat {
        let (digits, colons): (CGFloat, CGFloat) = switch remaining {
        case ..<600: (3, 1)        // 9:59
        case ..<3600: (4, 1)       // 59:59
        case ..<36000: (5, 2)      // 9:59:59
        default: (6, 2)            // 99:59:59
        }
        return ceil(digits * fontSize * 0.62 + colons * fontSize * 0.34 + 2)
    }

    /// SF Symbol podle typu akce („Cvičení“, „Zkouška“…).
    ///
    /// Typ může přijít česky (STAG) i v jazyce aplikace (název typu povinnosti),
    /// proto se hledají české i anglické tvary bez ohledu na velikost písmen a diakritiku.
    ///
    /// - Parameters:
    ///   - typeName: Název typu akce.
    ///   - kind: Druh aktivity (hodina, nebo zkouška).
    /// - Returns: Název SF Symbolu; výchozí je čepice (zkouška) nebo kniha (hodina).
    static func symbol(typeName: String, kind: StudyActivityAttributes.Kind) -> String {
        let type = typeName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
        /// Zjistí, zda normalizovaný typ obsahuje některé z klíčových slov.
        ///
        /// - Parameter keywords: Hledaná klíčová slova bez diakritiky.
        /// - Returns: `true` při alespoň jedné shodě.
        func matches(_ keywords: String...) -> Bool { keywords.contains { type.contains($0) } }
        switch kind {
        case .exam:
            if matches("zapoc", "credit") { return "checkmark.seal.fill" }
            if matches("projekt", "project") { return "hammer.fill" }
            if matches("ukol", "assignment", "task", "homework") { return "doc.text.fill" }
            return "graduationcap.fill"
        case .lesson:
            if matches("predn", "lecture") { return "person.wave.2.fill" }
            if matches("cvic", "exercise", "practical", "tutorial") { return "laptopcomputer" }
            if matches("semin") { return "person.3.fill" }
            if matches("lab") { return "flask.fill" }
            return "book.closed.fill"
        }
    }
}
