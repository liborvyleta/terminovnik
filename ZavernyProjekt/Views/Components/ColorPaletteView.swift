import SwiftUI

/// Mřížka barev pro výběr barvy předmětu.
///
/// Zobrazuje barvy z `SubjectPalette.entries` v šesti sloupcích; vybraná barva má fajfku a obrys.
/// Klepnutím uživatel barvu vybere (hex se zapíše do `selection`). Používá se ve formuláři předmětu
/// (`SubjectFormSheet`).
struct ColorPaletteView: View {
    /// Hex kód vybrané barvy, sdílený s nadřazeným formulářem.
    @Binding var selection: String

    /// Šest pružných sloupců mřížky.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    /// Mřížka kruhových tlačítek – jedno pro každou barvu palety.
    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(SubjectPalette.entries) { entry in
                let isSelected = entry.hex == selection
                Button {
                    withAnimation(.snappy) { selection = entry.hex }
                } label: {
                    Circle()
                        .fill(Color(hex: entry.hex).gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay {
                            Circle().strokeBorder(Color(hex: entry.hex), lineWidth: isSelected ? 2 : 0)
                        }
                }
                // .borderless: v řádku Formu reaguje každé tlačítko samostatně
                .buttonStyle(.borderless)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
