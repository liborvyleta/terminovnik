import SwiftUI

/// Detail rozvrhové akce (sheet): kdy, kde, kdo a přidání do Kalendáře.
struct TimetableEventDetailView: View {
    let selection: TimetableSelection
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingToCalendar = false
    /// Hodina se sleduje jako Live Activity na zamčené obrazovce
    @State private var isTracking = false
    /// Spuštění selhalo (typicky vypnuté Živé aktivity v Nastavení iOS)
    @State private var trackingFailed = false

    private var event: TimetableEvent { selection.event }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                whenSection
                whereSection

                if let teacher = event.teacher, !teacher.isEmpty {
                    Section("Vyučující") {
                        Label(teacher, systemImage: "person.fill")
                            .labelStyle(.compact(spacing: 10))
                    }
                }

                Section("Předmět") {
                    LabeledContent("Kód", value: event.subjectCode)
                    if !event.department.isEmpty {
                        LabeledContent("Katedra", value: event.department)
                    }
                    LabeledContent("Typ akce", value: event.typeName)
                }

                if let occurrence = selection.occurrence {
                    Section {
                        Button {
                            isAddingToCalendar = true
                        } label: {
                            Label("Přidat do Kalendáře", systemImage: "calendar.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(tint)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text("Předvyplníme \(occurrence.start.deadlineLongFormatted). Událost uložíš v systémovém Kalendáři – aplikace k němu nepotřebuje přístup.")
                    }

                    if LiveActivityManager.shared.canStartLesson(occurrence) {
                        liveActivitySection(occurrence)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle(event.typeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingToCalendar) {
                if let occurrence = selection.occurrence {
                    CalendarEventEditor(
                        title: "\(event.typeName) \(event.subjectCode): \(event.subjectName)",
                        start: occurrence.start,
                        end: occurrence.end,
                        location: event.locationText,
                        notes: calendarNotes
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: TimetableViewModel.symbol(for: event))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.subjectName)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TimetableCodeTag(code: event.subjectCode, tint: tint)
                    if let occurrence = selection.occurrence {
                        Label(TimetableViewModel.timeRange(of: occurrence), systemImage: "clock")
                            .labelStyle(.compact)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Sekce

    /// Tlačítko pro sledování hodiny jako Live Activity (zamčená obrazovka, Dynamic Island)
    private func liveActivitySection(_ occurrence: TimetableOccurrence) -> some View {
        Section {
            Button {
                if LiveActivityManager.shared.startLesson(occurrence) {
                    withAnimation(.snappy) { isTracking = true }
                    trackingFailed = false
                } else {
                    trackingFailed = true
                }
            } label: {
                Label(
                    isTracking ? "Sleduje se na zamčené obrazovce" : "Sledovat na zamčené obrazovce",
                    systemImage: isTracking ? "checkmark.circle.fill" : "livephoto"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(tint)
            .disabled(isTracking)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .sensoryFeedback(.success, trigger: isTracking) { _, new in new }
        } footer: {
            if trackingFailed {
                Text("Živé aktivity se nepodařilo spustit. Zkontroluj, že je máš povolené v Nastavení iOS → Termínovník.")
            } else {
                Text("Odpočet do začátku a místnost uvidíš na zamčené obrazovce i v Dynamic Islandu.")
            }
        }
        .onAppear { isTracking = LiveActivityManager.shared.isTracking(occurrence) }
    }

    private var whenSection: some View {
        Section("Kdy") {
            if let occurrence = selection.occurrence {
                LabeledContent("Datum", value: Self.capitalized(occurrence.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))))
                LabeledContent("Čas") {
                    Text("\(TimetableViewModel.timeRange(of: occurrence)) · \(durationText(occurrence))")
                        .monospacedDigit()
                }
            } else {
                LabeledContent("Termín", value: String(localized: "Bez pevného termínu"))
                if let start = event.startTime, let end = event.endTime {
                    LabeledContent("Čas", value: "\(start)–\(end)")
                }
            }
            if let repetitionText {
                LabeledContent("Opakování", value: repetitionText)
            }
            if let validity = validityText {
                LabeledContent("Platnost", value: validity)
            }
        }
    }

    /// S budovou: název, adresa, mapa a navigace; bez budovy jen místnost
    @ViewBuilder
    private var whereSection: some View {
        if let building = event.building, !building.isEmpty {
            BuildingMapSection(buildingCode: building, room: event.room)
                .tint(tint)
        } else if let location = event.locationText {
            Section("Kde") {
                LabeledContent("Místnost", value: location)
            }
        }
    }

    // MARK: - Texty

    /// Jak často se akce koná; u akcí bez pevného dne nic
    private var repetitionText: String? {
        if event.singleDate != nil { return String(localized: "Jednorázově") }
        guard event.weekday != nil else { return nil }
        switch event.weekParity {
        case "Sudý": return String(localized: "Sudý týden")
        case "Lichý": return String(localized: "Lichý týden")
        case "Jiný": return String(localized: "Nepravidelně")
        default: return String(localized: "Každý týden")
        }
    }

    /// „21. 9. 2026 – 18. 12. 2026“
    private var validityText: String? {
        let style = Date.FormatStyle.dateTime.day().month(.defaultDigits).year().locale(.czech)
        switch (event.dateFrom, event.dateTo) {
        case let (from?, to?): return "\(from.formatted(style)) – \(to.formatted(style))"
        case let (from?, nil): return String(localized: "od \(from.formatted(style))", comment: "Platnost akce od data")
        case let (nil, to?): return String(localized: "do \(to.formatted(style))", comment: "Platnost akce do data")
        default: return nil
        }
    }

    private func durationText(_ occurrence: TimetableOccurrence) -> String {
        let minutes = Int(occurrence.end.timeIntervalSince(occurrence.start) / 60)
        return TimetableViewModel.durationText(minutes: minutes)
    }

    /// Poznámka události v Kalendáři: místnost, vyučující, zdroj
    private var calendarNotes: String {
        var lines: [String] = []
        if let location = event.locationText { lines.append(String(localized: "Místnost: \(location)")) }
        if let teacher = event.teacher, !teacher.isEmpty { lines.append(String(localized: "Vyučující: \(teacher)")) }
        lines.append(String(localized: "Z rozvrhu IS/STAG – Termínovník"))
        return lines.joined(separator: "\n")
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

#Preview {
    let snapshot = TimetableSnapshot.sample
    let event = snapshot.events[1]
    let occurrence = event.occurrence(on: .now)
        ?? TimetableOccurrence(event: event, start: .now, end: .now.addingTimeInterval(7_200))
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            TimetableEventDetailView(
                selection: TimetableSelection(event: event, occurrence: occurrence),
                tint: Color(hex: event.hexColor ?? "#3E63DD")
            )
        }
}
