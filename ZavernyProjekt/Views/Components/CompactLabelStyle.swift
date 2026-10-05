import SwiftUI

/// Kompaktní styl štítku: ikona a text těsně vedle sebe.
/// Výchozí styl v řádcích Listu zarovnává ikony do sloupce a roztahuje mezery,
/// což se pro malé štítky (odpočet, typ, čas) nehodí.
struct CompactLabelStyle: LabelStyle {
    var spacing: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    static var compact: CompactLabelStyle { CompactLabelStyle() }

    static func compact(spacing: CGFloat) -> CompactLabelStyle { CompactLabelStyle(spacing: spacing) }
}
