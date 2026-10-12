import SwiftUI

/// Stránka s nejbližšími nesplněnými deadliny.
///
/// Zobrazuje deadliny, které ``WatchStore`` dekódoval z kontextu přijatého z iPhonu přes
/// WatchConnectivity, s odpočtem a barvou naléhavosti přepočítávanými každou minutu.
/// Klepnutím na řádek se otevře detail deadlinu.
struct DeadlinesView: View {
    /// Zdroj dat přijatých z iPhonu.
    let store: WatchStore

    /// Seznam deadlinů, nebo prázdný stav „Vše hotovo“, když žádný deadline není.
    var body: some View {
        TimelineView(.everyMinute) { context in
            if store.deadlines.isEmpty {
                ContentUnavailableView {
                    Label("Vše hotovo", systemImage: "checkmark.circle")
                } description: {
                    Text("Nemáš žádné nesplněné deadliny.")
                }
            } else {
                List(store.deadlines) { deadline in
                    NavigationLink {
                        DeadlineDetailView(deadline: deadline)
                    } label: {
                        DeadlineRow(deadline: deadline, now: context.date)
                    }
                }
            }
        }
    }
}

/// Řádek seznamu deadlinů.
///
/// Zobrazuje odpočet v barvě naléhavosti, název deadlinu a zkratku předmětu s typem;
/// pro VoiceOver tvoří jediný prvek.
struct DeadlineRow: View {
    /// Zobrazovaný deadline.
    let deadline: WidgetDeadline
    /// Aktuální čas, ke kterému se počítá odpočet a naléhavost.
    let now: Date

    /// Obsah řádku.
    var body: some View {
        let urgency = DeadlineUrgency(dueDate: deadline.dueDate, now: now)
        VStack(alignment: .leading, spacing: 2) {
            Label(Countdown.text(for: deadline.dueDate, now: now), systemImage: urgency.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(urgency.color)
            Text(deadline.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: deadline.hexColor))
                    .frame(width: 6, height: 6)
                Text(verbatim: deadline.subjectCode.isEmpty ? deadline.typeTitle : "\(deadline.subjectCode) · \(deadline.typeTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Detail jednoho deadlinu.
///
/// Zobrazuje typ, název, předmět, přesný termín a odpočet; během posledních 24 hodin
/// přidá odpočet po sekundách. Pozadí má barvu naléhavosti.
struct DeadlineDetailView: View {
    /// Zobrazovaný deadline.
    let deadline: WidgetDeadline

    /// Obsah detailu, přepočítávaný každou minutu.
    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let urgency = DeadlineUrgency(dueDate: deadline.dueDate, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Label(deadline.typeTitle, systemImage: deadline.typeSymbol)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: deadline.hexColor))

                    Text(deadline.title)
                        .font(.headline)

                    if !deadline.subjectName.isEmpty {
                        Text(deadline.subjectName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text(deadline.dueDate.deadlineLongFormatted)
                        .font(.footnote)

                    Label(Countdown.text(for: deadline.dueDate, now: now), systemImage: urgency.symbol)
                        .foregroundStyle(urgency.color)
                        .font(.footnote.weight(.semibold))

                    // Posledních 24 hodin odpočítáváme po sekundách
                    if deadline.dueDate > now, deadline.dueDate.timeIntervalSince(now) < 24 * 3600 {
                        Text(timerInterval: now...deadline.dueDate, countsDown: true)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(urgency.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .containerBackground(urgency.color.gradient, for: .navigation)
        }
        .navigationTitle(deadline.subjectCode.isEmpty ? deadline.typeTitle : deadline.subjectCode)
    }
}

// MARK: - Ukázková data

extension WidgetDeadline {
    /// Ukázkové deadliny pro náhledy a ukázkový režim.
    ///
    /// Obsahuje čtyři deadliny s různou mírou naléhavosti včetně jednoho, který už uplynul;
    /// termíny jsou relativní k okamžiku volání.
    static var watchSamples: [WidgetDeadline] {
        let now = Date.now
        func deadline(_ title: String, _ code: String, _ name: String, _ color: String,
                      _ type: String, _ symbol: String, hours: Double) -> WidgetDeadline {
            WidgetDeadline(id: UUID(), title: title, subjectCode: code, subjectName: name, hexColor: color,
                           typeTitle: type, typeSymbol: symbol, dueDate: now.addingTimeInterval(hours * 3600))
        }
        return [
            deadline("Odevzdat semestrální projekt", "AP9PT", "Pokročilé mobilní technologie", "#3E63DD", "Projekt", "hammer.fill", hours: 5),
            deadline("Test z clusterování", "AP9DM", "Datamining", "#12A594", "Test", "pencil.and.list.clipboard", hours: 50),
            deadline("Zkouška", "AP9EV", "Evoluční výpočetní techniky", "#B8860B", "Zkouška", "graduationcap.fill", hours: 24 * 9),
            deadline("Prezentace bezpečnostní analýzy", "AP9BI", "Bezpečnost informačních systémů", "#E5484D", "Prezentace", "person.wave.2.fill", hours: -20)
        ]
    }
}

#Preview("Deadliny") {
    NavigationStack {
        DeadlinesView(store: WatchStore(timetable: nil, deadlines: WidgetDeadline.watchSamples))
    }
}

#Preview("Detail deadlinu") {
    NavigationStack {
        DeadlineDetailView(deadline: WidgetDeadline.watchSamples[0])
    }
}
