import SwiftUI

// Jednoduché náhledy (snippety), které Siri a Zkratky zobrazí pod odpovědí.

/// Seznam hodin z rozvrhu (jedna hodina nebo celý den).
///
/// Náhled, který Siri a Zkratky zobrazí pod odpovědí akcí `NextLessonIntent` a `TimetableForDayIntent`.
struct TimetableSnippetView: View {
    /// Nadpis náhledu.
    let title: String
    /// Hodiny k zobrazení.
    let lessons: [TimetableOccurrence]
    /// Text zobrazený, když je seznam hodin prázdný.
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if lessons.isEmpty {
                Label(emptyText, systemImage: "cup.and.saucer.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lessons) { lesson in
                    lessonRow(lesson)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Vytvoří řádek jedné hodiny: barevný proužek předmětu, čas, název a detaily (kód, typ, místnost).
    /// - Parameter lesson: Výskyt hodiny.
    /// - Returns: Řádek seznamu.
    private func lessonRow(_ lesson: TimetableOccurrence) -> some View {
        let event = lesson.event
        let details = [event.subjectCode, event.typeName, event.locationText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.hexColor ?? "#687076"))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(IntentText.time(lesson.start))–\(IntentText.time(lesson.end))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(event.subjectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hodnoty jednoho deadlinu pro snippet (bez vazby na SwiftData model).
///
/// Hodnoty se z `ExamTask` zkopírují v okamžiku vytvoření, takže náhled nedrží odkaz na model.
struct DeadlineSnippetItem {
    /// Název povinnosti.
    let title: String
    /// „Kód – název“ předmětu (bez kódu jen název); bez předmětu prázdný.
    let subjectText: String
    /// Barva předmětu „#RRGGBB“, bez předmětu šedá „#687076“.
    let hexColor: String
    /// Lokalizovaný název typu povinnosti.
    let typeTitle: String
    /// SF Symbol typu povinnosti.
    let typeSymbol: String
    /// Datum a čas termínu.
    let dueDate: Date
    /// Text odpočtu, např. „Za 5 dní“.
    let countdown: String

    /// Převede povinnost na hodnoty pro náhled.
    /// - Parameter task: Povinnost, ze které se hodnoty převezmou.
    init(task: ExamTask) {
        title = task.title
        subjectText = task.subject.map { $0.code.isEmpty ? $0.name : "\($0.code) – \($0.name)" } ?? ""
        hexColor = task.subject?.hexColor ?? "#687076"
        typeTitle = task.taskType.title
        typeSymbol = task.taskType.symbol
        dueDate = task.dueDate
        countdown = Countdown.text(for: task.dueDate, isCompleted: task.isCompleted)
    }
}

/// Karta jednoho deadlinu s odpočtem.
///
/// Náhled pro akce `NextExamIntent` a `AddDeadlineIntent`; barva štítku odpočtu se řídí `DeadlineUrgency`.
struct DeadlineSnippetView: View {
    /// Nadpis karty.
    let header: String
    /// Zobrazovaný deadline; `nil` = zobrazí se `emptyText`.
    let item: DeadlineSnippetItem?
    /// Text zobrazený, když deadline chybí.
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.headline)

            if let item {
                let urgency = DeadlineUrgency(dueDate: item.dueDate)
                HStack(spacing: 12) {
                    Image(systemName: item.typeSymbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color(hex: item.hexColor), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if !item.subjectText.isEmpty {
                            Text(item.subjectText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text("\(item.typeTitle) · \(item.dueDate.deadlineFormatted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label(item.countdown, systemImage: urgency.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(urgency.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(urgency.color.opacity(0.15), in: Capsule())
                }
            } else {
                Label(emptyText, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
