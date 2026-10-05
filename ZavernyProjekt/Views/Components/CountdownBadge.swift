import SwiftUI

/// Barevný štítek s odpočtem („Dnes“, „Zítra“, „Za 5 dní“). Barva odpovídá naléhavosti.
struct CountdownBadge: View {
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
