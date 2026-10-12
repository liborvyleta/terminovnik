import SwiftUI

/// Logo aplikace Termínovník: kalendář s promoční čepicí a fajfkou.
///
/// Kreslí se čistě SwiftUI tvary v `Canvas` (SF Symbols se v logu ani ikoně používat nesmějí)
/// a barvy bere z privátní struktury `Palette` podle zvolené varianty. Nemá žádná data ani akce.
/// Stejný kód slouží v aplikaci (úvodní obrazovka, Nastavení) i pro vygenerování ikony v Assets
/// (1024 × 1024 px, `RenderAppIcon`). Vykresluje celý čtverec – zaoblení rohů dodá systém (ikona)
/// nebo `clipShape` (v aplikaci).
struct AppLogoView: View {
    /// Barevná varianta loga odpovídající variantám ikony aplikace.
    enum Variant {
        case light   // výchozí ikona
        case dark    // ikona pro tmavý režim (iOS 18+)
        case tinted  // šedotónová varianta, kterou systém obarví (iOS 18+)
    }

    /// Varianta barev, ve které se logo vykreslí (výchozí světlá).
    var variant: Variant = .light

    /// Čtvercový `Canvas` kreslený ve vrstvách: pozadí s přechodem, karta kalendáře se stínem,
    /// barevná hlavička, fajfka, promoční čepice a střapec. Souřadnice jsou relativní k velikosti.
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let colors = Palette(variant)

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }

            // 1) Pozadí s diagonálním přechodem a jemnou září vlevo nahoře
            context.fill(Path(rect(0, 0, 1, 1)), with: .linearGradient(
                Gradient(colors: colors.background), startPoint: point(0, 0), endPoint: point(1, 1)))
            context.fill(Path(ellipseIn: rect(-0.25, -0.35, 1.1, 1.0)), with: .radialGradient(
                Gradient(colors: [colors.glow, .clear]), center: point(0.28, 0.12), startRadius: 0, endRadius: 0.62 * s))

            // 2) Karta kalendáře se stínem
            let card = Path(roundedRect: rect(0.22, 0.36, 0.56, 0.48), cornerRadius: 0.085 * s, style: .continuous)
            var shadowed = context
            shadowed.addFilter(.shadow(color: colors.shadow, radius: 0.035 * s, x: 0, y: 0.022 * s))
            shadowed.fill(card, with: .color(colors.card))

            // 3) Barevná hlavička kalendáře (oříznutá do tvaru karty)
            context.drawLayer { layer in
                layer.clip(to: card)
                layer.fill(Path(rect(0.22, 0.36, 0.56, 0.125)), with: .linearGradient(
                    Gradient(colors: colors.header), startPoint: point(0.22, 0.36), endPoint: point(0.78, 0.485)))
            }

            // 4) Fajfka = splněný deadline
            var check = Path()
            check.move(to: point(0.36, 0.655))
            check.addLine(to: point(0.465, 0.755))
            check.addLine(to: point(0.65, 0.57))
            context.stroke(check, with: .color(colors.check),
                           style: StrokeStyle(lineWidth: 0.072 * s, lineCap: .round, lineJoin: .round))

            // 5) Promoční čepice „nasazená“ na kalendáři – spodní díl
            context.fill(Path(roundedRect: rect(0.34, 0.245, 0.32, 0.13), cornerRadius: 0.035 * s, style: .continuous),
                         with: .color(colors.capShade))

            // 6) Deska čepice (kosočtverec)
            var board = Path()
            board.move(to: point(0.5, 0.125))
            board.addLine(to: point(0.85, 0.245))
            board.addLine(to: point(0.5, 0.365))
            board.addLine(to: point(0.15, 0.245))
            board.closeSubpath()
            var boardContext = context
            boardContext.addFilter(.shadow(color: colors.shadow, radius: 0.02 * s, x: 0, y: 0.012 * s))
            boardContext.fill(board, with: .color(colors.capTop))

            // 7) Střapec visící vpravo mimo kartu
            var cord = Path()
            cord.move(to: point(0.5, 0.245))
            cord.addQuadCurve(to: point(0.805, 0.29), control: point(0.7, 0.235))
            cord.addLine(to: point(0.805, 0.4))
            context.stroke(cord, with: .color(colors.tassel),
                           style: StrokeStyle(lineWidth: 0.02 * s, lineCap: .round, lineJoin: .round))
            context.fill(Path(roundedRect: rect(0.778, 0.385, 0.054, 0.095), cornerRadius: 0.022 * s, style: .continuous),
                         with: .color(colors.tassel))
            context.fill(Path(ellipseIn: rect(0.474, 0.219, 0.052, 0.052)), with: .color(colors.tassel))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Logo Termínovník")
    }
}

/// Barvy jednotlivých variant loga.
///
/// Drží odstíny pozadí, karty, hlavičky, fajfky, čepice, střapce a stínu pro `AppLogoView`.
private struct Palette {
    let background: [Color]
    let glow: Color
    let card: Color
    let header: [Color]
    let check: Color
    let capTop: Color
    let capShade: Color
    let tassel: Color
    let shadow: Color

    /// Vytvoří paletu pro danou variantu loga.
    /// - Parameter variant: světlá, tmavá nebo šedotónová (tinted) varianta.
    init(_ variant: AppLogoView.Variant) {
        switch variant {
        case .light:
            background = [Color(hex: "#7471F9"), Color(hex: "#4338CA")]
            glow = .white.opacity(0.22)
            card = .white
            header = [Color(hex: "#FB923C"), Color(hex: "#F97316")]
            check = Color(hex: "#4F46E5")
            capTop = Color(hex: "#1E1B4B")
            capShade = Color(hex: "#312E81")
            tassel = Color(hex: "#FACC15")
            shadow = .black.opacity(0.28)
        case .dark:
            background = [Color(hex: "#24214A"), Color(hex: "#0B0A1A")]
            glow = Color(hex: "#6366F1").opacity(0.25)
            card = Color(hex: "#F1F1F6")
            header = [Color(hex: "#FB923C"), Color(hex: "#F97316")]
            check = Color(hex: "#4F46E5")
            capTop = Color(hex: "#6366F1")
            capShade = Color(hex: "#4338CA")
            tassel = Color(hex: "#FACC15")
            shadow = .black.opacity(0.5)
        case .tinted:
            background = [.black, .black]
            glow = .clear
            card = .white
            header = [Color(white: 0.72), Color(white: 0.66)]
            check = Color(white: 0.25)
            capTop = Color(white: 0.88)
            capShade = Color(white: 0.6)
            tassel = .white
            shadow = .clear
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AppLogoView(variant: .light)
        AppLogoView(variant: .dark)
        AppLogoView(variant: .tinted)
    }
    .frame(height: 120)
    .padding()
}
