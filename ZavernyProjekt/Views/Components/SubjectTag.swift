import SwiftUI

/// Štítek s kódem předmětu v barvě předmětu.
///
/// Zobrazuje kód předmětu (bez kódu jeho název) v kapsli. Nemá akce; používá se v řádku deadlinu,
/// v detailu předmětu a v rozvrhu.
struct SubjectTag: View {
    /// Předmět, jehož kód a barva se zobrazí.
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
