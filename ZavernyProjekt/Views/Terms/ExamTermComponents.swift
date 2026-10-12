import SwiftUI

// Stavební kameny záložky Zkoušky: karta nejbližšího zapsaného termínu, řádky termínů,
// dlaždice s datem, ukazatel obsazenosti a štítky.

// MARK: - Karta nejbližšího zapsaného termínu

/// Výrazná karta v barvě předmětu s odpočtem k nejbližšímu zapsanému termínu.
///
/// Zobrazuje název a kód předmětu, typ termínu, den, čas, místnost, zkoušejícího
/// a případně lhůtu pro odhlášení; zrušený termín je šedý a přeškrtnutý. Data dostává
/// hotová zvenku, texty skládá přes statické pomocníky `ExamTermsViewModel`.
/// Používá se nahoře v seznamu `ExamTermsView`, klepnutím se otevře detail termínu.
struct ExamTermHeroCard: View {
    /// Zobrazovaný zapsaný termín.
    let term: ExamTerm
    /// Název předmětu z rozvrhu; když chybí, zobrazí se kód předmětu.
    let subjectName: String?
    /// Barva předmětu použitá pro pozadí karty.
    let tint: Color
    /// Aktuální čas pro výpočet odpočtu a lhůty odhlášení.
    let now: Date

    /// Hlavička se štítkem a odpočtem, předmět, datum a místo pod sebou,
    /// na pozadí gradient v barvě předmětu s velkou průhlednou ikonou typu termínu.
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

/// Řádek dalšího zapsaného termínu v seznamu zkoušek.
///
/// Zobrazuje dlaždici s datem, název předmětu s odpočtem, kód a typ termínu,
/// štítek „Zrušeno“, místnost, zkoušejícího a lhůtu pro odhlášení. Data dostává zvenku
/// a texty skládá přes `ExamTermsViewModel`. Používá se v sekci zapsaných termínů `ExamTermsView`.
struct ExamTermRegisteredRow: View {
    /// Zobrazovaný zapsaný termín.
    let term: ExamTerm
    /// Název předmětu z rozvrhu; když chybí, zobrazí se kód předmětu.
    let subjectName: String?
    /// Barva předmětu pro dlaždici s datem a kód předmětu.
    let tint: Color
    /// Aktuální čas pro odpočet a lhůtu odhlášení.
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

/// Řádek vypsaného termínu, na který se lze přihlásit.
///
/// Zobrazuje dlaždici s datem, čas a typ termínu, štítky „opravný“ a „Nový“, místnost,
/// zkoušejícího, ukazatel obsazenosti, okno přihlašování (oranžově, když se brzy zavírá)
/// a důvod, proč STAG zápis blokuje. Texty skládá přes `ExamTermsViewModel`.
/// Používá se v sekcích vypsaných termínů v `ExamTermsView`.
struct ExamTermAvailableRow: View {
    /// Zobrazovaný vypsaný termín.
    let term: ExamTerm
    /// Barva předmětu pro dlaždici s datem.
    let tint: Color
    /// Zda je termín nově vypsaný od poslední synchronizace (zobrazí štítek „Nový“).
    let isNew: Bool
    /// Aktuální čas pro výpočet okna přihlašování.
    let now: Date

    /// Dlaždice s datem vlevo, vpravo sloupec s časem, štítky, místem, obsazeností,
    /// oknem přihlašování a důvodem blokace.
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

/// Místnost a zkoušející termínu pod sebou.
///
/// Zobrazí jen údaje, které nejsou prázdné. Sdílí ho řádky `ExamTermRegisteredRow`
/// a `ExamTermAvailableRow` v tomto souboru.
private struct ExamTermInfoLines: View {
    /// Termín, jehož místnost a zkoušející se zobrazí.
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

/// Dlaždice ve stylu kalendáře s datem termínu.
///
/// Zobrazuje zkratku dne v týdnu, číslo dne a zkratku měsíce v češtině na podkladu
/// v barvě předmětu. Pro VoiceOver je skrytá. Používá se v řádcích termínů.
struct ExamTermDateTile: View {
    /// Zobrazované datum.
    let date: Date
    /// Barva předmětu pro podklad, rámeček a den v týdnu.
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).locale(.czech)))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text(verbatim: "\(Calendar.current.component(.day, from: date))")
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

/// Ukazatel obsazenosti termínu.
///
/// Zobrazuje pruh zaplnění a text typu „14/20 · volno 6“; plný termín má text
/// tučně červeně. Barvu, podíl i text bere ze statických pomocníků `ExamTermsViewModel`.
/// Používá se v `ExamTermAvailableRow` a v detailu termínu.
struct ExamTermOccupancyBar: View {
    /// Termín, jehož obsazenost se zobrazí.
    let term: ExamTerm

    /// Pruh se zaplněním (jen když je známa kapacita) a vedle text obsazenosti.
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

/// Odpočet do začátku termínu v barvě naléhavosti („Za 9 dní“).
///
/// Barvu a ikonu určuje `DeadlineUrgency` podle data termínu, text
/// `ExamTermsViewModel.countdownText`. Používá se v `ExamTermRegisteredRow`.
struct ExamTermCountdownChip: View {
    /// Termín, k jehož začátku se odpočítává.
    let term: ExamTerm
    /// Aktuální čas pro výpočet odpočtu.
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

/// Štítek „Nový“ u nově vypsaného termínu.
///
/// Bílý text s ikonou na kapsli v barvě aplikace. Používá se v `ExamTermAvailableRow`.
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

/// Malý barevný štítek s textem a volitelnou ikonou.
///
/// Slouží pro označení jako „opravný“, „Zrušeno“ nebo „Zapsáno“ v řádcích
/// a detailu termínu.
struct ExamTermChip: View {
    /// Text štítku.
    let text: LocalizedStringKey
    /// Volitelný název SF Symbolu zobrazený před textem.
    var symbol: String? = nil
    /// Barva textu a podkladu štítku.
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
