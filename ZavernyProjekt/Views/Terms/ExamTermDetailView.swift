import SwiftUI
import SwiftData

/// Detail termínu zkoušky zobrazený jako sheet.
///
/// Zobrazuje hlavičku se štítky stavu, sekce Kdy, Kde a kdo, mapu budovy, obsazenost,
/// přihlašování, zápis/odhlášení ve STAGu, poznámku, údaje o předmětu a tlačítko
/// pro přidání do Kalendáře. Aktuální podobu termínu bere z `ExamTermsViewModel`,
/// zápis provádí přes `examTermRegistrationFlow` vždy až po potvrzení. Otevírá se
/// z `ExamTermsView` klepnutím na kartu nebo řádek termínu.
struct ExamTermDetailView: View {
    /// Termín při otevření – aktuální podobu (po zápisu se mění) bere z ViewModelu.
    private let initialTerm: ExamTerm
    /// Název předmětu z rozvrhu; když chybí, zobrazí se kód předmětu.
    let subjectName: String?
    /// Barva předmětu pro hlavičku a tlačítka.
    let tint: Color
    /// Zda je termín nově vypsaný (zobrazí štítek „Nový“).
    var isNew: Bool
    /// ViewModel termínů pro aktuální data a změny zápisu.
    let viewModel: ExamTermsViewModel

    /// Akce pro zavření sheetu.
    @Environment(\.dismiss) private var dismiss
    /// Zda je otevřený systémový editor události Kalendáře.
    @State private var isAddingToCalendar = false
    /// Akce čekající na potvrzení v dialogu.
    @State private var registrationRequest: ExamTermRegistrationRequest?
    /// Výsledek poslední akce (ukázaný v sekci zápisu).
    @State private var lastOutcome: ExamTermRegistrationOutcome?

    /// Vytvoří detail termínu.
    /// - Parameters:
    ///   - term: Termín při otevření detailu.
    ///   - subjectName: Název předmětu, nebo `nil`.
    ///   - tint: Barva předmětu.
    ///   - isNew: Zda je termín nově vypsaný.
    ///   - viewModel: ViewModel termínů.
    init(term: ExamTerm, subjectName: String?, tint: Color, isNew: Bool = false, viewModel: ExamTermsViewModel) {
        initialTerm = term
        self.subjectName = subjectName
        self.tint = tint
        self.isNew = isNew
        self.viewModel = viewModel
    }

    /// Aktuální podoba termínu ze store / náhledu.
    private var term: ExamTerm { viewModel.latest(initialTerm) }

    /// Seznam sekcí v `NavigationStack`, obnovovaný každou minutu přes `TimelineView`,
    /// s tlačítkem Hotovo, tokem zápisu a sheetem editoru Kalendáře.
    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let now = context.date

                List {
                    Section {
                        header(now: now)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }

                    whenSection(now: now)
                    whereSection
                    if let room = term.room, !room.isEmpty {
                        BuildingMapSection(buildingCode: ExamTermsViewModel.buildingCode(from: room), room: room)
                    }
                    occupancySection
                    registrationSection(now: now)
                    registrationActionSection(now: now)

                    if let note = term.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        Section("Poznámka") {
                            Text(note)
                                .font(.subheadline)
                        }
                    }

                    Section("Předmět") {
                        if let subjectName {
                            LabeledContent("Název", value: subjectName)
                        }
                        LabeledContent("Kód", value: term.subjectCode)
                        if !term.department.isEmpty {
                            LabeledContent("Katedra", value: term.department)
                        }
                        LabeledContent("Typ termínu", value: ExamTermsViewModel.typeText(term))
                    }

                    calendarSection
                }
                .listSectionSpacing(.compact)
            }
            .navigationTitle(term.typeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
            .examTermRegistrationFlow($registrationRequest, viewModel: viewModel, showsSuccessAlert: false) { outcome in
                withAnimation(.snappy) { lastOutcome = outcome }
            }
            .sheet(isPresented: $isAddingToCalendar) {
                CalendarEventEditor(
                    title: calendarTitle,
                    start: term.start,
                    end: term.end,
                    location: term.room,
                    notes: calendarNotes
                )
                .ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hlavička

    /// Hlavička detailu: ikona typu termínu, název předmětu, kód a štítky stavu.
    /// - Parameter now: Aktuální čas (hlavička ho zatím nevyužívá).
    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: ExamTermsViewModel.symbol(for: term))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(subjectName ?? term.subjectCode)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(term.isCancelled)
                HStack(spacing: 6) {
                    TimetableCodeTag(code: term.subjectCode, tint: tint)
                    statusChips
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Štítky stavu termínu: zrušeno / zapsáno / plno, opravný a nový.
    @ViewBuilder
    private var statusChips: some View {
        if term.isCancelled {
            ExamTermChip(text: "Zrušeno", symbol: "xmark.octagon.fill", color: .red)
        } else if term.isRegistered {
            ExamTermChip(text: "Zapsáno", symbol: "checkmark.circle.fill", color: .green)
        } else if term.isFull {
            ExamTermChip(text: "Plno", symbol: "person.fill.xmark", color: .red)
        }
        if term.isRetake {
            ExamTermChip(text: "opravný", color: .purple)
        }
        if isNew {
            ExamTermNewBadge()
        }
    }

    // MARK: - Sekce

    /// Sekce Kdy: datum, čas s délkou a odpočet u nadcházejícího termínu.
    /// - Parameter now: Aktuální čas pro rozhodnutí, zda je termín nadcházející.
    private func whenSection(now: Date) -> some View {
        Section("Kdy") {
            LabeledContent("Datum", value: ExamTermsViewModel.longDayText(term.start))
            LabeledContent("Čas") {
                Text([ExamTermsViewModel.timeText(term), ExamTermsViewModel.durationText(term)].compactMap { $0 }.joined(separator: " · "))
                    .monospacedDigit()
            }
            if term.isUpcoming(now: now) {
                LabeledContent("Zbývá") {
                    ExamTermCountdownChip(term: term, now: now)
                }
            }
        }
    }

    /// Sekce Kde a kdo s místností a zkoušejícím; skrytá, když chybí oba údaje.
    @ViewBuilder
    private var whereSection: some View {
        let room = term.room.flatMap { $0.isEmpty ? nil : $0 }
        let teacher = term.teacher.flatMap { $0.isEmpty ? nil : $0 }
        if room != nil || teacher != nil {
            Section("Kde a kdo") {
                if let room {
                    LabeledContent("Místnost") {
                        Label(room, systemImage: "mappin.and.ellipse")
                            .labelStyle(.compact)
                    }
                }
                if let teacher {
                    LabeledContent("Zkoušející", value: teacher)
                }
            }
        }
    }

    /// Sekce Obsazenost: počet zapsaných, kapacita nebo volná místa a ukazatel zaplnění.
    @ViewBuilder
    private var occupancySection: some View {
        if ExamTermsViewModel.occupancyText(term) != nil {
            Section("Obsazenost") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        if let occupied = term.occupied {
                            Text(verbatim: "\(occupied)")
                                .font(.title2.bold())
                                .monospacedDigit()
                            Group {
                                if let capacity = term.capacity {
                                    Text("z \(capacity) míst", comment: "Pod počtem zapsaných: z kolika míst")
                                } else {
                                    Text(Self.registeredLabel(occupied))
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let free = term.freeSpots {
                            Text(term.isFull ? String(localized: "Plno") : String(localized: "volno \(free)", comment: "Počet volných míst na termínu"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ExamTermsViewModel.occupancyColor(term))
                        }
                    }
                    if let fraction = ExamTermsViewModel.occupancyFraction(term) {
                        ProgressView(value: fraction)
                            .tint(ExamTermsViewModel.occupancyColor(term))
                            .accessibilityLabel("Zaplněnost termínu")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Sekce Přihlašování s daty otevření, uzávěrky přihlášení a odhlášení a důvodem blokace.
    /// - Parameter now: Aktuální čas pro zvýraznění blížící se uzávěrky a text stavu v patičce.
    @ViewBuilder
    private func registrationSection(now: Date) -> some View {
        let hasDates = term.registrationOpens != nil || term.registrationDeadline != nil || term.unregisterDeadline != nil
        let reason = ExamTermsViewModel.blockReasonText(term)
        if hasDates || reason != nil {
            Section {
                if let opens = term.registrationOpens {
                    LabeledContent("Přihlašování od", value: opens.deadlineFormatted)
                }
                if let deadline = term.registrationDeadline {
                    LabeledContent("Přihlásit se do") {
                        Text(deadline.deadlineFormatted)
                            .foregroundStyle(ExamTermsViewModel.isRegistrationClosingSoon(term, now: now) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    }
                }
                if let unregister = term.unregisterDeadline {
                    LabeledContent("Odhlásit se do", value: unregister.deadlineFormatted)
                }
                if let reason {
                    Label(reason, systemImage: "info.circle")
                        .labelStyle(.compact(spacing: 8))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Přihlašování")
            } footer: {
                if let status = ExamTermsViewModel.registrationText(term, now: now), !term.isRegistered {
                    Text(status)
                }
            }
        }
    }

    /// Zápis / odhlášení / fronta přímo ve STAGu (vždy přes potvrzovací dialog).
    ///
    /// Během probíhající změny ukazuje průběh, jinak tlačítko akce a pod ním výsledek poslední změny.
    /// - Parameter now: Aktuální čas pro určení dostupné akce a textů v patičce.
    @ViewBuilder
    private func registrationActionSection(now: Date) -> some View {
        if let action = viewModel.registrationAction(for: term, now: now) {
            let enabled = ExamTermsViewModel.isRegistrationActionEnabled(action, term: term)
            let pending = viewModel.pendingRegistration
            Section {
                if let pending, pending.termID == term.id {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(pending.action.progressText)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityElement(children: .combine)
                } else {
                    Button(role: action.isDestructive ? .destructive : nil) {
                        lastOutcome = nil
                        registrationRequest = ExamTermRegistrationRequest(term: term, action: action, subjectName: subjectName)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(action.isDestructive ? .red : tint)
                    .disabled(!enabled || pending != nil)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let lastOutcome, lastOutcome.termID == term.id {
                    Label(lastOutcome.message, systemImage: lastOutcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .labelStyle(.compact(spacing: 8))
                        .font(.subheadline)
                        .foregroundStyle(lastOutcome.isSuccess ? Color.green : Color.red)
                        .transition(.opacity)
                }
            } header: {
                Text("Zápis ve STAGu")
            } footer: {
                registrationActionFooter(action, enabled: enabled, now: now)
            }
        }
    }

    /// Patička sekce zápisu: proč akce nejde (důvod ze STAGu a termíny přihlašování/odhlašování),
    /// jinak upozornění na ostrou změnu ve STAGu.
    /// - Parameters:
    ///   - action: Nabízená akce zápisu.
    ///   - enabled: Zda STAG akci aktuálně dovoluje.
    ///   - now: Aktuální čas pro texty termínů.
    /// - Returns: Text s řádky patičky.
    private func registrationActionFooter(_ action: StagTermRegistrationAction, enabled: Bool, now: Date) -> some View {
        var lines: [String] = []
        if enabled {
            lines.append(String(localized: "Změna proběhne přímo v IS/STAG – před provedením ji ještě potvrdíš."))
            if action == .register, let unregister = ExamTermsViewModel.unregisterText(term, now: now) { lines.append(unregister) }
        } else {
            lines.append(ExamTermsViewModel.blockReasonText(term) ?? String(localized: "STAG teď změnu zápisu nedovoluje."))
            if let registration = ExamTermsViewModel.registrationText(term, now: now) { lines.append(registration) }
            if let unregister = ExamTermsViewModel.unregisterText(term, now: now) { lines.append(unregister) }
        }
        return Text(lines.joined(separator: "\n"))
    }

    /// Sekce s tlačítkem pro přidání termínu do systémového Kalendáře.
    private var calendarSection: some View {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Událost uložíš v systémovém Kalendáři – aplikace k němu nepotřebuje přístup.")
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Texty

    /// Název události v Kalendáři, např. „Zkouška AP9PT: Pokročilé mobilní technologie (opravný)“.
    private var calendarTitle: String {
        var title = "\(term.typeName) \(term.subjectCode)"
        if let subjectName { title += ": \(subjectName)" }
        if term.isRetake { title = String(localized: "\(title) (opravný)", comment: "Název události v Kalendáři u opravného termínu") }
        return title
    }

    /// Poznámka události v Kalendáři: místnost, zkoušející, poznámka a zdroj.
    private var calendarNotes: String {
        var lines: [String] = []
        if let room = term.room, !room.isEmpty { lines.append(String(localized: "Místnost: \(room)")) }
        if let teacher = term.teacher, !teacher.isEmpty { lines.append(String(localized: "Zkoušející: \(teacher)")) }
        if let note = term.note, !note.isEmpty { lines.append(note) }
        lines.append(String(localized: "Termín z IS/STAG – Termínovník"))
        return lines.joined(separator: "\n")
    }

    /// Popisek pod velkým číslem, když kapacita není známá: „zapsaný“, „zapsaní“, „zapsaných“.
    ///
    /// Číslo je zobrazené zvlášť, proto tvary bez čísla (v angličtině všechny „registered“).
    /// - Parameter count: Počet zapsaných studentů.
    /// - Returns: Lokalizovaný popisek ve správném tvaru.
    private static func registeredLabel(_ count: Int) -> String {
        switch count {
        case 1: String(localized: "zapsaný", comment: "Popisek pod počtem 1 zapsaného studenta")
        case 2...4: String(localized: "zapsaní", comment: "Popisek pod počtem 2–4 zapsaných studentů")
        default: String(localized: "zapsaných", comment: "Popisek pod počtem 0 nebo 5+ zapsaných studentů")
        }
    }
}

#Preview("Zapsaný") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExamTermDetailView(term: ExamTerm.samples[0], subjectName: "Pokročilé mobilní technologie", tint: Color(hex: "#3E63DD"),
                               viewModel: ExamTermsViewModel(previewTerms: ExamTerm.samples))
        }
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}

#Preview("Vypsaný – zapsat se") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExamTermDetailView(term: ExamTerm.samples[1], subjectName: "Pokročilé mobilní technologie", tint: Color(hex: "#3E63DD"),
                               viewModel: ExamTermsViewModel(previewTerms: ExamTerm.samples))
        }
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}

#Preview("Vypsaný – plno") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExamTermDetailView(term: ExamTerm.samples[2], subjectName: "Evoluční výpočetní techniky", tint: Color(hex: "#B8860B"), isNew: true,
                               viewModel: ExamTermsViewModel(previewTerms: ExamTerm.samples))
        }
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
        .preferredColorScheme(.dark)
}
