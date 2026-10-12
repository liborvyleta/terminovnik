import Foundation
import Observation
import CoreLocation
import MapKit

/// Budovy školy z veřejné služby IS/STAG `mistnost/getBudovy` (adresa a GPS).
///
/// - Škola se bere z přihlášeného účtu (``StagAccountStore``), jinak z volby před přihlášením (`StagSchoolPreference`).
/// - Seznam se ukládá do App Group zvlášť pro každou školu a obnovuje se nejvýš jednou za 7 dní.
/// - Souřadnice ze STAGu se přijmou jen uvnitř ČR (některé jsou chybné); jinak se adresa
///   dohledá přes MapKit a výsledek se drží v paměti.
/// - Používají ho detaily hodin a termínů pro zobrazení mapy a adresy.
@Observable
final class BuildingStore {
    /// Sdílená instance používaná celou aplikací.
    static let shared = BuildingStore()

    /// Budovy aktuální školy.
    private(set) var buildings: [StagBuilding] = []
    /// Kdy se seznam naposledy načetl ze STAGu.
    private(set) var fetchedAt: Date?
    /// Zda právě probíhá načítání.
    private(set) var isLoading = false
    /// Škola, ke které patří načtený seznam
    private(set) var school: StagSchool?

    /// Platnost cache
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// Po neúspěšném načtení to znovu nezkoušet hned při každém otevření detailu
    private let retryDelay: TimeInterval = 5 * 60
    /// Čas posledního neúspěchu podle klíče cache školy.
    private var lastFailure: [String: Date] = [:]
    /// Souřadnice dohledané podle adresy (klíč = škola + kód budovy)
    private var geocoded: [String: CLLocationCoordinate2D] = [:]
    /// Budovy, jejichž adresu se dohledat nepodařilo (nezkouší se znovu).
    private var geocodeMisses: Set<String> = []

    /// Uložený seznam budov v App Group.
    private struct Snapshot: Codable {
        var buildings: [StagBuilding]
        var fetchedAt: Date
    }

    /// Soukromý init – používá se jen ``shared``.
    private init() {}

    /// Úložiště cache – App Group, jinak standardní UserDefaults.
    private var defaults: UserDefaults { AppGroup.defaults ?? .standard }

    /// Škola podle přihlášeného účtu, jinak podle volby v aplikaci.
    var currentSchool: StagSchool {
        StagAccountStore.shared.account?.resolvedSchool ?? StagSchoolPreference.selected
    }

    /// Klíč cache budov pro danou školu.
    /// - Parameter school: Škola.
    /// - Returns: Klíč odvozený z adresy STAGu školy.
    private static func cacheKey(for school: StagSchool) -> String {
        "buildings.v1.\(school.baseURL.absoluteString)"
    }

    // MARK: - Načítání

    /// Asynchronně načte budovy aktuální školy z cache, a pokud je starší než 7 dní (nebo chybí), ze STAGu.
    ///
    /// Po neúspěchu další pokus odloží o 5 minut; chyby sítě se nevyhazují, zůstane starší cache.
    /// V ukázkovém režimu nic nedělá.
    func loadIfNeeded() async {
        if DemoMode.isActive { return }
        let school = currentSchool
        if self.school != school { restoreCache(for: school) }

        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge, !buildings.isEmpty { return }
        guard !isLoading else { return }
        let key = Self.cacheKey(for: school)
        if let failure = lastFailure[key], Date.now.timeIntervalSince(failure) < retryDelay { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await StagService(baseURL: school.baseURL).buildings()
            // Mezitím se mohla změnit škola – výsledek pak nepatří k aktuální
            guard currentSchool == school else { return }
            guard !loaded.isEmpty else { lastFailure[key] = .now; return }
            buildings = loaded
            fetchedAt = .now
            self.school = school
            lastFailure[key] = nil
            if let data = try? JSONEncoder().encode(Snapshot(buildings: loaded, fetchedAt: .now)) {
                defaults.set(data, forKey: key)
            }
        } catch {
            // Bez sítě zůstane starší cache – mapa je jen doplněk
            lastFailure[key] = .now
        }
    }

    /// Přepne na školu a načte její budovy z cache (bez cache vyprázdní seznam).
    /// - Parameter school: Škola, jejíž cache se obnoví.
    private func restoreCache(for school: StagSchool) {
        self.school = school
        if let data = defaults.data(forKey: Self.cacheKey(for: school)),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            buildings = snapshot.buildings
            fetchedAt = snapshot.fetchedAt
        } else {
            buildings = []
            fetchedAt = nil
        }
    }

    // MARK: - Dotazy

    /// Budova podle kódu z rozvrhu nebo termínu (bez ohledu na velikost písmen a okrajové mezery).
    /// - Parameter code: Kód budovy.
    /// - Returns: Nalezená budova, nebo nil.
    func building(code: String?) -> StagBuilding? {
        guard let code = code?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
        return buildings.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    /// Souřadnice budovy ze STAGu, jen pokud leží v ČR; jinak dříve dohledaná podle adresy.
    /// - Parameter building: Budova.
    /// - Returns: Souřadnice, nebo nil, pokud nejsou známé.
    func coordinate(for building: StagBuilding) -> CLLocationCoordinate2D? {
        if let latitude = building.latitude, let longitude = building.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            if Self.isInCzechia(coordinate) { return coordinate }
        }
        return geocoded[geocodeKey(building)]
    }

    /// Adresa budovy pro zobrazení („Nad stráněmi 3685, Zlín“).
    /// - Parameter building: Budova.
    /// - Returns: Text adresy, nebo nil.
    func addressText(for building: StagBuilding) -> String? { building.addressText }

    /// Souřadnice budovy; když STAG nemá platné GPS, asynchronně dohledá adresu přes MapKit (jednou za běh aplikace).
    /// - Parameter building: Budova.
    /// - Returns: Souřadnice v ČR, nebo nil, pokud je nejde zjistit.
    func resolveCoordinate(for building: StagBuilding) async -> CLLocationCoordinate2D? {
        if let coordinate = coordinate(for: building) { return coordinate }
        let key = geocodeKey(building)
        guard !geocodeMisses.contains(key), let address = building.addressText else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let found = response.mapItems.lazy
            .map { Self.coordinate(of: $0) }
            .first { Self.isInCzechia($0) }
        if let found {
            geocoded[key] = found
        } else {
            geocodeMisses.insert(key)
        }
        return found
    }

    /// Klíč pro dohledané souřadnice (škola + kód budovy).
    /// - Parameter building: Budova.
    /// - Returns: Klíč do ``geocoded`` a ``geocodeMisses``.
    private func geocodeKey(_ building: StagBuilding) -> String {
        "\(school?.baseURL.absoluteString ?? "")|\(building.code)"
    }

    /// Souřadnice výsledku MapKitu (na iOS 26 přes `location`, dříve přes `placemark`).
    /// - Parameter item: Výsledek vyhledávání.
    /// - Returns: Souřadnice místa.
    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26, *) {
            return item.location.coordinate
        }
        return item.placemark.coordinate
    }

    /// Hrubý obdélník ČR – odfiltruje zjevně chybné souřadnice (např. šířka 42 u Zlína).
    /// - Parameter coordinate: Kontrolované souřadnice.
    /// - Returns: `true`, pokud leží uvnitř obdélníku ČR.
    nonisolated static func isInCzechia(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (48.5...51.1).contains(coordinate.latitude) && (12.0...18.9).contains(coordinate.longitude)
    }
}

// MARK: - Texty budovy

nonisolated extension StagBuilding {
    /// Název budovy z pole ulice: „U52 - (Severní pavilon B) Nad stráněmi“ → „Severní pavilon B“.
    var displayName: String? {
        guard let street,
              let open = street.firstIndex(of: "("),
              let close = street[open...].firstIndex(of: ")") else { return nil }
        let name = street[street.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Samotná ulice bez označení budovy: „U52 - (Severní pavilon B) Nad stráněmi“ → „Nad stráněmi“.
    var streetName: String? {
        guard var text = street else { return nil }
        if let dash = text.range(of: " - ") { text = String(text[dash.upperBound...]) }
        if let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Adresa pro zobrazení z ulice, čísla a města: „Nad stráněmi 3685, Zlín“.
    var addressText: String? {
        let number = streetNumber?.trimmingCharacters(in: .whitespaces)
        let streetPart = [streetName, number].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        let cityPart = city?.trimmingCharacters(in: .whitespaces)
        let parts = [streetPart, cityPart].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Ukázková budova pro náhledy (bez sítě)
    static let sample = StagBuilding(
        code: "52",
        street: "U52 - (Severní pavilon B) Nad stráněmi",
        streetNumber: " 3685",
        city: "Zlín",
        latitude: 49.23057,
        longitude: 17.65715
    )
}

// Ukázkový režim – data jen v paměti, nic se neukládá
extension BuildingStore {
    /// Nastaví ukázkové budovy jen v paměti (nic se neukládá).
    /// - Parameter buildings: Ukázkové budovy.
    func loadDemo(_ buildings: [StagBuilding]) {
        self.buildings = buildings
        fetchedAt = .now
        school = currentSchool
    }

    /// Po ukončení dema zahodí ukázkové budovy – při dalším načtení se obnoví cache skutečné školy.
    func reloadAfterDemo() {
        buildings = []
        fetchedAt = nil
        school = nil
    }
}
