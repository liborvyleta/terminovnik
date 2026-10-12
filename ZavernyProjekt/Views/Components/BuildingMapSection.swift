import SwiftUI
import MapKit
import CoreLocation

/// Sekce „Kde“ pro List/Form: budova a místnost, malá mapa se značkou a tlačítko „Navigovat“.
///
/// Bez kódu budovy se nezobrazí nic. Adresa a GPS pocházejí z `BuildingStore` (veřejná služba
/// STAGu `mistnost/getBudovy`); když STAG nemá platné souřadnice, adresa se dohledá v MapKitu.
/// Klepnutím na „Navigovat“ uživatel otevře pěší trasu v Apple Mapách; když chybí i adresa,
/// otevře se v Mapách vyhledávání „<škola> budova <kód>“. Používá se v detailu rozvrhové akce
/// (`TimetableEventDetailView`) a v detailu zkouškového termínu (`ExamTermDetailView`).
struct BuildingMapSection: View {
    /// Kód budovy ze STAGu (oříznutý o mezery), `nil` = sekce se nezobrazí.
    let buildingCode: String?
    /// Označení místnosti (oříznuté o mezery).
    let room: String?

    /// Budova dodaná přímo (náhledy) – nenačítá se ze STAGu.
    private let fixedBuilding: StagBuilding?

    /// Akce prostředí pro otevření URL (Apple Mapy bez souřadnic).
    @Environment(\.openURL) private var openURL
    /// Souřadnice dohledané asynchronně přes `BuildingStore.resolveCoordinate(for:)`.
    @State private var resolvedCoordinate: CLLocationCoordinate2D?

    /// Vytvoří sekci, která budovu načte ze STAGu podle kódu.
    /// - Parameters:
    ///   - buildingCode: kód budovy, `nil` nebo prázdný = sekce se nezobrazí
    ///   - room: označení místnosti, případně `nil`
    init(buildingCode: String?, room: String?) {
        self.buildingCode = buildingCode?.trimmingCharacters(in: .whitespaces)
        self.room = room?.trimmingCharacters(in: .whitespaces)
        self.fixedBuilding = nil
    }

    /// Pro náhledy a testy: budova bez načítání ze sítě.
    /// - Parameters:
    ///   - building: budova s adresou a souřadnicemi
    ///   - room: označení místnosti, případně `nil`
    init(building: StagBuilding, room: String?) {
        self.buildingCode = building.code
        self.room = room
        self.fixedBuilding = building
    }

    /// Sdílené úložiště budov (`BuildingStore.shared`).
    private var store: BuildingStore { BuildingStore.shared }

    /// Neprázdný kód budovy, jinak `nil`.
    private var code: String? {
        guard let buildingCode, !buildingCode.isEmpty else { return nil }
        return buildingCode
    }

    /// Budova: pevně dodaná, nebo vyhledaná ve `BuildingStore` podle kódu.
    private var building: StagBuilding? {
        fixedBuilding ?? store.building(code: code)
    }

    /// Souřadnice budovy: uložené ve STAGu, jinak dohledané přes MapKit.
    private var coordinate: CLLocationCoordinate2D? {
        // Kontrola rozsahu ČR je v BuildingStore
        if let building, let stored = store.coordinate(for: building) { return stored }
        return resolvedCoordinate
    }

    /// Sekce s řádkem budovy, místností, mapkou a tlačítkem „Navigovat“; v `.task` načte budovy
    /// a dohledá souřadnice (jen když budova není dodaná pevně).
    var body: some View {
        if let code {
            Section("Kde") {
                titleRow(code: code)

                if let room, !room.isEmpty {
                    LabeledContent("Místnost", value: room)
                }

                if let coordinate {
                    mapPreview(coordinate)
                        .listRowInsets(EdgeInsets())
                }

                Button(action: navigate) {
                    Label("Navigovat", systemImage: "figure.walk")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityHint(Text("Otevře pěší trasu k budově v Apple Mapách"))
            }
            .task(id: code) {
                guard fixedBuilding == nil else { return }
                await store.loadIfNeeded()
                if let building = store.building(code: code) {
                    resolvedCoordinate = await store.resolveCoordinate(for: building)
                }
            }
        }
    }

    // MARK: - Řádky

    /// Řádek s ikonou budovy, názvem a podtitulkem (adresa, případně „Načítám adresu…“).
    /// - Parameter code: kód budovy.
    /// - Returns: řádek sloučený pro VoiceOver do jednoho prvku.
    private func titleRow(code: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(code: code))
                    .font(.body.weight(.semibold))
                if let subtitle = subtitle(code: code) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if store.isLoading && fixedBuilding == nil {
                    Text("Načítám adresu…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Malá neinteraktivní mapa se značkou budovy.
    /// - Parameter coordinate: poloha budovy.
    /// - Returns: mapa vysoká 170 bodů bez ovládacích prvků.
    private func mapPreview(_ coordinate: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 700))) {
            Marker(title(code: code ?? ""), systemImage: "building.2.fill", coordinate: coordinate)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Malá mapa v seznamu jen ukazuje polohu – posun by se pletl s rolováním seznamu
        .allowsHitTesting(false)
        .frame(height: 170)
        .id("\(coordinate.latitude),\(coordinate.longitude)")
        .accessibilityLabel(Text("Mapa s polohou budovy"))
    }

    // MARK: - Texty

    /// Název budovy: „Severní pavilon B“, jinak „Budova 52“.
    /// - Parameter code: kód budovy.
    /// - Returns: zobrazovaný název budovy.
    private func title(code: String) -> String {
        building?.displayName ?? String(localized: "Budova \(code)", comment: "Kód budovy školy")
    }

    /// Podtitulek „Budova 52 · Nad stráněmi 3685, Zlín“ (kód jen tehdy, když má budova vlastní název).
    /// - Parameter code: kód budovy.
    /// - Returns: podtitulek, nebo `nil`, když budova není známá nebo nemá co ukázat.
    private func subtitle(code: String) -> String? {
        guard let building else { return nil }
        let codeText = String(localized: "Budova \(code)", comment: "Kód budovy školy")
        let parts = [building.displayName != nil ? codeText : nil, building.addressText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Navigace

    /// Otevře pěší trasu v Apple Mapách – podle souřadnic, jinak podle adresy
    /// nebo vyhledáním „<škola> budova <kód>“.
    private func navigate() {
        let name = title(code: code ?? "")
        if let coordinate {
            let item: MKMapItem
            if #available(iOS 26, *) {
                item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
            } else {
                item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            }
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            return
        }

        // Bez souřadnic: pěší trasa na adresu, případně na „<škola> budova <kód>“
        let query = building?.addressText
            ?? String(localized: "\(store.currentSchool.name) budova \(code ?? "")", comment: "Vyhledání budovy v Mapách: název školy a kód budovy")
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: query),
            URLQueryItem(name: "dirflg", value: "w")
        ]
        if let url = components.url { openURL(url) }
    }
}

#Preview("Budova s mapou") {
    List {
        BuildingMapSection(building: .sample, room: "206")
    }
}

#Preview("Bez kódu budovy") {
    List {
        Section("Předmět") { Text("Bez budovy se sekce nezobrazí") }
        BuildingMapSection(buildingCode: nil, room: "A1")
    }
}
