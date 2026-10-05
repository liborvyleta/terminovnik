import SwiftUI

/// Detail termínu zkoušky (sheet): kdy, kde, kdo, obsazenost, přihlašování a přidání do Kalendáře.
struct ExamTermDetailView: View {
    let term: ExamTerm
    let subjectName: String?
    let tint: Color
    var isNew: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingToCalendar = false

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
                    occupancySection
                    registrationSection(now: now)

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

    @ViewBuilder
    private var occupancySection: some View {
        if ExamTermsViewModel.occupancyText(term) != nil {
            Section("Obsazenost") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        if let occupied = term.occupied {
                            Text("\(occupied)")
                                .font(.title2.bold())
                                .monospacedDigit()
                            Text(term.capacity.map { "z \($0) míst" } ?? CzechPlural.form(occupied, one: "zapsaný", few: "zapsaní", many: "zapsaných"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let free = term.freeSpots {
                            Text(term.isFull ? "Plno" : "volno \(free)")
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
                Label("Zapsat/odhlásit se můžeš na portálu IS/STAG.", systemImage: "info.circle")
                    .labelStyle(.compact(spacing: 6))
                Text("Událost uložíš v systémovém Kalendáři – aplikace k němu nepotřebuje přístup.")
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Texty

    /// „Zkouška AP9PT: Pokročilé mobilní technologie (opravný)“
    private var calendarTitle: String {
        var title = "\(term.typeName) \(term.subjectCode)"
        if let subjectName { title += ": \(subjectName)" }
        if term.isRetake { title += " (opravný)" }
        return title
    }

    /// Poznámka události v Kalendáři: místnost, zkoušející, poznámka, zdroj
    private var calendarNotes: String {
        var lines: [String] = []
        if let room = term.room, !room.isEmpty { lines.append("Místnost: \(room)") }
        if let teacher = term.teacher, !teacher.isEmpty { lines.append("Zkoušející: \(teacher)") }
        if let note = term.note, !note.isEmpty { lines.append(note) }
        lines.append("Termín z IS/STAG – Termínovník")
        return lines.joined(separator: "\n")
    }
}

#Preview("Zapsaný") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExamTermDetailView(term: ExamTerm.samples[0], subjectName: "Pokročilé mobilní technologie", tint: Color(hex: "#3E63DD"))
        }
}

#Preview("Vypsaný – plno") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ExamTermDetailView(term: ExamTerm.samples[2], subjectName: "Evoluční výpočetní techniky", tint: Color(hex: "#B8860B"), isNew: true)
        }
        .preferredColorScheme(.dark)
}
