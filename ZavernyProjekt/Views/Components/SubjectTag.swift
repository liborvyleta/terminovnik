import SwiftUI

/// Štítek s kódem předmětu v barvě předmětu.
struct SubjectTag: View {
    let subject: Subject

    var body: some View {
        Text(subject.code.isEmpty ? subject.name : subject.code)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(subject.color.gradient, in: Capsule())
    }
}
