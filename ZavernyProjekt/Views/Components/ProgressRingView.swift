import SwiftUI

/// Kruhový ukazatel postupu s procenty uprostřed.
struct ProgressRingView: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                Text("hotovo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Splněno \(Int(progress * 100)) procent")
    }
}
