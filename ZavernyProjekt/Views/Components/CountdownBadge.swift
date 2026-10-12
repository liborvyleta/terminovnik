import SwiftUI

/// Barevný štítek s odpočtem do termínu.
///
/// Zobrazuje text z `Countdown.text(for:)` („Dnes“, „Zítra“, „Za 5 dní“) se symbolem a barvou
/// podle `DeadlineUrgency`. Nemá akce; používá se v řádku deadlinu (`TaskRowView`) a v detailu předmětu.
struct CountdownBadge: View {
    /// Deadline, ke kterému se odpočet počítá.
    let task: ExamTask

    var body: some View {
        let urgency = DeadlineUrgency(task: task)
        Label(Countdown.text(for: task), systemImage: urgency.symbol)
            .labelStyle(.compact)
            .font(.caption.weight(.semibold))
            .foregroundStyle(urgency.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(urgency.color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}
