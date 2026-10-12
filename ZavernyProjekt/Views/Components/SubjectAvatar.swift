import SwiftUI

/// Zaoblený čtverec v barvě předmětu s iniciálami.
///
/// Čistě dekorativní (skrytý pro VoiceOver), bez akcí. Používá se na kartě předmětu
/// a ve formuláři předmětu.
struct SubjectAvatar: View {
    /// Iniciály předmětu.
    let initials: String
    /// Barva předmětu.
    let color: Color
    /// Délka strany čtverce v bodech.
    var size: CGFloat = 48

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
