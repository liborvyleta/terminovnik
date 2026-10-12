import SwiftUI
import SwiftData

/// Záložka Rozvrh – výuka po dnech z IS/STAG.
///
/// Nahoře výběr dne v týdnu, pod ním karta „Teď probíhá / Další hodina“, časová osa
/// zvoleného dne a akce bez pevného termínu; alternativně týdenní mřížka. Data čte
/// z `TimetableViewModel` (nad `TimetableStore.shared`), barvy akcí bere živě
/// z předmětů přes `@Query`. Uživatel přepíná den / týden, vrací se na dnešek,
/// obnovuje rozvrh (tlačítko i tažení dolů), přihlašuje se do STAGu a klepnutím
/// na akci otevírá její detail. Používá se jako jedna ze záložek hlavního `TabView`.
struct TimetableView: View {
    /// Kontext SwiftData předávaný view modelu při obnovení rozvrhu.
    @Environment(\.modelContext) private var modelContext
    /// Předměty – kvůli barvám akcí (změna barvy předmětu se hned projeví i v rozvrhu).
    @Query private var subjects: [Subject]

    /// View model rozvrhu (stav obrazovky, vybraný den, výskyty akcí).
    @State private var viewModel: TimetableViewModel
    /// Vybraná akce, jejíž detail se zobrazuje v sheetu.
    @State private var selection: TimetableSelection?
    /// Zda je zobrazen sheet s přihlášením do IS/STAG.
    @State private var isShowingLogin = false

    /// Ostrý režim – data z `TimetableStore.shared`.
    init() {
        _viewModel = State(initialValue: TimetableViewModel())
    }

    /// Vstříknutý ViewModel – pro náhledy a snímky obrazovky (`TimetableViewModel(previewSnapshot:)`).
    /// - Parameter viewModel: Připravený view model rozvrhu.
    init(viewModel: TimetableViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    /// Zvolený pohled (den / týden) – aplikace si ho pamatuje.
    @AppStorage("timetableDisplayMode") private var displayMode: TimetableDisplayMode = .day

    /// Obsah podle stavu v `NavigationStack` se sheety detailu a přihlášení a automatickým načtením.
    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Rozvrh")
                // Pruh dnů je připnutý nahoře, velký nadpis by se s ním překrýval
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(item: $selection) { selection in
                    TimetableEventDetailView(selection: selection, tint: tint(for: selection.event))
                }
                .sheet(isPresented: $isShowingLogin) { StagImportView() }
                // Spustí se při otevření i hned po přihlášení do STAGu
                .task(id: viewModel.isConnected) {
                    await viewModel.refreshIfNeeded(context: modelContext)
                }
                .sensoryFeedback(.selection, trigger: viewModel.selectedDay)
        }
    }

    // MARK: - Stavy

    /// Obsah podle stavu obrazovky: nepřihlášeno, načítání, chyba, prázdný rozvrh nebo rozvrh.
    @ViewBuilder
    private var content: some View {
        switch viewModel.screenState {
        case .notConnected(let message):
            centered {
                EmptyStateView(
                    symbol: "calendar.day.timeline.left",
                    title: String(localized: "Tvůj rozvrh na jednom místě"),
                    message: message ?? String(localized: "Přihlas se do IS/STAG a uvidíš své přednášky, cvičení a semináře po dnech – i s místnostmi, vyučujícími a odpočtem do další hodiny."),
                    tint: .indigo,
                    actionTitle: String(localized: "Přihlásit se do IS/STAG"),
                    actionSymbol: "person.crop.circle.badge.checkmark",
                    action: { isShowingLogin = true }
                )
            }

        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Načítám rozvrh ze STAGu…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            centered {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "Rozvrh se nepodařilo načíst"),
                    message: message,
                    tint: .orange,
                    actionTitle: String(localized: "Zkusit znovu"),
                    actionSymbol: "arrow.clockwise",
                    action: refresh
                )
            }

        case .empty:
            centered {
                EmptyStateView(
                    symbol: "calendar.badge.checkmark",
                    title: String(localized: "Rozvrh je prázdný"),
                    message: String(localized: "Na tento semestr nemáš ve STAGu žádné rozvrhové akce. Až si je zapíšeš, objeví se tady."),
                    tint: .teal,
                    actionTitle: String(localized: "Obnovit"),
                    actionSymbol: "arrow.clockwise",
                    action: refresh
                )
            }

        case .ready:
            timetable
        }
    }

    /// Prázdný stav vystředěný ve scrollovatelné ploše (funguje i tažení dolů pro obnovení).
    /// - Parameter content: Obsah, který se vystředí.
    /// - Returns: `ScrollView` s obnovením tažením dolů.
    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .containerRelativeFrame(.vertical)
        }
        .refreshable { await viewModel.refresh(context: modelContext) }
    }

    // MARK: - Rozvrh

    /// Denní nebo týdenní rozvrh podle zvoleného režimu.
    @ViewBuilder
    private var timetable: some View {
        switch displayMode {
        case .day: dayTimetable
        case .week: weekTimetable
        }
    }

    // MARK: - Týden

    /// Klasická týdenní mřížka – sloupce dnů, bloky podle času.
    ///
    /// Překresluje se každou minutu; nahoře je pás týdne bez dlaždic dnů.
    private var weekTimetable: some View {
        let colors = subjectColors

        return TimelineView(.everyMinute) { context in
            let now = context.date
            let footer = viewModel.footerText(now: now)

            ScrollView {
                VStack(spacing: 12) {
                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    TimetableWeekGridView(
                        days: viewModel.weekDays.map(\.date),
                        occurrences: { viewModel.occurrences(on: $0) },
                        now: now,
                        color: { tint(for: $0, colors: colors) },
                        onSelect: { occurrence in
                            selection = TimetableSelection(event: occurrence.event, occurrence: occurrence)
                        }
                    )

                    if !viewModel.unscheduledEvents.isEmpty {
                        Text("\(viewModel.unscheduledEvents.count) akcí bez pevného termínu najdeš v denním pohledu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let footer { footerLabel(footer) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .refreshable { await viewModel.refresh(context: modelContext) }
            .safeAreaInset(edge: .top, spacing: 0) {
                TimetableWeekStrip(viewModel: viewModel, now: now, showsDays: false) { tint(for: $0, colors: colors) }
            }
        }
    }

    // MARK: - Den

    /// Denní rozvrh: karta nejbližší hodiny, časová osa nebo volný den a akce bez termínu.
    ///
    /// Překresluje se každou minutu; nahoře je připnutý výběr dne.
    private var dayTimetable: some View {
        let colors = subjectColors

        // Překreslení každou minutu: odpočet, zvýraznění probíhající hodiny, „aktualizováno před…“
        return TimelineView(.everyMinute) { context in
            let now = context.date
            let occurrences = viewModel.selectedOccurrences
            let unscheduled = viewModel.unscheduledEvents
            let footer = viewModel.footerText(now: now)

            List {
                if let errorMessage = viewModel.errorMessage {
                    Section { errorBanner(errorMessage) }
                }

                if let highlighted = viewModel.highlightedOccurrence(now: now) {
                    Section {
                        Button {
                            selection = TimetableSelection(event: highlighted.event, occurrence: highlighted)
                        } label: {
                            TimetableNowCard(occurrence: highlighted, now: now, tint: tint(for: highlighted.event, colors: colors))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if occurrences.isEmpty {
                        TimetableFreeDayView(
                            isWeekend: TimetableEvent.weekday(of: viewModel.selectedDay) >= 6,
                            nextLessonText: viewModel.nextLessonDay.map {
                                $0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))
                            }
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        TimetableDayTimelineView(
                            occurrences: occurrences,
                            now: now,
                            isToday: viewModel.isToday(viewModel.selectedDay, now: now),
                            color: { tint(for: $0, colors: colors) },
                            onSelect: { occurrence in
                                selection = TimetableSelection(event: occurrence.event, occurrence: occurrence)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 12))
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                } header: {
                    HStack {
                        Text(viewModel.dayTitle(now: now))
                        Spacer()
                        if !occurrences.isEmpty {
                            Text(viewModel.lessonCountText)
                        }
                    }
                } footer: {
                    if unscheduled.isEmpty, let footer {
                        footerLabel(footer)
                    }
                }

                if !unscheduled.isEmpty {
                    Section {
                        ForEach(unscheduled) { event in
                            Button {
                                selection = TimetableSelection(event: event, occurrence: nil)
                            } label: {
                                TimetableUnscheduledRow(event: event, tint: tint(for: event, colors: colors))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Bez pevného termínu")
                    } footer: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Termín těchto akcí domluví vyučující – sleduj IS/STAG nebo e-mail.")
                            if let footer { footerLabel(footer) }
                        }
                    }
                }
            }
            .listSectionSpacing(.compact)
            .refreshable { await viewModel.refresh(context: modelContext) }
            .safeAreaInset(edge: .top, spacing: 0) {
                TimetableWeekStrip(viewModel: viewModel, now: now) { tint(for: $0, colors: colors) }
            }
        }
    }

    /// Chyba při obnovení – starší rozvrh zůstává zobrazený.
    /// - Parameter message: Text chyby.
    /// - Returns: Pruh s varováním a tlačítkem „Zkusit znovu“.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rozvrh se nepodařilo aktualizovat")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Zkusit znovu", action: refresh)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isLoading)
        }
    }

    /// Popisek zápatí s informací o poslední aktualizaci.
    /// - Parameter text: Text zápatí.
    /// - Returns: Vystředěný popisek s ikonou.
    private func footerLabel(_ text: String) -> some View {
        Label(text, systemImage: "arrow.triangle.2.circlepath")
            .labelStyle(.compact)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    // MARK: - Toolbar

    /// Položky toolbaru: přepínač den / týden a tlačítko Dnes (u načteného rozvrhu) a obnovení (po přihlášení).
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.screenState == .ready {
            ToolbarItem(placement: .principal) {
                Picker("Zobrazení", selection: $displayMode.animation(.snappy)) {
                    ForEach(TimetableDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Dnes") {
                    withAnimation(.snappy) { viewModel.showToday() }
                }
                .disabled(viewModel.isShowingDefaultDay())
            }
        }
        if viewModel.isConnected {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button("Obnovit rozvrh", systemImage: "arrow.clockwise", action: refresh)
                }
            }
        }
    }

    // MARK: - Pomocné

    /// Spustí obnovení rozvrhu ze STAGu na pozadí.
    private func refresh() {
        Task { await viewModel.refresh(context: modelContext) }
    }

    /// Barvy předmětů podle kódu (velkými písmeny) jako hex řetězce.
    private var subjectColors: [String: String] {
        Dictionary(subjects.map { ($0.code.uppercased(), $0.hexColor) }, uniquingKeysWith: { first, _ in first })
    }

    /// Vrátí barvu akce podle předmětu.
    /// - Parameters:
    ///   - event: Akce rozvrhu.
    ///   - colors: Předem spočtené barvy předmětů; `nil` znamená spočítat je znovu.
    /// - Returns: Barva akce.
    private func tint(for event: TimetableEvent, colors: [String: String]? = nil) -> Color {
        Color(hex: TimetableViewModel.hexColor(for: event, subjectColors: colors ?? subjectColors))
    }
}

/// Režim zobrazení rozvrhu: denní časová osa nebo týdenní mřížka.
///
/// Ukládá se do `@AppStorage` a vybírá se segmentovým přepínačem v toolbaru `TimetableView`.
enum TimetableDisplayMode: String, CaseIterable, Identifiable {
    case day
    case week

    /// Identifikátor pro `ForEach`.
    var id: Self { self }

    /// Lokalizovaný název režimu pro přepínač.
    var title: String {
        switch self {
        case .day: String(localized: "Den", comment: "Přepínač zobrazení rozvrhu")
        case .week: String(localized: "Týden", comment: "Přepínač zobrazení rozvrhu")
        }
    }
}

#Preview("Rozvrh – světlý") {
    TimetableView(viewModel: TimetableViewModel(previewSnapshot: .sample))
        .modelContainer(SampleData.previewContainer)
}

#Preview("Rozvrh – tmavý") {
    TimetableView(viewModel: TimetableViewModel(previewSnapshot: .sample))
        .modelContainer(SampleData.previewContainer)
        .preferredColorScheme(.dark)
}

#Preview("Nepřihlášený") {
    TimetableView(viewModel: TimetableViewModel(previewSnapshot: nil))
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
