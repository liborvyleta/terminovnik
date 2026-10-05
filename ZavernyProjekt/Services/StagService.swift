import Foundation

// MARK: - Datové typy odpovědí webových služeb IS/STAG
// `nonisolated` = síťová vrstva nepotřebuje hlavní vlákno, typy jdou použít odkudkoli.

/// Předmět tak, jak ho vrací STAG (služby getPredmetyByStudent a getPredmetInfo).
nonisolated struct StagSubject: Decodable, Identifiable, Hashable {
    let katedra: String
    let zkratka: String
    let nazev: String?
    let kreditu: Int?
    let rok: String?

    /// Předmět jednoznačně určuje katedra + zkratka (např. „AUIUI/AP9PT“)
    var id: String { "\(katedra)/\(zkratka)" }

    var displayName: String {
        guard let nazev, !nazev.isEmpty else { return zkratka }
        return nazev
    }

    private enum CodingKeys: String, CodingKey {
        case katedra, zkratka, nazev, kreditu, rok
    }

    init(katedra: String, zkratka: String, nazev: String?, kreditu: Int?, rok: String?) {
        self.katedra = katedra
        self.zkratka = zkratka
        self.nazev = nazev
        self.kreditu = kreditu
        self.rok = rok
    }

    /// Tolerantní dekódování: různé služby STAGu posílají čísla jednou jako číslo, jindy jako text nebo null.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        katedra = try container.decode(String.self, forKey: .katedra)
        zkratka = try container.decode(String.self, forKey: .zkratka)
        nazev = try container.decodeIfPresent(String.self, forKey: .nazev)
        rok = Self.flexibleString(container, .rok)
        kreditu = Self.flexibleString(container, .kreditu).flatMap { Int($0) }
    }

    private static func flexibleString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }
}

/// Aktuální období podle STAGu (služba kalendar/getAktualniObdobiInfo)
nonisolated struct StagPeriod: Decodable {
    /// „ZS“ (zimní) nebo „LS“ (letní)
    let obdobi: String
    /// Začátek akademického roku, „2026“ = akademický rok 2026/2027
    let akademRok: String

    var academicYearTitle: String {
        guard let start = Int(akademRok) else { return akademRok }
        return "\(start)/\(start + 1)"
    }
}

/// Informace o přihlášeném uživateli (parametr stagUserInfo / služba getStagUserListForLoginTicket)
nonisolated struct StagUserInfo: Decodable {
    let jmeno: String?
    let prijmeni: String?
    let stagUserInfo: [Role]?

    struct Role: Decodable, Hashable {
        let userName: String
        /// „ST“ = student, „VY“ = vyučující…
        let role: String
        let fakulta: String?
        /// Osobní číslo studenta (jen u role ST)
        let osCislo: String?
        let aktivni: String?
    }

    /// Studentské role s osobním číslem; aktivní studium má přednost
    var studentRoles: [Role] {
        (stagUserInfo ?? [])
            .filter { $0.role == "ST" && $0.osCislo != nil }
            .sorted { ($0.aktivni == "A" ? 0 : 1) < ($1.aktivni == "A" ? 0 : 1) }
    }

    var fullName: String {
        [jmeno, prijmeni].compactMap { $0 }.joined(separator: " ")
    }
}

/// Chyby komunikace se STAGem – texty se rovnou zobrazují uživateli
nonisolated enum StagError: LocalizedError {
    case invalidCallback
    case anonymousLogin
    case noStudentRole
    case unauthorized
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCallback: "STAG nevrátil přihlašovací údaje. Zkus se přihlásit znovu."
        case .anonymousLogin: "Přihlásil ses jako anonymní uživatel. Pro načtení tvých předmětů se přihlas školním účtem."
        case .noStudentRole: "Účet nemá v IS/STAG roli studenta."
        case .unauthorized: "Přihlášení vypršelo nebo nebylo přijato. Přihlas se znovu."
        case .server(let code): "Server IS/STAG vrátil chybu \(code). Zkus to později."
        case .invalidResponse: "Odpověď ze STAGu se nepodařilo zpracovat."
        }
    }
}

// MARK: - Klient webových služeb

/// Klient REST webových služeb IS/STAG (dokumentace: is-stag.zcu.cz/napoveda/web-services).
///
/// Veřejné služby (detail předmětu s kredity, aktuální semestr) fungují bez přihlášení.
/// Osobní data (zapsané předměty) vyžadují ticket, který aplikace získá přihlášením
/// ve vestavěném prohlížeči – heslo tak aplikace nikdy nevidí. Ticket je dlouhodobý
/// (platí až 90 dní) a `StagAccountStore` ho bezpečně uchovává v Klíčence.
nonisolated struct StagService {
    /// Instance IS/STAG na UTB ve Zlíně. Pro jinou školu stačí změnit adresu.
    static let baseURL = URL(string: "https://stag-ws.utb.cz/ws")!
    /// Vlastní URL schéma, na které STAG po přihlášení přesměruje zpět do aplikace
    static let callbackScheme = "zkousky"

    /// Uživatelský ticket z přihlášení (nil = anonymní volání)
    var ticket: String?
    /// Uživatelské jméno konkrétní role (parametr stagUser) – nutné na školách s přihlášením osoby
    var stagUser: String?
    var session: URLSession = .shared

    init(ticket: String? = nil, stagUser: String? = nil) {
        self.ticket = ticket
        self.stagUser = stagUser
    }

    // MARK: Přihlášení

    /// Adresa přihlašovací stránky. `onlyMainLoginMethod=1` nabídne rovnou školní přihlášení,
    /// `longTicket=1` vydá dlouhodobý ticket (platí až 90 dní), takže se není nutné přihlašovat při každém importu.
    static func loginURL() -> URL {
        let callback = "\(callbackScheme)://stag-login"
        let encodedCallback = callback.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? callback
        var components = URLComponents(url: baseURL.appending(path: "login"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "originalURL", value: encodedCallback),
            URLQueryItem(name: "onlyMainLoginMethod", value: "1"),
            URLQueryItem(name: "longTicket", value: "1")
        ]
        return components.url!
    }

    /// Z návratové adresy `zkousky://stag-login?stagUserTicket=…&stagUserInfo=…` vytáhne ticket
    /// a (pokud je přiložen) Base64 JSON s rolemi uživatele.
    static func parseLoginCallback(_ url: URL) throws -> (ticket: String, info: StagUserInfo?) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let ticket = items.first(where: { $0.name == "stagUserTicket" })?.value,
              !ticket.isEmpty
        else { throw StagError.invalidCallback }

        guard ticket != "anonymous" else { throw StagError.anonymousLogin }

        var info: StagUserInfo?
        if let encoded = items.first(where: { $0.name == "stagUserInfo" })?.value,
           let data = Data(base64Lenient: encoded) {
            info = try? JSONDecoder().decode(StagUserInfo.self, from: data)
        }
        return (ticket, info)
    }

    // MARK: Služby

    /// Aktuální semestr a akademický rok (veřejné)
    func currentPeriod() async throws -> StagPeriod {
        try JSONDecoder().decode(StagPeriod.self, from: await request("kalendar/getAktualniObdobiInfo"))
    }

    /// Detail předmětu včetně kreditů (veřejné)
    func subjectInfo(department: String, code: String, year: String) async throws -> StagSubject {
        let data = try await request("predmety/getPredmetInfo", ["katedra": department, "zkratka": code, "rok": year])
        return try JSONDecoder().decode(StagSubject.self, from: data)
    }

    /// Předměty, které má student zapsané v daném semestru (vyžaduje přihlášení)
    func studentSubjects(osCislo: String, semester: String, year: String) async throws -> [StagSubject] {
        try await list("predmety/getPredmetyByStudent", ["osCislo": osCislo, "semestr": semester, "rok": year])
    }

    /// Role uživatele podle ticketu – záloha, kdyby STAG nepřiložil stagUserInfo do návratové adresy
    func userInfo(forTicket ticket: String) async throws -> StagUserInfo {
        try JSONDecoder().decode(StagUserInfo.self, from: await request("help/getStagUserListForLoginTicket", ["ticket": ticket]))
    }

    // MARK: Síťová vrstva

    private func request(_ path: String, _ parameters: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(
            url: Self.baseURL.appending(path: "services/rest2/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        var items = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "outputFormat", value: "JSON"))
        if let stagUser { items.append(URLQueryItem(name: "stagUser", value: stagUser)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        if let ticket {
            // Ticket se posílá v HTTP Basic jako uživatelské jméno s prázdným heslem (dle dokumentace IS/STAG).
            let credentials = Data("\(ticket):".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StagError.invalidResponse }
        switch http.statusCode {
        case 200: return data
        case 204: return Data()
        case 401, 403: throw StagError.unauthorized
        default: throw StagError.server(http.statusCode)
        }
    }

    /// STAG obaluje seznamy do objektu s jedním klíčem, jehož název se liší podle služby
    /// (např. {"predmetKatedry": […]}). Vezmeme proto první pole, které v odpovědi najdeme.
    /// Položky, které nejdou dekódovat, přeskočíme, aby jedna vadná nerozbila celý seznam.
    private func list<T: Decodable>(_ path: String, _ parameters: [String: String]) async throws -> [T] {
        let data = try await request(path, parameters)
        guard !data.isEmpty else { return [] }

        let object = try JSONSerialization.jsonObject(with: data)
        let array: Any
        if let direct = object as? [Any] {
            array = direct
        } else if let wrapper = object as? [String: Any], let nested = wrapper.values.first(where: { $0 is [Any] }) {
            array = nested
        } else {
            return []
        }

        let arrayData = try JSONSerialization.data(withJSONObject: array)
        return try JSONDecoder().decode([Lossy<T>].self, from: arrayData).compactMap(\.value)
    }
}

/// Obal, který při chybě dekódování vrátí nil místo vyhození výjimky
private nonisolated struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension Data {
    /// Base64 dekódování, které snese chybějící „=“ na konci i URL-safe variantu.
    nonisolated init?(base64Lenient string: String) {
        var normalized = string
            .replacingOccurrences(of: " ", with: "+")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: normalized)
    }
}
