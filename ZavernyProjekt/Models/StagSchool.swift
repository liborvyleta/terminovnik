import Foundation

/// Vysoká škola s IS/STAG.
///
/// Aplikace se připojuje k webovým službám zvolené školy (`baseURL`). Kromě předdefinovaných
/// škol (`all`) lze zadat vlastní server (`custom(address:)`). Volba se pamatuje ve `StagSchoolPreference`.
nonisolated struct StagSchool: Codable, Hashable, Identifiable {
    /// Stabilní identifikátor („utb“, „zcu“…; „custom“ = vlastní adresa).
    let id: String
    /// Plný název školy.
    let name: String
    /// Zkratka školy („UTB“).
    let shortName: String
    /// Sídlo školy; u vlastní adresy prázdné.
    let city: String
    /// Adresa webových služeb IS/STAG, např. https://stag-ws.utb.cz/ws.
    let baseURL: URL

    /// Příznak školy zadané vlastní adresou serveru.
    var isCustom: Bool { id == Self.customID }

    /// Celý host serveru (s portem, je-li uvedený) malými písmeny, např. „stag-ws.utb.cz“.
    ///
    /// Zobrazuje se u přihlášení, aby uživatel viděl, komu zadává heslo. Mezinárodní domény jsou v punycode.
    /// Když host nejde zjistit, vrátí celou adresu.
    var displayHost: String {
        let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        guard let host = components?.encodedHost ?? baseURL.host(), !host.isEmpty else {
            return baseURL.absoluteString
        }
        if let port = components?.port { return "\(host.lowercased()):\(port)" }
        return host.lowercased()
    }
}

nonisolated extension StagSchool {
    /// Identifikátor školy zadané vlastní adresou.
    static let customID = "custom"

    /// Školy s ověřenými webovými službami IS/STAG (veřejná služba i přihlášení odpovídají).
    static let all: [StagSchool] = [
        StagSchool(id: "utb", name: "Univerzita Tomáše Bati ve Zlíně", shortName: "UTB", city: "Zlín",
                   baseURL: URL(string: "https://stag-ws.utb.cz/ws")!),
        StagSchool(id: "zcu", name: "Západočeská univerzita v Plzni", shortName: "ZČU", city: "Plzeň",
                   baseURL: URL(string: "https://stag-ws.zcu.cz/ws")!),
        StagSchool(id: "jcu", name: "Jihočeská univerzita v Českých Budějovicích", shortName: "JČU", city: "České Budějovice",
                   baseURL: URL(string: "https://stag-ws.jcu.cz/ws")!),
        StagSchool(id: "tul", name: "Technická univerzita v Liberci", shortName: "TUL", city: "Liberec",
                   baseURL: URL(string: "https://stag-ws.tul.cz/ws")!),
        StagSchool(id: "upce", name: "Univerzita Pardubice", shortName: "UPa", city: "Pardubice",
                   baseURL: URL(string: "https://stag-ws.upce.cz/ws")!),
        StagSchool(id: "uhk", name: "Univerzita Hradec Králové", shortName: "UHK", city: "Hradec Králové",
                   baseURL: URL(string: "https://stagws.uhk.cz/ws")!),
        StagSchool(id: "ujep", name: "Univerzita J. E. Purkyně v Ústí nad Labem", shortName: "UJEP", city: "Ústí nad Labem",
                   baseURL: URL(string: "https://ws.ujep.cz/ws")!)
    ]

    /// Výchozí škola – UTB (původní chování aplikace).
    static var utb: StagSchool { all[0] }

    /// Najde předdefinovanou školu podle identifikátoru.
    /// - Parameter id: Identifikátor školy, např. „utb“.
    /// - Returns: Škola ze seznamu `all`, nebo `nil`, pokud neexistuje.
    static func school(id: String) -> StagSchool? { all.first { $0.id == id } }

    /// Vytvoří vlastní školu z adresy serveru zadané uživatelem.
    ///
    /// Přijme „stag-ws.skola.cz“, „https://stag-ws.skola.cz“
    /// i „https://stag-ws.skola.cz/ws“. Povolené je jen HTTPS.
    /// Jméno a heslo v adrese („https://user:heslo@server“) se zahodí, host se převede na malá písmena,
    /// port zůstává. Cesta se doplní o `/ws`, dotaz a fragment se odstraní. Název i zkratka školy
    /// jsou rovny hostu.
    /// - Parameter address: Adresa serveru zadaná uživatelem.
    /// - Returns: Škola s identifikátorem `customID`, nebo `nil` při prázdné adrese, jiném schématu
    ///   než HTTPS nebo hostu bez tečky.
    static func custom(address: String) -> StagSchool? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Schéma doplníme, jen když v adrese chybí („httpstag.skola.cz“ je název serveru, ne schéma)
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let rawHost = components.host, rawHost.contains(".") else { return nil }
        let host = rawHost.lowercased()
        components.scheme = "https"
        components.user = nil
        components.password = nil
        components.host = host
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/ws") { path += "/ws" }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }
        return StagSchool(id: customID, name: host, shortName: host, city: "", baseURL: url)
    }
}

/// Škola zvolená před přihlášením.
///
/// Ukládá se jako JSON do `UserDefaults.standard` (klíč `stagSelectedSchool.v1`), takže se pamatuje
/// i po zavření aplikace.
enum StagSchoolPreference {
    private static let key = "stagSelectedSchool.v1"

    /// Aktuálně zvolená škola; bez uložené nebo při nečitelné hodnotě vrací UTB.
    static var selected: StagSchool {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let school = try? JSONDecoder().decode(StagSchool.self, from: data) else { return .utb }
            return school
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}
