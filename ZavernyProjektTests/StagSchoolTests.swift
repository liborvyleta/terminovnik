import Foundation
import Testing
@testable import ZavernyProjekt

/// Seznam škol s IS/STAG a zadání vlastní adresy serveru.
/// (Uloženou volbu školy – `StagSchoolPreference` – netestujeme, zapisuje do UserDefaults uživatele.)
@Suite("STAG – školy")
struct StagSchoolTests {
    // MARK: - StagSchool.all

    @Test("Školy mají unikátní id a zkratky")
    func uniqueIDs() {
        let ids = StagSchool.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(StagSchool.all.map(\.shortName)).count == ids.count)
        #expect(!ids.contains(StagSchool.customID))
    }

    @Test("Každá škola používá HTTPS a adresa končí /ws")
    func httpsAndWsPath() {
        for school in StagSchool.all {
            #expect(school.baseURL.scheme == "https", "\(school.id)")
            #expect(school.baseURL.path().hasSuffix("/ws"), "\(school.id)")
            #expect(school.baseURL.host()?.contains(".") == true, "\(school.id)")
            #expect(!school.name.isEmpty && !school.city.isEmpty, "\(school.id)")
            #expect(!school.isCustom)
        }
    }

    @Test("Výchozí škola je UTB a dohledání podle id funguje")
    func lookup() {
        #expect(StagSchool.utb.id == "utb")
        #expect(StagSchool.utb.baseURL.absoluteString == "https://stag-ws.utb.cz/ws")
        #expect(StagSchool.school(id: "zcu")?.shortName == "ZČU")
        #expect(StagSchool.school(id: "neexistuje") == nil)
        #expect(StagSchool.school(id: StagSchool.customID) == nil)
    }

    @Test("Škola přežije JSON (pamatuje se mezi spuštěními)")
    func codableRoundTrip() throws {
        let original = try #require(StagSchool.custom(address: "stag-ws.skola.cz"))
        let decoded = try JSONDecoder().decode(StagSchool.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.isCustom)
    }

    // MARK: - StagSchool.custom(address:)

    @Test(
        "Vlastní adresa – doplní https:// a /ws, ořízne lomítka, query a fragment",
        arguments: [
            ("stag-ws.skola.cz", "https://stag-ws.skola.cz/ws"),
            ("  stag-ws.skola.cz \n", "https://stag-ws.skola.cz/ws"),
            ("https://stag-ws.skola.cz", "https://stag-ws.skola.cz/ws"),
            ("https://stag-ws.skola.cz/", "https://stag-ws.skola.cz/ws"),
            ("https://stag-ws.skola.cz/ws", "https://stag-ws.skola.cz/ws"),
            ("https://stag-ws.skola.cz/ws/", "https://stag-ws.skola.cz/ws"),
            ("https://stag-ws.skola.cz/ws///", "https://stag-ws.skola.cz/ws"),
            ("HTTPS://stag-ws.skola.cz/ws", "https://stag-ws.skola.cz/ws"),
            ("stag-ws.skola.cz/ws?lang=cs#login", "https://stag-ws.skola.cz/ws"),
            ("https://stag-ws.skola.cz/ws/?a=1", "https://stag-ws.skola.cz/ws"),
            ("stag.skola.cz/stag/ws", "https://stag.skola.cz/stag/ws"),
            ("stag.skola.cz/api", "https://stag.skola.cz/api/ws"),
            ("stag.skola.cz:8443/ws", "https://stag.skola.cz:8443/ws")
        ]
    )
    func customAddressNormalized(input: String, expected: String) throws {
        let school = try #require(StagSchool.custom(address: input))
        #expect(school.baseURL.absoluteString.lowercased() == expected)
        #expect(school.isCustom)
        #expect(school.id == StagSchool.customID)
    }

    @Test("Vlastní škola se pojmenuje podle serveru")
    func customName() throws {
        let school = try #require(StagSchool.custom(address: "https://stag-ws.skola.cz/ws"))
        #expect(school.name == "stag-ws.skola.cz")
        #expect(school.shortName == "stag-ws.skola.cz")
        #expect(school.city == "")
    }

    @Test(
        "Neplatné adresy se odmítnou",
        arguments: [
            "", "   ", "\n",
            "http://stag-ws.skola.cz", "HTTP://stag-ws.skola.cz/ws", "http://stag-ws.skola.cz/ws",
            "localhost", "https://localhost/ws", "stagws",
            "ftp://stag-ws.skola.cz", "stag ws.skola.cz"
        ]
    )
    func customAddressRejected(input: String) {
        #expect(StagSchool.custom(address: input) == nil)
    }

    @Test("Server, jehož název začíná na „http“, se zadá i bez schématu")
    func customAddressStartingWithHttp() {
        // Název serveru začínající na „http“ nesmí být považován za schéma
        #expect(StagSchool.custom(address: "httpstag.skola.cz")?.baseURL.absoluteString == "https://httpstag.skola.cz/ws")
    }
}
