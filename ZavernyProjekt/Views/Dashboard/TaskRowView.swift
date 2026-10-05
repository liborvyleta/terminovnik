import SwiftUI

/// Řádek deadlinu: checkbox, název, odpočet, štítek předmětu, typ a termín.
/// Používá se na Dashboardu i v detailu předmětu.
struct TaskRowView: View {
    let task: ExamTask
    /// V detailu předmětu štítek předmětu skryjeme (je zřejmý z kontextu)
    var showsSubject = true
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    CountdownBadge(task: task)
                }

                HStack(spacing: 8) {
                    if showsSubject, let subject = task.subject {
                        SubjectTag(subject: subject)
                    }
                    Label(task.taskType.title, systemImage: task.taskType.symbol)
                        .labelStyle(.compact)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Label(task.dueDate.deadlineFormatted, systemImage: "clock")
                    .labelStyle(.compact)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if task.isCompleted, let grade = task.pointsOrGrade, !grade.isEmpty {
                    Label("Hodnocení: \(grade)", systemImage: "star.fill")
                        .labelStyle(.compact)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Kulatý checkbox – klepnutím se deadline označí jako splněný
    private var checkbox: some View {
        Button(action: onToggle) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(task.isCompleted ? Color.green : (task.subject?.color ?? .secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        // .borderless: klepnutí na checkbox nespustí akci celého řádku v Listu
        .buttonStyle(.borderless)
        .accessibilityLabel(task.isCompleted ? "Označit jako nesplněné" : "Označit jako splněné")
    }
}
