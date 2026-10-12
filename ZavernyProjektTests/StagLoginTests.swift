import Foundation
import Testing
@testable import ZavernyProjekt

/// Testy přihlášení do IS/STAG.
///
/// Ověřují sestavení přihlašovací adresy, zpracování návratové adresy a dekódování Base64 s rolemi.
/// Nic se neposílá po síti a nic se neukládá do Klíčenky.
@Suite("STAG – přihlášení")
struct StagLoginTests {
    private let userInfoJSON = """
    {"jmeno":"Jan","prijmeni":"Novák","stagUserInfo":[
      {"userName":"vy1","role":"VY","fakulta":"FAI","osCislo":null,"aktivni":"A"},
      {"userName":"st1","role":"ST","fakulta":"FAI","osCislo":"A1","aktivni":"N"},
      {"userName":"st2","role":"ST","fakulta":"FAI","osCislo":"A2","aktivni":"A"}
    ]}
    """

    private var standardBase64: String { Data(userInfoJSON.utf8).base64EncodedString() }

    /// Sestaví návratovou adresu přihlášení s daným dotazem.
    ///
    /// - Parameter query: Část adresy za otazníkem.
    /// - Returns: Adresa `zkousky://stag-login?…`.
    private func callback(_ query: String) -> URL {
        URL(string: "zkousky://stag-login?\(query)")!
    }

    /// Zakóduje text procentovým kódováním; ponechá jen písmena, číslice a znaky `-._~`.
    ///
    /// - Parameter value: Text ke kódování.
    /// - Returns: Zakódovaný text.
    private func percentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    // MARK: - parseLoginCallback

    @Test("Ticket bez informací o uživateli")
    func ticketOnly() throws {
        let result = try StagService.parseLoginCallback(callback("stagUserTicket=abc123XYZ"))
        #expect(result.ticket == "abc123XYZ")
        #expect(result.info == nil)
    }

    @Test("Ticket + stagUserInfo v Base64 s paddingem")
    func ticketWithPaddedInfo() throws {
        #expect(standardBase64.hasSuffix("="), "Fixture má mít padding, aby test něco ověřoval")
        let url = callback("stagUserTicket=t1&stagUserInfo=\(percentEncoded(standardBase64))")
        let result = try StagService.parseLoginCallback(url)
        #expect(result.ticket == "t1")
        let info = try #require(result.info)
        #expect(info.fullName == "Jan Novák")
        #expect(info.studentRoles.map(\.userName) == ["st2", "st1"])
        #expect(info.studentRoles.first?.osCislo == "A2")
    }

    @Test("Base64 bez paddingu i URL-safe varianta")
    func ticketWithUnpaddedInfo() throws {
        let unpadded = standardBase64.replacingOccurrences(of: "=", with: "")
        let unpaddedResult = try StagService.parseLoginCallback(
            callback("stagUserTicket=t1&stagUserInfo=\(percentEncoded(unpadded))")
        )
        #expect(unpaddedResult.info?.fullName == "Jan Novák")

        let urlSafe = unpadded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let urlSafeResult = try StagService.parseLoginCallback(callback("stagUserTicket=t1&stagUserInfo=\(urlSafe)"))
        #expect(urlSafeResult.info?.studentRoles.count == 2)
    }

    @Test("Poškozené stagUserInfo přihlášení nezablokuje – ticket projde, info je nil")
    func invalidInfoIsIgnored() throws {
        let garbage = try StagService.parseLoginCallback(callback("stagUserTicket=t1&stagUserInfo=%21%21%21"))
        #expect(garbage.ticket == "t1")
        #expect(garbage.info == nil)

        let notJSON = Data("není to JSON".utf8).base64EncodedString()
        let wrongPayload = try StagService.parseLoginCallback(callback("stagUserTicket=t1&stagUserInfo=\(percentEncoded(notJSON))"))
        #expect(wrongPayload.info == nil)
    }

    @Test("Anonymní přihlášení je chyba")
    func anonymousLogin() {
        let error = #expect(throws: StagError.self) {
            try StagService.parseLoginCallback(callback("stagUserTicket=anonymous"))
        }
        guard case .anonymousLogin? = error else {
            Issue.record("Čekal jsem StagError.anonymousLogin, přišlo \(String(describing: error))")
            return
        }
    }

    @Test(
        "Chybějící nebo prázdný ticket je chyba invalidCallback",
        arguments: ["", "stagUserInfo=abc", "stagUserTicket=", "jinyParametr=1"]
    )
    func missingTicket(query: String) {
        let url = query.isEmpty ? URL(string: "zkousky://stag-login")! : callback(query)
        let error = #expect(throws: StagError.self) {
            try StagService.parseLoginCallback(url)
        }
        guard case .invalidCallback? = error else {
            Issue.record("Čekal jsem StagError.invalidCallback, přišlo \(String(describing: error))")
            return
        }
    }

    @Test("Chyby mají text pro uživatele")
    func errorDescriptions() {
        let errors: [StagError] = [.invalidCallback, .anonymousLogin, .noStudentRole, .unauthorized, .forbidden, .server(500), .invalidResponse]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty, "\(error)")
        }
        #expect(StagError.server(503).errorDescription?.contains("503") == true)
    }

    // MARK: - StagUserInfo

    @Test("Studentské role: jen ST s osobním číslem, aktivní první")
    func studentRoles() throws {
        let info = try decodeJSON(StagUserInfo.self, userInfoJSON)
        #expect(info.studentRoles.map(\.osCislo) == ["A2", "A1"])
        #expect(info.studentRoles.allSatisfy { $0.role == "ST" })

        let teacherOnly = try decodeJSON(StagUserInfo.self, #"{"jmeno":"Eva","stagUserInfo":[{"userName":"vy","role":"VY"}]}"#)
        #expect(teacherOnly.studentRoles.isEmpty)
        #expect(teacherOnly.fullName == "Eva")

        let empty = try decodeJSON(StagUserInfo.self, "{}")
        #expect(empty.studentRoles.isEmpty)
        #expect(empty.fullName == "")
    }

    // MARK: - Data(base64Lenient:)

    @Test("Base64 s paddingem, bez něj a URL-safe")
    func base64Lenient() throws {
        #expect(Data(base64Lenient: "SGVsbG8=") == Data("Hello".utf8))
        #expect(Data(base64Lenient: "SGVsbG8") == Data("Hello".utf8))
        #expect(Data(base64Lenient: "SGVsbA") == Data("Hell".utf8))
        #expect(Data(base64Lenient: "SGVsbA==") == Data("Hell".utf8))
        // 0xFB 0xFF = „+/8=“ ve standardní, „-_8“ v URL-safe variantě
        #expect(Data(base64Lenient: "+/8=") == Data([0xFB, 0xFF]))
        #expect(Data(base64Lenient: "-_8") == Data([0xFB, 0xFF]))
        // „+“ převedené někde po cestě na mezeru
        #expect(Data(base64Lenient: " /8") == Data([0xFB, 0xFF]))
    }

    @Test("Neplatné Base64 vrátí nil, prázdné prázdná data")
    func base64LenientInvalid() {
        #expect(Data(base64Lenient: "@@@@") == nil)
        #expect(Data(base64Lenient: "A") == nil)
        #expect(Data(base64Lenient: "") == Data())
    }

    // MARK: - loginURL

    @Test("Přihlašovací adresa obsahuje návratovou adresu, hlavní metodu a dlouhý ticket")
    func loginURL() throws {
        let url = StagService.loginURL(baseURL: StagSchool.utb.baseURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "stag-ws.utb.cz")
        #expect(components.path == "/ws/login")

        let items = components.queryItems ?? []
        /// Najde hodnotu parametru dotazu podle názvu.
        ///
        /// - Parameter name: Název parametru.
        /// - Returns: Hodnota prvního parametru s tímto názvem, nebo `nil`.
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("originalURL") == "\(StagService.callbackScheme)://stag-login")
        #expect(value("onlyMainLoginMethod") == "1")
        #expect(value("longTicket") == "1")
        #expect(items.count == 3)

        // Návratová adresa musí být zakódovaná, jinak by se její „:“ a „/“ míchaly s adresou serveru
        #expect(url.absoluteString.contains("originalURL=zkousky%3A%2F%2Fstag"))
    }

    @Test("Přihlašovací adresa pro vlastní školu s delší cestou")
    func loginURLCustomPath() throws {
        let school = try #require(StagSchool.custom(address: "stag.skola.cz/stag/ws"))
        let url = StagService.loginURL(baseURL: school.baseURL)
        #expect(url.host() == "stag.skola.cz")
        #expect(url.path() == "/stag/ws/login")
    }

    @Test("Návratová adresa z loginURL projde zpět přes parseLoginCallback")
    func loginRoundTrip() throws {
        let login = StagService.loginURL(baseURL: StagSchool.utb.baseURL)
        let original = try #require(
            URLComponents(url: login, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "originalURL" }?.value
        )
        // STAG po přihlášení připojí ticket k původní adrese
        let returned = try #require(URL(string: original + "?stagUserTicket=xyz"))
        #expect(returned.scheme == StagService.callbackScheme)
        #expect(try StagService.parseLoginCallback(returned).ticket == "xyz")
    }
}
