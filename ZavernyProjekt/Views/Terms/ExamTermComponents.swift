import SwiftUI

// Stavební kameny záložky Zkoušky: karta nejbližšího zapsaného termínu, řádky termínů,
// dlaždice s datem, ukazatel obsazenosti a štítky.

// MARK: - Karta nejbližšího zapsaného termínu

/// Výrazná karta v barvě předmětu s odpočtem – nejbližší zapsaný termín
struct ExamTermHeroCard: View {
    let term: ExamTerm
    let subjectName: String?
    let tint: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(term.isCancelled ? "Termín zrušen" : "Nejbližší termín", systemImage: term.isCancelled ? "xmark.octagon.fill" : "checkmark.seal.fill")
                    .labelStyle(.compact(spacing: 6))
                    .textCase(.uppercase)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer(minLength: 8)

                Text(ExamTermsViewModel.countdownText(term, now: now))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(subjectName ?? term.subjectCode)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(term.isCancelled)
                HStack(spacing: 8) {
                    Text(term.subjectCode)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.25), in: Capsule())
                    Label(ExamTermsViewModel.typeText(term), systemImage: ExamTermsViewModel.symbol(for: term))
                        .labelStyle(.compact)
                        .font(.caption.weight(.semibold))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Label(ExamTermsViewModel.dayText(term.start), systemImage: "calendar")
                    Label(ExamTermsViewModel.timeText(term), systemImage: "clock")
                        .monospacedDigit()
                }
                HStack(spacing: 16) {
                    if let room = term.room, !room.isEmpty {
                        Label(room, systemImage: "mappin.and.ellipse")
                    }
                    if let teacher = term.teacher, !teacher.isEmpty {
                        Label(teacher, systemImage: "person")
                            .lineLimit(1)
                    }
                }
            }
            .labelStyle(.compact)
            .font(.subheadline.weight(.medium))

            if let unregister = ExamTermsViewModel.unregisterText(term, now: now) {
                Label(unregister, systemImage: "rectangle.portrait.and.arrow.right")
                    .labelStyle(.compact(spacing: 6))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(term.isCancelled ? Color.gray.gradient : tint.gradient)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: ExamTermsViewModel.symbol(for: term))
                        .font(.system(size: 92, weight: .bold))
                        .foregroundStyle(.white.opacity(0.12))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 14, y: 18)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .shadow(color: (term.isCancelled ? Color.gray : tint).opacity(0.35), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zobrazí podrobnosti o termínu")
    }
}

// MARK: - Řádek zapsaného termínu

/// Další zapsaný termín: dlaždice s datem, předmět, čas, místnost, zkoušející a odpočet
struct ExamTermRegisteredRow: View {
    let term: ExamTerm
    let subjectName: String?
    let tint: Color
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExamTermDateTile(date: term.start, tint: tint)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subjectName ?? term.subjectCode)
                        .font(.headline)
                        .lineLimit(2)
                        .strikethrough(term.isCancelled)
                    Spacer(minLength: 4)
                    ExamTermCountdownChip(term: term, now: now)
                }

                HStack(spacing: 8) {
                    TimetableCodeTag(code: term.subjectCode, tint: tint)
                    Label(ExamTermsViewModel.typeText(term), systemImage: ExamTermsViewModel.symbol(for: term))
                        .labelStyle(.compact)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if term.isCancelled {
                        ExamTermChip(text: "Zrušeno", symbol: "xmark.octagon.fill", color: .red)
                    }
                }

                ExamTermInfoLines(term: term)

                if let unregister = ExamTermsViewModel.unregisterText(term, now: now) {
                    Label(unregister, systemImage: "rectangle.portrait.and.arrow.right")
                        .labelStyle(.compact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Řádek vypsaného termínu

/// Vypsaný termín: datum, čas, místnost, obsazenost, okno přihlašování a důvod blokace
struct ExamTermAvailableRow: View {
    let term: ExamTerm
    let tint: Color
    let isNew: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExamTermDateTile(date: term.start, tint: tint)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ExamTermsViewModel.timeText(term))
                        .font(.headline)
                        .monospacedDigit()
                    Text(term.typeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if term.isRetake {
                        ExamTermChip(text: "opravný", color: .purple)
                    }
                    Spacer(minLength: 4)
                    if isNew {
                        ExamTermNewBadge()
                    }
                }

                ExamTermInfoLines(term: term)

                if ExamTermsViewModel.occupancyText(term) != nil {
                    ExamTermOccupancyBar(term: term)
                        .padding(.top, 2)
                }

                if let registration = ExamTermsViewModel.registrationText(term, now: now),
                   let window = ExamTermsViewModel.registrationWindow(term, now: now) {
                    let closingSoon = ExamTermsViewModel.isRegistrationClosingSoon(term, now: now)
                    Label(registration, systemImage: closingSoon ? "exclamationmark.circle.fill" : window.symbol)
                        .labelStyle(.compact)
                        .font(.caption.weight(closingSoon ? .semibold : .regular))
                        .foregroundStyle(closingSoon ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                }

                if let reason = ExamTermsViewModel.blockReasonText(term) {
                    Label(reason, systemImage: "info.circle")
                        .labelStyle(.compact)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Společné části

/// Místnost a zkoušející pod sebou
private struct ExamTermInfoLines: View {
    let term: ExamTerm

    var body: some View {
        if let room = term.room, !room.isEmpty {
            Label(room, systemImage: "mappin.and.ellipse")
                .labelStyle(.compact)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let teacher = term.teacher, !teacher.isEmpty {
            Label(teacher, systemImage: "person")
                .labelStyle(.compact)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Dlaždice ve stylu kalendáře: den v týdnu, číslo dne a měsíc v barvě předmětu
struct ExamTermDateTile: View {
    let date: Date
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).locale(.czech)))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(date.formatted(.dateTime.month(.abbreviated).locale(.czech)))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 50, height: 62)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Ukazatel obsazenosti: pruh a text „14/20 · volno 6“, plný termín červeně
struct ExamTermOccupancyBar: View {
    let term: ExamTerm

    var body: some View {
        let color = ExamTermsViewModel.occupancyColor(term)
        HStack(spacing: 8) {
            if let fraction = ExamTermsViewModel.occupancyFraction(term) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(color.gradient)
                                .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                        }
                    }
                    .frame(maxWidth: 110)
                    .accessibilityHidden(true)
            }
            Text(ExamTermsViewModel.occupancyText(term) ?? "")
                .font(.caption.weight(term.isFull ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(term.isFull ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Obsazenost \(ExamTermsViewModel.occupancyText(term) ?? "")")
    }
}

/// Odpočet do termínu v barvě naléhavosti („Za 9 dní“)
struct ExamTermCountdownChip: View {
    let term: ExamTerm
    let now: Date

    var body: some View {
        let urgency = DeadlineUrgency(dueDate: term.start, now: now)
        Label(ExamTermsViewModel.countdownText(term, now: now), systemImage: urgency.symbol)
            .labelStyle(.compact)
            .font(.caption.weight(.semibold))
            .foregroundStyle(urgency.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(urgency.color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

/// Štítek „Nový“ u nově vypsaného termínu
struct ExamTermNewBadge: View {
    var body: some View {
        Label("Nový", systemImage: "sparkles")
            .labelStyle(.compact(spacing: 3))
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.gradient, in: Capsule())
            .fixedSize()
    }
}

/// Malý barevný štítek („opravný“, „Zrušeno“, „Zapsáno“)
struct ExamTermChip: View {
    let text: String
    var symbol: String? = nil
    let color: Color

    var body: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol).labelStyle(.compact(spacing: 3))
            } else {
                Text(text)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .fixedSize()
    }
}

#Preview("Řádky") {
    let terms = ExamTerm.samples
    List {
        ExamTermHeroCard(term: terms[0], subjectName: "Pokročilé mobilní technologie", tint: .indigo, now: .now)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        ExamTermRegisteredRow(term: terms[0], subjectName: "Pokročilé mobilní technologie", tint: .indigo, now: .now)
        ForEach(terms.dropFirst()) { term in
            ExamTermAvailableRow(term: term, tint: .teal, isNew: term.id == "t4", now: .now)
        }
    }
}
