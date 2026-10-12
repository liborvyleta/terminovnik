import SwiftUI

// Stavební kameny studijních výsledků: karta s průměrem, řádek předmětu, čipy zápočtu a zkoušky,
// hodnocení v detailu předmětu a vstupní karta v záložce Předměty.

// MARK: - Karta s průměrem

/// Výrazná karta v barvě průměru se souhrnem studijních výsledků.
///
/// Zobrazuje vážený průměr se slovním hodnocením, získané kredity, počet absolvovaných
/// předmětů a ukazatel podílu absolvovaných. Data dostává jako `GradeSummary`, barvu a texty
/// bere ze statických pomocníků `GradesViewModel`. Používá se nahoře v `GradesView`.
struct GradeSummaryCard: View {
    /// Souhrn známek, ze kterého se karta skládá.
    let summary: GradeSummary

    /// Vážený průměr, nebo `nil`, když zatím nejsou známky.
    private var average: Double? { summary.weightedAverage }
    /// Barva karty podle úrovně průměru, bez průměru barva aplikace.
    private var tint: Color { average == nil ? .accentColor : GradesViewModel.averageLevel(average).color }

    /// Nadpis, velký průměr se slovním hodnocením, dvě dlaždice statistik a ukazatel průběhu
    /// na gradientu v barvě průměru s průhlednou ikonou.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Vážený průměr", systemImage: "chart.bar.fill")
                .labelStyle(.compact(spacing: 6))
                .textCase(.uppercase)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: GradesViewModel.averageText(average))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Group {
                    if let average {
                        Text(SubjectGrade.verbalText(value: average))
                    } else {
                        Text("Zatím bez známek")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            HStack(spacing: 10) {
                stat(value: "\(summary.earnedCredits)", title: "Získané kredity", symbol: "star.fill")
                stat(value: "\(summary.passedCount)/\(summary.totalCount)", title: "Absolvované předměty", symbol: "checkmark.seal.fill")
            }

            ProgressView(value: GradesViewModel.passedFraction(summary))
                .tint(.white)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tint.gradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 96, weight: .bold))
                        .foregroundStyle(.white.opacity(0.12))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 18, y: -6)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
        .animation(.snappy, value: summary)
        .accessibilityElement(children: .combine)
    }

    /// Dlaždice jedné statistiky s hodnotou, ikonou a popiskem.
    /// - Parameters:
    ///   - value: Zobrazená hodnota.
    ///   - title: Popisek pod hodnotou.
    ///   - symbol: Název SF Symbolu u hodnoty.
    /// - Returns: Pohled dlaždice.
    private func stat(value: String, title: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
            }
            .labelStyle(.compact(spacing: 6))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Řádek předmětu

/// Řádek předmětu v seznamu výsledků.
///
/// Zobrazuje kód, kredity, název, čipy zápočtu a zkoušky, štítek „Uznáno“ a vpravo
/// odznak se známkou. Data dostává zvenku. Používá se v `GradesView`.
struct GradeRow: View {
    /// Hodnocení předmětu ze STAGu.
    let grade: SubjectGrade
    /// Zobrazený název předmětu.
    let name: String
    /// Barva předmětu pro štítek kódu.
    let tint: Color

    /// Sloupec s kódem, názvem a čipy vlevo, odznak známky vpravo.
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    TimetableCodeTag(code: grade.code, tint: tint)
                    if let credits = grade.credits {
                        Text(GradesViewModel.creditsText(credits))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if hasChips {
                    HStack(spacing: 6) {
                        if let creditTest = grade.creditTest {
                            GradePartChip(title: "Zápočet", part: creditTest)
                        }
                        if let exam = grade.exam {
                            GradePartChip(title: "Zkouška", part: exam)
                        }
                        if grade.isRecognized {
                            GradeStatusTag(title: "Uznáno", symbol: "arrow.triangle.swap", color: .indigo, compact: true)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            GradeBadge(grade: grade)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Zda řádek zobrazí řádek čipů (zápočet, zkouška nebo uznání).
    private var hasChips: Bool { grade.creditTest != nil || grade.exam != nil || grade.isRecognized }
}

/// Malý čip části hodnocení: „Zápočet ✓“, „Zápočet ✗“, „Zkouška B“.
///
/// Barvu a případnou ikonu určuje `SubjectGrade.level` podle výsledku, jinak se
/// zobrazí výsledek textem. Používá se v `GradeRow`.
struct GradePartChip: View {
    /// Název části hodnocení.
    let title: LocalizedStringKey
    /// Část hodnocení s výsledkem.
    let part: GradePart

    var body: some View {
        let level = SubjectGrade.level(part.result)
        HStack(spacing: 3) {
            Text(title)
            if let symbol = level.symbol {
                Image(systemName: symbol)
                    .fontWeight(.heavy)
            } else {
                Text(verbatim: part.result)
                    .fontWeight(.bold)
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(level.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(level.color.opacity(0.13), in: Capsule())
        .fixedSize()
    }
}

/// Stavový štítek „Absolvováno“ / „Uznáno“.
///
/// Ikona s textem na kapsli v zadané barvě, ve dvou velikostech. Používá se
/// v `GradeRow` a `SubjectGradeSummaryRow`.
struct GradeStatusTag: View {
    /// Text štítku.
    let title: LocalizedStringKey
    /// Název SF Symbolu.
    let symbol: String
    /// Barva textu a podkladu.
    let color: Color
    /// Menší varianta do řádků seznamu.
    var compact = false

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.compact(spacing: compact ? 3 : 4))
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}

// MARK: - Hodnocení v detailu předmětu

/// Hlavička hodnocení v detailu předmětu.
///
/// Zobrazuje velkou známku, slovní hodnocení, semestr s kredity a štítky
/// „Absolvováno“ a „Uznáno“. Používá se v `SubjectDetailView`.
struct SubjectGradeSummaryRow: View {
    /// Hodnocení předmětu ze STAGu.
    let grade: SubjectGrade

    var body: some View {
        HStack(spacing: 16) {
            GradeBadge(grade: grade, size: .large)

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let value = grade.displayGrade {
                        Text(SubjectGrade.verbalText(value) ?? String(localized: "Známka \(value)", comment: "Známka bez slovního hodnocení"))
                    } else {
                        Text("Zatím bez hodnocení")
                    }
                }
                .font(.title3.bold())
                .lineLimit(2)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if grade.isPassed || grade.isRecognized {
                    HStack(spacing: 6) {
                        if grade.isPassed {
                            GradeStatusTag(title: "Absolvováno", symbol: "checkmark.seal.fill", color: GradeLevel.passed.color)
                        }
                        if grade.isRecognized {
                            GradeStatusTag(title: "Uznáno", symbol: "arrow.triangle.swap", color: .indigo)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Podtitulek se semestrem a kredity, např. „LS 2025/2026 · 5 kreditů“.
    private var subtitle: String {
        guard let credits = grade.credits else { return grade.semesterTitle }
        return "\(grade.semesterTitle) · \(GradesViewModel.creditsText(credits))"
    }
}

/// Řádek zápočtu nebo zkoušky v detailu předmětu.
///
/// Zobrazuje ikonu v barvě výsledku, název, datum, pokus, body, zkoušejícího a vpravo
/// odznak se známkou a slovním hodnocením. Používá se v `SubjectDetailView`.
struct GradePartDetailRow: View {
    /// Název části hodnocení.
    let title: LocalizedStringKey
    /// Název SF Symbolu vlevo.
    let symbol: String
    /// Část hodnocení s výsledkem a podrobnostmi.
    let part: GradePart

    /// Ikona vlevo, uprostřed název, podrobnosti a zkoušející, vpravo známka.
    var body: some View {
        let level = SubjectGrade.level(part.result)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(level.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let examiner = part.examiner?.trimmingCharacters(in: .whitespaces), !examiner.isEmpty {
                    Label(examiner, systemImage: "person")
                        .labelStyle(.compact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                GradeBadge(part: part)
                if let verbal = SubjectGrade.verbalText(part.result) {
                    Text(verbal)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(level.color)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Podrobnosti části hodnocení, např. „15. 12. 2026 · 2. pokus · 45 b.“ (chybějící se vynechají).
    private var details: [String] {
        [
            part.date.map(GradesViewModel.dateText),
            GradesViewModel.attemptText(part),
            GradesViewModel.pointsText(part)
        ].compactMap { $0 }
    }
}

// MARK: - Vstup v záložce Předměty

/// Vstupní karta „Studijní výsledky“ nad seznamem předmětů.
///
/// Zobrazuje ikonu v barvě průměru, podtitulek s kredity a absolvovanými předměty
/// a vpravo vážený průměr. Data dostává zvenku (z `GradeStore`). Používá se v `SubjectsListView`
/// jako odkaz na `GradesView`.
struct GradesEntryCard: View {
    /// Souhrn známek pro průměr a kredity.
    let summary: GradeSummary
    /// Zda jsou nějaké známky; bez nich se ukáže popis obrazovky.
    let hasGrades: Bool

    /// Barva podle úrovně průměru, bez průměru barva aplikace.
    private var tint: Color {
        summary.weightedAverage == nil ? .accentColor : GradesViewModel.averageLevel(summary.weightedAverage).color
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Studijní výsledky")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            if let average = summary.weightedAverage {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: GradesViewModel.averageText(average))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text("průměr")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Podtitulek „17 kreditů · 4 z 6 předmětů“, bez známek popis obrazovky.
    private var subtitle: String {
        guard hasGrades else { return String(localized: "Známky, kredity a vážený průměr") }
        return "\(GradesViewModel.creditsText(summary.earnedCredits)) · \(GradesViewModel.passedText(summary))"
    }
}

#Preview("Komponenty") {
    let grades = SubjectGrade.samples
    List {
        Section {
            GradeSummaryCard(summary: GradeSummary(grades: grades))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            GradesEntryCard(summary: GradeSummary(grades: grades), hasGrades: true)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            ForEach(grades) { grade in
                GradeRow(grade: grade, name: grade.name ?? grade.code, tint: .indigo)
            }
        }
        Section {
            SubjectGradeSummaryRow(grade: grades[3])
            if let creditTest = grades[3].creditTest {
                GradePartDetailRow(title: "Zápočet", symbol: "checkmark.seal.fill", part: creditTest)
            }
            if let exam = grades[3].exam {
                GradePartDetailRow(title: "Zkouška", symbol: "graduationcap.fill", part: exam)
            }
        }
    }
}
