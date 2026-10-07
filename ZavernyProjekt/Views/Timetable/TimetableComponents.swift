import SwiftUI

// Stavební kameny záložky Rozvrh: výběr dne, karta „Teď probíhá / Další hodina“,
// řádky akcí a volný den.

// MARK: - Štítek kódu

/// Štítek s kódem předmětu v barvě předmětu (jako `SubjectTag`, jen bez modelu `Subject`)
struct TimetableCodeTag: View {
    let code: String
    let tint: Color

    var body: some View {
        Text(code)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.gradient, in: Capsule())
    }
}

// MARK: - Výběr dne

/// Vodorovný výběr dne aktuálního týdne se šipkami na předchozí / další týden.
/// Vodorovným tahem přes pás se také přepíná týden.
struct TimetableWeekStrip: View {
    let viewModel: TimetableViewModel
    let now: Date
    /// V týdenním režimu dny ukazuje přímo mřížka – dlaždice dnů skryjeme
    var showsDays: Bool = true
    /// Barvy předmětů pro tečky pod dnem
    let tint: (TimetableEvent) -> Color

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 10) {
            header
            if showsDays {
                HStack(spacing: 6) {
                    ForEach(viewModel.weekDays) { day in
                        dayButton(day)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 50, abs(horizontal) > abs(value.translation.height) else { return }
                withAnimation(.snappy) {
                    if horizontal < 0 {
                        viewModel.showNextWeek()
                    } else {
                        viewModel.showPreviousWeek()
                    }
                }
            }
        )
    }

    private var header: some View {
        HStack {
            weekButton(symbol: "chevron.left", label: "Předchozí týden") { viewModel.showPreviousWeek() }
            Spacer()
            VStack(spacing: 1) {
                Text(viewModel.weekTitle(now: now))
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.weekRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Spacer()
            weekButton(symbol: "chevron.right", label: "Další týden") { viewModel.showNextWeek() }
        }
    }

    private func weekButton(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.secondary)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: TimetableDay) -> some View {
        let isSelected = viewModel.isSelected(day.date)
        let isToday = viewModel.isToday(day.date, now: now)
        let occurrences = viewModel.occurrences(on: day.date)
        let dotColors = uniqueColors(of: occurrences)

        return Button {
            withAnimation(.snappy) { viewModel.select(day.date) }
        } label: {
            VStack(spacing: 4) {
                Text(viewModel.weekdaySymbol(day.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(isToday ? Color.accentColor : .secondary))
                Text(viewModel.dayNumber(day.date))
                    .font(.title3.weight(isToday || isSelected ? .bold : .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(isToday ? Color.accentColor : .primary))
                HStack(spacing: 3) {
                    ForEach(dotColors.indices, id: \.self) { index in
                        Circle()
                            .fill(isSelected ? Color.white : dotColors[index])
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 3)
                        .matchedGeometryEffect(id: "selectedDay", in: selectionNamespace)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: day.date, isToday: isToday, count: occurrences.count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Nejvýš tři různé barvy předmětů daného dne
    private func uniqueColors(of occurrences: [TimetableOccurrence]) -> [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for occurrence in occurrences where seen.insert(occurrence.event.subjectCode).inserted {
            colors.append(tint(occurrence.event))
            if colors.count == 3 { break }
        }
        return colors
    }

    private func accessibilityLabel(for day: Date, isToday: Bool, count: Int) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))
        let lessons = count == 0
            ? String(localized: "volno", comment: "Den bez výuky (VoiceOver)")
            : String(localized: "\(count) akcí", comment: "Počet akcí rozvrhu ve dni")
        return isToday
            ? String(localized: "Dnes, \(date), \(lessons)", comment: "VoiceOver: dnešní den, datum, počet akcí")
            : "\(date), \(lessons)"
    }
}

// MARK: - Karta „Teď probíhá / Další hodina“

/// Výrazná karta s probíhající nebo nejbližší hodinou a odpočtem
struct TimetableNowCard: View {
    let occurrence: TimetableOccurrence
    let now: Date
    let tint: Color

    private var event: TimetableEvent { occurrence.event }
    private var isOngoing: Bool { occurrence.start <= now }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: isOngoing ? "record.circle" : "forward.fill")
                        .symbolEffect(.pulse, isActive: isOngoing)
                    Text(isOngoing ? "Teď probíhá" : "Další hodina")
                        .textCase(.uppercase)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))

                Spacer(minLength: 8)

                Text(TimetableViewModel.countdownText(for: occurrence, now: now))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(event.subjectName)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(event.subjectCode)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.25), in: Capsule())
                    Label(event.typeName, systemImage: TimetableViewModel.symbol(for: event))
                        .labelStyle(.compact)
                        .font(.caption.weight(.semibold))
                }
            }

            HStack(spacing: 16) {
                Label(TimetableViewModel.timeRange(of: occurrence), systemImage: "clock")
                    .monospacedDigit()
                if let location = event.locationText {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
            }
            .labelStyle(.compact)
            .font(.subheadline.weight(.medium))

            if isOngoing {
                ProgressView(value: TimetableViewModel.progress(of: occurrence, now: now))
                    .tint(.white)
                    .accessibilityLabel("Uplynulá část hodiny")
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tint.gradient)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: TimetableViewModel.symbol(for: event))
                        .font(.system(size: 92, weight: .bold))
                        .foregroundStyle(.white.opacity(0.12))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 14, y: 18)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zobrazí podrobnosti o hodině")
    }
}

// MARK: - Řádek akce

/// Řádek výskytu akce: čas, barevný proužek, předmět, typ, místnost a vyučující
struct TimetableOccurrenceRow: View {
    let occurrence: TimetableOccurrence
    let now: Date
    let tint: Color

    private var event: TimetableEvent { occurrence.event }
    private var isOngoing: Bool { occurrence.start <= now && now < occurrence.end }
    private var isPast: Bool { occurrence.end <= now }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(TimetableViewModel.time(occurrence.start))
                    .font(.subheadline.weight(.semibold))
                Text(TimetableViewModel.time(occurrence.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: 46, alignment: .trailing)

            Capsule()
                .fill(tint.gradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            TimetableEventDetails(event: event, tint: tint, isOngoing: isOngoing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .opacity(isPast ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Řádek akce bez pevného termínu
struct TimetableUnscheduledRow: View {
    let event: TimetableEvent
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 46)

            Capsule()
                .fill(tint.gradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            TimetableEventDetails(event: event, tint: tint, isOngoing: false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Společný obsah řádků: název, štítky, místnost, vyučující
private struct TimetableEventDetails: View {
    let event: TimetableEvent
    let tint: Color
    let isOngoing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.subjectName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if isOngoing {
                    TimetableLiveBadge(tint: tint)
                }
            }

            HStack(spacing: 8) {
                TimetableCodeTag(code: event.subjectCode, tint: tint)
                Label(event.typeName, systemImage: TimetableViewModel.symbol(for: event))
                    .labelStyle(.compact)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let parity = event.parityText {
                    Text(parity)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }

            if let location = event.locationText {
                Label(location, systemImage: "mappin.and.ellipse")
                    .labelStyle(.compact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let teacher = event.teacher, !teacher.isEmpty {
                Label(teacher, systemImage: "person")
                    .labelStyle(.compact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Štítek „Probíhá“ s pulzující tečkou
struct TimetableLiveBadge: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .symbolEffect(.pulse)
            Text("Probíhá")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.gradient, in: Capsule())
    }
}

// MARK: - Volný den

/// Den bez výuky
struct TimetableFreeDayView: View {
    let isWeekend: Bool
    /// Popis nejbližšího dne s výukou, např. „čtvrtek 8. října“
    let nextLessonText: String?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: isWeekend ? "beach.umbrella.fill" : "sun.max.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: isWeekend)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Volno")
                    .font(.title2.bold())
                Text("Tento den nemáš žádnou výuku. Užij si ho!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let nextLessonText {
                    Label("Další výuka: \(nextLessonText)", systemImage: "arrow.forward.circle")
                        .labelStyle(.compact)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
