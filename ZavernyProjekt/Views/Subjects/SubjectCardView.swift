import SwiftUI

/// Karta předmětu v seznamu: avatar, název, kód, kredity, postup a nejbližší deadline.
struct SubjectCardView: View {
    let subject: Subject

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SubjectAvatar(initials: subject.initials, color: subject.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(verbatim: "\(subject.code) · \(creditsText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let grade, grade.displayGrade != nil {
                    GradeBadge(grade: grade)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: subject.progress)
                    .tint(subject.color)
                HStack {
                    Text("Splněno \(subject.completedCount) z \(subject.taskList.count)")
                    Spacer()
                    nextDeadline
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.compact)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Hodnocení ze STAGu (@Observable singleton – nová známka se na kartě hned ukáže)
    private var grade: SubjectGrade? {
        subject.code.isEmpty ? nil : GradeStore.shared.grade(forSubjectCode: subject.code)
    }

    /// „4 kredity“ – tvar podle počtu doplňuje String Catalog
    private var creditsText: String {
        String(localized: "\(subject.credits) kreditů")
    }

    @ViewBuilder
    private var nextDeadline: some View {
        if let next = subject.nextTask {
            let urgency = DeadlineUrgency(task: next)
            Label("\(next.taskType.title): \(Countdown.text(for: next))", systemImage: urgency.symbol)
                .foregroundStyle(urgency.color)
                .fontWeight(.medium)
        } else if !subject.taskList.isEmpty {
            Label("Vše splněno", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .fontWeight(.medium)
        } else {
            Text("Bez úkolů")
        }
    }
}
