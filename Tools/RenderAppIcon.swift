// Vygeneruje ikonu aplikace (světlou, tmavou a tónovanou variantu) z AppLogoView.
//
// Spuštění z kořene repozitáře:
//   swiftc -parse-as-library ZavernyProjekt/Views/Components/AppLogoView.swift \
//     Shared/Color+Hex.swift Tools/RenderAppIcon.swift -o /tmp/render-icon
//   /tmp/render-icon ZavernyProjekt/Assets.xcassets/AppIcon.appiconset

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main struct RenderAppIcon {
    @MainActor static func main() {
        guard CommandLine.arguments.count > 1 else {
            print("Použití: render-icon <cílová složka AppIcon.appiconset>")
            return
        }
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        let variants: [(AppLogoView.Variant, String)] = [
            (.light, "AppIcon.png"),
            (.dark, "AppIcon-Dark.png"),
            (.tinted, "AppIcon-Tinted.png")
        ]

        for (variant, fileName) in variants {
            let renderer = ImageRenderer(content: AppLogoView(variant: variant).frame(width: 1024, height: 1024))
            renderer.scale = 1
            guard let image = renderer.cgImage else { fatalError("Vykreslení selhalo") }

            // Ikona nesmí mít alfa kanál – překreslíme do neprůhledného kontextu.
            let context = CGContext(
                data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

            let url = outputDirectory.appendingPathComponent(fileName)
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            CGImageDestinationFinalize(destination)
            print("✓ \(fileName)")
        }
    }
}
