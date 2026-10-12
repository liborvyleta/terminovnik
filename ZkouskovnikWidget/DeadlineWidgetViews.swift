import AppIntents
import SwiftUI
import WidgetKit

// Pohledy jednotlivých rodin widgetu. Žádný z nich nečte `widgetFamily` –
// výběr dělá jen `DeadlineWidgetView`, takže je lze vykreslit i samostatně.

/// Kořenový pohled widgetu „Nejbližší deadliny“.
///
/// Podle aktuální rodiny (`widgetFamily`) vybere konkrétní rozvržení a doplní pozadí
/// kontejneru. `.systemExtraLarge` sdílí rozvržení s velkým widgetem, neznámé rodiny malé.
struct DeadlineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// Záznam časové osy, který se má zobrazit.
    let entry: DeadlineEntry

    /// Obsah pohledu `DeadlineWidgetView` sestavený z jeho vstupních hodnot.
    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    /// Rozvržení odpovídající aktuální rodině widgetu.
    ///
    /// - Returns: Pohled pro danou rodinu.
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

    /// Pozadí kontejneru widgetu: průhledné pro widgety zamčené obrazovky, jinak systémové pozadí.
    ///
    /// - Returns: Pohled pozadí pro `containerBackground(for:)`.
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

/// Malý widget s nejbližším deadlinem.
///
/// Zobrazí štítek předmětu, ikonu naléhavosti, přepínač splnění, typ, název, velký barevný
/// odpočet a datum. Bez deadlinů ukáže kompaktní prázdný stav.
struct SmallDeadlineView: View {
    let entry: DeadlineEntry

    /// Obsah pohledu `SmallDeadlineView` sestavený z jeho vstupních hodnot.
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
                    WidgetCompleteToggle(deadline: deadline, font: .title3)
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
                    // Během zpracování „Označit jako splněné“ systém obsah zneplatní (shimmer).
                    .invalidatableContent()

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

/// Střední widget s hlavičkou a 3 nejbližšími deadliny.
///
/// Rozvržení obstarává `WidgetDeadlineList`.
struct MediumDeadlineView: View {
    let entry: DeadlineEntry

    /// Obsah pohledu `MediumDeadlineView` sestavený z jeho vstupních hodnot.
    var body: some View {
        WidgetDeadlineList(entry: entry, maxRows: 3, isLarge: false)
    }
}

/// Velký widget s hlavičkou a 6 nejbližšími deadliny.
///
/// Rozvržení obstarává `WidgetDeadlineList`; řádky navíc ukazují datum a oddělovače.
struct LargeDeadlineView: View {
    let entry: DeadlineEntry

    /// Obsah pohledu `LargeDeadlineView` sestavený z jeho vstupních hodnot.
    var body: some View {
        WidgetDeadlineList(entry: entry, maxRows: 6, isLarge: true)
    }
}

/// Společné rozvržení seznamu pro střední a velký widget.
///
/// Zobrazí hlavičku s počtem a nejvýše `maxRows` řádků, případně prázdný stav.
struct WidgetDeadlineList: View {
    let entry: DeadlineEntry
    /// Maximální počet zobrazených řádků.
    let maxRows: Int
    /// Zda jde o velkou variantu (větší písmo, rozestupy a oddělovače).
    let isLarge: Bool

    /// Obsah pohledu `WidgetDeadlineList` sestavený z jeho vstupních hodnot.
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

/// Hlavička seznamu „Nejbližší deadliny“ s počtem.
///
/// Počet se zobrazí v kapsli barvy značky, jen pokud je větší než nula.
struct WidgetListHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Celkový počet nesplněných deadlinů.
    let count: Int
    /// Zda použít větší písmo velkého widgetu.
    let isLarge: Bool

    /// Obsah pohledu `WidgetListHeader` sestavený z jeho vstupních hodnot.
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

/// Řádek seznamu deadlinů.
///
/// Obsahuje přepínač splnění, název, „kód · typ“, odpočet vpravo (ve velké variantě i datum)
/// a barevný proužek předmětu na levém okraji.
struct WidgetDeadlineRow: View {
    /// Zobrazovaný deadline.
    let deadline: WidgetDeadline
    /// Okamžik, vůči kterému se počítá odpočet a naléhavost.
    let now: Date
    /// Zda použít variantu velkého widgetu.
    let isLarge: Bool

    /// Obsah pohledu `WidgetDeadlineRow` sestavený z jeho vstupních hodnot.
    var body: some View {
        let urgency = DeadlineUrgency(dueDate: deadline.dueDate, now: now)

        HStack(alignment: .center, spacing: 8) {
            WidgetCompleteToggle(deadline: deadline, font: isLarge ? .title3 : .body)

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
        .invalidatableContent()
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color(hex: deadline.hexColor))
                .frame(width: 4)
        }
    }
}

// MARK: - Zamčená obrazovka

/// Obdélníkový widget zamčené obrazovky.
///
/// Ukáže „KÓD · odpočet“, název a datum nejbližšího deadlinu, nebo stav „Vše hotovo“.
struct RectangularDeadlineView: View {
    let entry: DeadlineEntry

    /// Obsah pohledu `RectangularDeadlineView` sestavený z jeho vstupních hodnot.
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

/// Kruhový widget zamčené obrazovky.
///
/// Ukáže kód předmětu a počet kalendářních dní do nejbližšího deadlinu, „Dnes“ s časem,
/// nebo „Prošlo“ u deadlinu po termínu; bez deadlinů „Hotovo“.
struct CircularDeadlineView: View {
    let entry: DeadlineEntry

    /// Obsah pohledu `CircularDeadlineView` sestavený z jeho vstupních hodnot.
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content
                .widgetAccentable()
                .padding(4)
        }
    }

    /// Obsah kruhu podle stavu nejbližšího deadlinu.
    ///
    /// - Returns: Pohled s kódem a odpočtem, nebo prázdný stav.
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
    ///
    /// Vezme lokalizovanou frázi „%lld dní“ (plurálové varianty v katalogu) a odebere z ní číslo,
    /// takže stačí jeden klíč s počtem místo samostatného slova bez kontextu.
    ///
    /// - Parameter days: Počet dní, podle kterého se volí plurálový tvar.
    /// - Returns: Jednotka bez čísla; když číslo ve frázi nenajde, celá fráze.
    private static func dayUnit(_ days: Int) -> String {
        let phrase = String(localized: "\(days) dní", comment: "Počet dní, např. „5 dní“ (plurál)")
        guard let range = phrase.range(of: String(days)) else { return phrase }
        var unit = phrase
        unit.removeSubrange(range)
        return unit.trimmingCharacters(in: .whitespaces)
    }
}

/// Řádkový widget zamčené obrazovky, např. „AP9PT: Zítra · Zápočtový test“.
///
/// Bez deadlinů zobrazí „Vše hotovo – žádné deadliny“.
struct InlineDeadlineView: View {
    let entry: DeadlineEntry

    /// Obsah pohledu `InlineDeadlineView` sestavený z jeho vstupních hodnot.
    var body: some View {
        if let deadline = entry.nearest {
            Text("\(deadline.subjectCode): \(Countdown.text(for: deadline.dueDate, now: entry.date)) · \(deadline.title)")
        } else {
            Text("Vše hotovo – žádné deadliny")
        }
    }
}

// MARK: - Sdílené prvky

/// Kroužek u deadlinu – klepnutí ho označí jako splněný bez otevření aplikace (iOS 17).
///
/// `Toggle(isOn:intent:)` systém po klepnutí okamžitě překreslí do opačného stavu (kroužek → fajfka),
/// zatímco `CompleteDeadlineIntent` běží v aplikaci. Ta pak přepíše přehled a deadline z widgetu zmizí.
struct WidgetCompleteToggle: View {
    /// Deadline, který přepínač označí jako splněný.
    let deadline: WidgetDeadline
    /// Písmo určující velikost ikony; výchozí je `.body`.
    var font: Font = .body

    /// Obsah pohledu `WidgetCompleteToggle` sestavený z jeho vstupních hodnot.
    var body: some View {
        // Widget ukazuje jen nesplněné deadliny → výchozí stav je vždy „nesplněno“.
        Toggle(isOn: false, intent: CompleteDeadlineIntent(deadlineID: deadline.id)) {
            Text("Označit jako splněné")
        }
        .toggleStyle(WidgetCheckToggleStyle(font: font))
        .accessibilityLabel(Text("Označit jako splněné"))
        .accessibilityValue(Text(deadline.title))
    }
}

/// Vzhled přepínače splnění.
///
/// Prázdný kroužek, v zapnutém stavu zelená fajfka s animací nahrazení symbolu.
struct WidgetCheckToggleStyle: ToggleStyle {
    /// Písmo určující velikost ikony.
    let font: Font

    /// Vykreslí přepínač jako ikonu kroužku nebo fajfky.
    ///
    /// - Parameter configuration: Konfigurace přepínače se stavem `isOn`.
    /// - Returns: Ikona s minimální plochou pro klepnutí 24 × 24 bodů.
    func makeBody(configuration: Configuration) -> some View {
        Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
            .font(font)
            .foregroundStyle(configuration.isOn ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
            .contentTransition(.symbolEffect(.replace))
            .widgetAccentable()
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
    }
}

/// Štítek předmětu.
///
/// Kapsle v barvě předmětu s bílým tučným kódem.
struct WidgetSubjectBadge: View {
    /// Kód předmětu, např. „AP9PT“.
    let code: String
    /// Barva předmětu v hexadecimálním zápisu.
    let hexColor: String

    /// Obsah pohledu `WidgetSubjectBadge` sestavený z jeho vstupních hodnot.
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
///
/// Zelená pečeť s textem „Vše hotovo“ a „Žádné nadcházející deadliny“.
struct WidgetEmptyState: View {
    /// Zda použít menší variantu pro malé a střední widgety.
    let compact: Bool

    /// Obsah pohledu `WidgetEmptyState` sestavený z jeho vstupních hodnot.
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

/// Barva značky Termínovníku.
///
/// Indigo, v tmavém režimu světlejší odstín.
enum WidgetBrand {
    /// Barva značky pro světlý režim.
    static let light = Color(hex: "#4F46E5")
    /// Barva značky pro tmavý režim.
    static let dark = Color(hex: "#818CF8")

    /// Vrátí barvu značky pro zadaný barevný režim.
    ///
    /// - Parameter scheme: Aktuální barevný režim.
    /// - Returns: `dark` v tmavém režimu, jinak `light`.
    static func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}
