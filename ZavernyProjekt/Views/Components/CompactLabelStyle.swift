import SwiftUI

/// Kompaktní styl štítku: ikona a text těsně vedle sebe.
///
/// Výchozí styl v řádcích Listu zarovnává ikony do sloupce a roztahuje mezery, což se pro malé
/// štítky (odpočet, typ, čas) nehodí. Nemá data ani akce; používá se přes `.labelStyle(.compact)`
/// napříč aplikací (řádky deadlinů, rozvrh, zkoušky, známky, nastavení).
struct CompactLabelStyle: LabelStyle {
    /// Mezera mezi ikonou a textem v bodech.
    var spacing: CGFloat = 4

    /// Poskládá ikonu a text do `HStack` s danou mezerou.
    /// - Parameter configuration: ikona a titulek štítku.
    /// - Returns: kompaktní štítek.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    /// Kompaktní styl s výchozí mezerou 4 body.
    static var compact: CompactLabelStyle { CompactLabelStyle() }

    /// Kompaktní styl s vlastní mezerou.
    /// - Parameter spacing: mezera mezi ikonou a textem.
    /// - Returns: kompaktní styl štítku.
    static func compact(spacing: CGFloat) -> CompactLabelStyle { CompactLabelStyle(spacing: spacing) }
}
