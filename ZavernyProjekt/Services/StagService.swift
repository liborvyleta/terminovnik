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

/// Rozvrhová akce tak, jak ji vrací STAG (rozvrhy/getRozvrhByStudent, getRozvrhByPredmet).
/// Dekóduje se tolerantně – chybějící nebo jinak typovaná pole akci nezahodí.
nonisolated struct StagTimetableAction: Decodable {
    let roakIdno: String?
    let nazev: String?
    let katedra: String?
    let predmet: String?
    let typAkce: String?
    let typAkceZkr: String?
    let den: String?
    let denZkr: String?
    let hodinaSkutOd: String?
    let hodinaSkutDo: String?
    let budova: String?
    let mistnost: String?
    let ucitele: String?
    let tyden: String?
    let datum: String?
    let datumOd: String?
    let datumDo: String?

    private enum CodingKeys: String, CodingKey {
        case roakIdno, nazev, katedra, predmet, typAkce, typAkceZkr, den, denZkr
        case hodinaSkutOd, hodinaSkutDo, budova, mistnost, tyden, datum, datumOd, datumDo
        case vsichniUciteleJmenaTituly
    }

    /// STAG posílá časy a data jako objekt {"value": "11:00"}
    private struct ValueBox: Decodable { let value: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? {
            if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
            if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return String(number) }
            return nil
        }
        func boxed(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(ValueBox.self, forKey: key))??.value ?? text(key)
        }
        roakIdno = text(.roakIdno)
        nazev = text(.nazev)
        katedra = text(.katedra)
        predmet = text(.predmet)
        typAkce = text(.typAkce)
        typAkceZkr = text(.typAkceZkr)
        den = text(.den)
        denZkr = text(.denZkr)
        hodinaSkutOd = boxed(.hodinaSkutOd)
        hodinaSkutDo = boxed(.hodinaSkutDo)
        budova = text(.budova)
        mistnost = text(.mistnost)
        ucitele = text(.vsichniUciteleJmenaTituly)
        tyden = text(.tyden)
        datum = boxed(.datum)
        datumOd = boxed(.datumOd)
        datumDo = boxed(.datumDo)
    }

    /// Převod na sdílený model rozvrhu (nil, pokud chybí kód předmětu)
    func timetableEvent(hexColor: String?) -> TimetableEvent? {
        guard let code = predmet, !code.isEmpty else { return nil }
        let start = hodinaSkutOd
        return TimetableEvent(
            id: roakIdno ?? "\(code)-\(denZkr ?? den ?? "?")-\(start ?? "?")-\(typAkceZkr ?? "")",
            subjectCode: code,
            department: katedra ?? "",
            subjectName: nazev ?? code,
            typeName: typAkce ?? typAkceZkr ?? "Výuka",
            typeShort: typAkceZkr ?? String((typAkce ?? "V").prefix(2)),
            weekday: Self.weekday(from: denZkr ?? den),
            startTime: start,
            endTime: hodinaSkutDo,
            building: budova,
            room: mistnost,
            teacher: ucitele,
            weekParity: tyden,
            dateFrom: Self.date(from: datumOd),
            dateTo: Self.date(from: datumDo),
            singleDate: Self.date(from: datum),
            hexColor: hexColor
        )
    }

    private static func weekday(from text: String?) -> Int? {
        guard let text = text?.lowercased() else { return nil }
        let days = ["po", "út", "st", "čt", "pá", "so", "ne"]
        return days.firstIndex { text.hasPrefix($0) }.map { $0 + 1 }
    }

    /// Datum ve formátu STAGu „16.9.2025“
    private static func date(from text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.timeZone = TimeZone(identifier: "Europe/Prague")
        formatter.dateFormat = "d.M.yyyy"
        return formatter.date(from: text)
    }
}

/// Termín zkoušky pro studenta (služba terminy/getTerminyProStudenta).
/// Názvy polí odpovídají dokumentaci IS/STAG; dekódování je tolerantní k typům i obalům {"value": …}.
nonisolated struct StagExamTerm: Decodable {
    let termIdno: String?
    let predmet: String?
    let katedra: String?
    let datum: String?
    let casOd: String?
    let casDo: String?
    let obsazeni: Int?
    let limit: Int?
    let budova: String?
    let mistnost: String?
    let poznamka: String?
    let opravny: Bool?
    let deadlineDatumPrihlaseni: String?
    let deadlineDatumOdhlaseni: String?
    let zacatekPrihlasovani: String?
    let platnost: String?
    let typTerminu: String?
    let zapsan: Bool?
    let lzeZapsatOdepsat: Bool?
    let duvodNelze: String?
    let ucitel: String?

    private enum CodingKeys: String, CodingKey {
        case termIdno, predmet, katedra, datum, casOd, casDo, obsazeni, limit, budova, mistnost
        case poznamka, opravny, deadlineDatumPrihlaseni, deadlineDatumOdhlaseni, zacatekPrihlasovani
        case platnost, typTerminu, zapsan, lzeZapsatOdepsat, ucitel
        case textDuvoduProcNelzeZapsatOdepsat, popisDuvoduProcNelzeZapsatOdepsat
    }

    private struct ValueBox: Decodable { let value: String? }
    private struct Teacher: Decodable {
        let jmeno: String?
        let prijmeni: String?
        let titulPred: String?
        let titulZa: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? {
            if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value.isEmpty ? nil : value }
            if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return String(number) }
            if let box = (try? c.decodeIfPresent(ValueBox.self, forKey: key)) ?? nil,
               let value = box.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
            return nil
        }
        func number(_ key: CodingKeys) -> Int? {
            if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
            return text(key).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        func flag(_ key: CodingKeys) -> Bool? {
            if let value = try? c.decodeIfPresent(Bool.self, forKey: key) { return value }
            guard let raw = text(key)?.lowercased() else { return nil }
            return ["a", "ano", "true", "1", "y"].contains(raw)
        }
        termIdno = text(.termIdno)
        predmet = text(.predmet)
        katedra = text(.katedra)
        datum = text(.datum)
        casOd = text(.casOd)
        casDo = text(.casDo)
        obsazeni = number(.obsazeni)
        limit = number(.limit)
        budova = text(.budova)
        mistnost = text(.mistnost)
        poznamka = text(.poznamka)
        opravny = flag(.opravny)
        deadlineDatumPrihlaseni = text(.deadlineDatumPrihlaseni)
        deadlineDatumOdhlaseni = text(.deadlineDatumOdhlaseni)
        zacatekPrihlasovani = text(.zacatekPrihlasovani)
        platnost = text(.platnost)
        typTerminu = text(.typTerminu)
        zapsan = flag(.zapsan)
        lzeZapsatOdepsat = flag(.lzeZapsatOdepsat)
        duvodNelze = text(.textDuvoduProcNelzeZapsatOdepsat) ?? text(.popisDuvoduProcNelzeZapsatOdepsat)
        if let teacher = (try? c.decodeIfPresent(Teacher.self, forKey: .ucitel)) ?? nil {
            let name = [teacher.titulPred, teacher.jmeno, teacher.prijmeni].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let full = [name, teacher.titulZa].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            ucitel = full.isEmpty ? nil : full
        } else {
            ucitel = text(.ucitel)
        }
    }

    /// Převod na model aplikace (nil, pokud chybí ID, předmět nebo datum)
    func examTerm() -> ExamTerm? {
        guard let id = termIdno, let code = predmet, let day = StagDateParser.date(datum) else { return nil }
        let start = StagDateParser.combine(day, time: casOd) ?? day
        let end = StagDateParser.combine(day, time: casDo)
        let room: String? = switch (budova, mistnost) {
        case let (b?, m?): "\(b)/\(m)"
        case let (nil, m?): m
        case let (b?, nil): b
        default: nil
        }
        return ExamTerm(
            id: id,
            subjectCode: code,
            department: katedra ?? "",
            typeName: typTerminu.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Termín",
            start: start,
            end: end.flatMap { $0 > start ? $0 : nil },
            room: room,
            teacher: ucitel,
            occupied: obsazeni,
            capacity: limit,
            isRegistered: zapsan ?? false,
            canChangeRegistration: lzeZapsatOdepsat ?? false,
            blockReason: duvodNelze,
            registrationOpens: StagDateParser.date(zacatekPrihlasovani),
            registrationDeadline: StagDateParser.date(deadlineDatumPrihlaseni),
            unregisterDeadline: StagDateParser.date(deadlineDatumOdhlaseni),
            isRetake: opravny ?? false,
            note: poznamka,
            isCancelled: (platnost ?? "A").uppercased() != "A"
        )
    }
}

/// Parsování dat a časů ve formátech, které STAG používá („16.1.2026“, „16.1.2026 23:59“, „09:00“)
nonisolated enum StagDateParser {
    private static let formats = ["d.M.yyyy HH:mm", "d.M.yyyy H:mm", "d.M.yyyy HH:mm:ss", "d.M.yyyy", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]

    static func date(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.timeZone = TimeZone(identifier: "Europe/Prague")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Den + čas „HH:mm“ → konkrétní okamžik
    static func combine(_ day: Date, time: String?) -> Date? {
        guard let parts = time?.split(separator: ":"), parts.count >= 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: day)
    }
}

/// Známky studenta z jednoho předmětu (služba znamky/getZnamkyByStudent, položky „studentNaPredmetu“).
/// Prefix „zk“ = zkouška, „zppzk“ = zápočet / zápočet před zkouškou.
nonisolated struct StagGradeRecord: Decodable {
    let katedra: String?
    let zkratka: String?
    let rok: String?
    let semestr: String?
    let zkHodnoceni: String?
    let zkDatum: String?
    let zkBody: String?
    let zkPokus: String?
    let zkUcitJmeno: String?
    let zppzkHodnoceni: String?
    let zppzkDatum: String?
    let zppzkPokus: String?
    let zppzkUcitJmeno: String?
    let predmetUznany: Bool?
    let stavAbsolvovani: String?

    private enum CodingKeys: String, CodingKey {
        case katedra, zkratka, rok, semestr, zkHodnoceni, zkDatum, zkBody, zkPokus, zkUcitJmeno
        case zppzkHodnoceni, zppzkDatum, zppzkPokus, zppzkUcitJmeno, predmetUznany, stavAbsolvovani
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { StagFlexible.text(c, key) }
        katedra = text(.katedra); zkratka = text(.zkratka); rok = text(.rok); semestr = text(.semestr)
        zkHodnoceni = text(.zkHodnoceni); zkDatum = text(.zkDatum); zkBody = text(.zkBody)
        zkPokus = text(.zkPokus); zkUcitJmeno = text(.zkUcitJmeno)
        zppzkHodnoceni = text(.zppzkHodnoceni); zppzkDatum = text(.zppzkDatum)
        zppzkPokus = text(.zppzkPokus); zppzkUcitJmeno = text(.zppzkUcitJmeno)
        predmetUznany = StagFlexible.flag(c, .predmetUznany); stavAbsolvovani = text(.stavAbsolvovani)
    }

    var exam: GradePart? {
        guard let result = zkHodnoceni else { return nil }
        return GradePart(result: result, date: StagDateParser.date(zkDatum), attempt: zkPokus.flatMap { Int($0) },
                         examiner: zkUcitJmeno, points: zkBody)
    }

    var creditTest: GradePart? {
        guard let result = zppzkHodnoceni else { return nil }
        return GradePart(result: result, date: StagDateParser.date(zppzkDatum), attempt: zppzkPokus.flatMap { Int($0) },
                         examiner: zppzkUcitJmeno, points: nil)
    }
}

/// Předmět studenta s informací o absolvování (služba student/getStudentPredmetyAbsolvoval, položky „predmetAbsolvoval“).
nonisolated struct StagPassedSubject: Decodable {
    let katedra: String?
    let zkratka: String?
    let rok: String?
    let semestr: String?
    let datum: String?
    let absolvoval: Bool?
    let znamka: String?
    let nazevPredmetu: String?
    let pocetKreditu: Int?

    private enum CodingKeys: String, CodingKey {
        case katedra, zkratka, rok, semestr, datum, absolvoval, znamka, nazevPredmetu, pocetKreditu
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        katedra = StagFlexible.text(c, .katedra); zkratka = StagFlexible.text(c, .zkratka)
        rok = StagFlexible.text(c, .rok); semestr = StagFlexible.text(c, .semestr)
        datum = StagFlexible.text(c, .datum); znamka = StagFlexible.text(c, .znamka)
        nazevPredmetu = StagFlexible.text(c, .nazevPredmetu)
        absolvoval = StagFlexible.flag(c, .absolvoval)
        pocetKreditu = StagFlexible.number(c, .pocetKreditu)
    }
}

/// Tolerantní čtení hodnot STAGu: text, číslo, Bool („A“/„N“) i obal {"value": …}
nonisolated enum StagFlexible {
    private struct ValueBox: Decodable { let value: String? }

    static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return String(number) }
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) { return String(number) }
        if let box = (try? c.decodeIfPresent(ValueBox.self, forKey: key)) ?? nil,
           let value = box.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
        return nil
    }

    static func number<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
        return text(c, key).flatMap { Int($0) }
    }

    static func flag<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if let value = try? c.decodeIfPresent(Bool.self, forKey: key) { return value }
        guard let raw = text(c, key)?.lowercased() else { return nil }
        return ["a", "ano", "true", "1", "y"].contains(raw)
    }
}

/// Budova školy (veřejná služba mistnost/getBudovy). Kód `code` odpovídá poli `budova` v rozvrhu.
/// Codable kvůli cache – kódování používá stejné klíče, takže uložená data jdou přečíst stejně jako odpověď STAGu.
nonisolated struct StagBuilding: Codable, Hashable {
    /// Zkratka budovy („52“, „U5“…)
    let code: String
    /// Ulice, často s názvem budovy („U52 - (Severní pavilon B) Nad stráněmi“)
    let street: String?
    /// Číslo popisné („3685“)
    let streetNumber: String?
    let city: String?
    let locality: String?
    /// Zeměpisná šířka (STAG ji vrací jako gpsBudovaX)
    let latitude: Double?
    /// Zeměpisná délka (STAG ji vrací jako gpsBudovaY)
    let longitude: Double?
    /// Provoz od/do ve formátu d.M.yyyy
    let operatingFrom: String?
    let operatingTo: String?

    enum CodingKeys: String, CodingKey {
        case code = "zkrBudovy"
        case street = "ulice"
        case streetNumber = "cisloUlice"
        case city = "obec"
        case locality = "lokalita"
        case latitude = "gpsBudovaX"
        case longitude = "gpsBudovaY"
        case operatingFrom = "provozOd"
        case operatingTo = "provozDo"
    }

    init(code: String, street: String?, streetNumber: String?, city: String?, locality: String? = nil,
         latitude: Double?, longitude: Double?, operatingFrom: String? = nil, operatingTo: String? = nil) {
        self.code = code
        self.street = street
        self.streetNumber = streetNumber
        self.city = city
        self.locality = locality
        self.latitude = latitude
        self.longitude = longitude
        self.operatingFrom = operatingFrom
        self.operatingTo = operatingTo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let code = StagFlexible.text(c, .code) else {
            throw DecodingError.dataCorruptedError(forKey: .code, in: c, debugDescription: "Chybí zkratka budovy")
        }
        self.code = code
        street = StagFlexible.text(c, .street)
        streetNumber = StagFlexible.text(c, .streetNumber)
        city = StagFlexible.text(c, .city)
        locality = StagFlexible.text(c, .locality)
        latitude = Self.coordinate(c, .latitude)
        longitude = Self.coordinate(c, .longitude)
        operatingFrom = StagFlexible.text(c, .operatingFrom)
        operatingTo = StagFlexible.text(c, .operatingTo)
    }

    /// Souřadnice jako číslo i text (s desetinnou čárkou nebo tečkou)
    private static func coordinate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        guard let text = StagFlexible.text(c, key) else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
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
    /// HTTP 401 – ticket vypršel nebo byl zneplatněn (účet se odhlásí)
    case unauthorized
    /// HTTP 403 – přihlášení platí, ale k této službě nebo údajům není oprávnění (účet zůstává)
    case forbidden
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCallback: String(localized: "STAG nevrátil přihlašovací údaje. Zkus se přihlásit znovu.")
        case .anonymousLogin: String(localized: "Přihlásil ses jako anonymní uživatel. Pro načtení tvých předmětů se přihlas školním účtem.")
        case .noStudentRole: String(localized: "Účet nemá v IS/STAG roli studenta.")
        case .unauthorized: String(localized: "Přihlášení vypršelo nebo nebylo přijato. Přihlas se znovu.")
        case .forbidden: String(localized: "IS/STAG k těmto údajům nepovolil přístup. Přihlášení zůstává platné, zkus to později.")
        case .server(let code): String(localized: "Server IS/STAG vrátil chybu \(code). Zkus to později.", comment: "HTTP stavový kód")
        case .invalidResponse: String(localized: "Odpověď ze STAGu se nepodařilo zpracovat.")
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
    /// Adresa webových služeb IS/STAG zvolené školy (např. https://stag-ws.utb.cz/ws)
    let baseURL: URL
    /// Vlastní URL schéma, na které STAG po přihlášení přesměruje zpět do aplikace
    static let callbackScheme = "zkousky"

    /// Uživatelský ticket z přihlášení (nil = anonymní volání)
    var ticket: String?
    /// Uživatelské jméno konkrétní role (parametr stagUser) – nutné na školách s přihlášením osoby
    var stagUser: String?
    var session: URLSession = StagService.urlSession

    /// Sdílená session pro STAG bez trvalé cache a cookies – odpovědi s osobními údaji
    /// (rozvrh, termíny, jméno) se neukládají na disk (`Cache.db`, `Library/Cookies`).
    static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL = StagSchool.utb.baseURL, ticket: String? = nil, stagUser: String? = nil) {
        self.baseURL = baseURL
        self.ticket = ticket
        self.stagUser = stagUser
    }

    // MARK: Přihlášení

    /// Adresa přihlašovací stránky. `onlyMainLoginMethod=1` nabídne rovnou školní přihlášení,
    /// `longTicket=1` vydá dlouhodobý ticket (platí až 90 dní), takže se není nutné přihlašovat při každém importu.
    static func loginURL(baseURL: URL) -> URL {
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

    /// Rozvrh studenta v daném semestru (vyžaduje přihlášení)
    func studentTimetable(osCislo: String, semester: String, year: String) async throws -> [StagTimetableAction] {
        try await list("rozvrhy/getRozvrhByStudent", ["osCislo": osCislo, "semestr": semester, "rok": year])
    }

    /// Termíny zkoušek studenta – zapsané i ty, na které se může zapsat (vyžaduje přihlášení)
    func studentExamTerms(osCislo: String) async throws -> [StagExamTerm] {
        try await list("terminy/getTerminyProStudenta", ["osCislo": osCislo, "lang": "cs"])
    }

    /// Známky studenta ze zápočtů a zkoušek za celé studium (vyžaduje přihlášení)
    func studentGrades(osCislo: String) async throws -> [StagGradeRecord] {
        try await list("znamky/getZnamkyByStudent", ["osCislo": osCislo, "vracetIUznane": "true"])
    }

    /// Předměty studenta s výslednou známkou, kredity a informací o absolvování (vyžaduje přihlášení)
    func studentPassedSubjects(osCislo: String) async throws -> [StagPassedSubject] {
        try await list("student/getStudentPredmetyAbsolvoval", ["osCislo": osCislo])
    }

    /// Rozvrh předmětu (veřejné) – stejná struktura dat, hodí se pro testy
    func subjectTimetable(department: String, code: String, semester: String, year: String) async throws -> [StagTimetableAction] {
        try await list("rozvrhy/getRozvrhByPredmet", ["katedra": department, "zkratka": code, "semestr": semester, "rok": year])
    }

    /// Budovy školy s adresou a GPS (veřejné)
    func buildings() async throws -> [StagBuilding] {
        try await list("mistnost/getBudovy", [:])
    }

    // MARK: Zápis na termíny (OSTRÉ operace – mění data studenta ve STAGu)

    /// Zapíše / odhlásí studenta z termínu nebo z fronty čekatelů (vyžaduje přihlášení).
    ///
    /// Jde o ostrou změnu ve STAGu – volat výhradně po výslovném potvrzení uživatelem.
    /// STAG vrací text „OK“ při úspěchu, jinak text s důvodem neúspěchu.
    /// - Parameters:
    ///   - queueValidUntil: jen pro zápis do fronty – do kdy má zápis ve frontě platit (volitelné)
    func changeTermRegistration(
        _ action: StagTermRegistrationAction,
        osCislo: String,
        termIdno: String,
        lang: String = StagService.preferredLanguage,
        queueValidUntil: Date? = nil
    ) async throws -> StagTermRegistrationResult {
        var parameters = ["osCislo": osCislo, "termIdno": termIdno, "lang": lang]
        if action == .joinQueue, let queueValidUntil {
            parameters["platnostZapisuDo"] = Self.stagDateFormatter.string(from: queueValidUntil)
        }
        let data = try await request(action.path, parameters)
        return StagTermRegistrationResult.parse(data)
    }

    /// Jazyk textů ze STAGu (důvody neúspěchu) podle jazyka aplikace
    static var preferredLanguage: String {
        Locale.current.language.languageCode?.identifier == "cs" ? "cs" : "en"
    }

    /// Datum ve formátu STAGu „d.M.yyyy“
    private static let stagDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.timeZone = TimeZone(identifier: "Europe/Prague")
        formatter.dateFormat = "d.M.yyyy"
        return formatter
    }()

    /// Role uživatele podle ticketu – záloha, kdyby STAG nepřiložil stagUserInfo do návratové adresy
    func userInfo(forTicket ticket: String) async throws -> StagUserInfo {
        try JSONDecoder().decode(StagUserInfo.self, from: await request("help/getStagUserListForLoginTicket", ["ticket": ticket]))
    }

    // MARK: Síťová vrstva

    private func request(_ path: String, _ parameters: [String: String] = [:]) async throws -> Data {
        // Demo režim nikdy nekomunikuje se STAGem
        if DemoMode.isActive { throw URLError(.notConnectedToInternet) }
        var components = URLComponents(
            url: baseURL.appending(path: "services/rest2/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        var items = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "outputFormat", value: "JSON"))
        if let stagUser { items.append(URLQueryItem(name: "stagUser", value: stagUser)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
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
        case 401: throw StagError.unauthorized
        // 403 neznamená vypršené přihlášení – neodhlašujeme, jen ukážeme chybu
        case 403: throw StagError.forbidden
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

// MARK: - Zápis na termíny

/// Změna zápisu na termín zkoušky – odpovídá službám `terminy/…` IS/STAG
nonisolated enum StagTermRegistrationAction: String, CaseIterable, Sendable {
    /// Zápis na termín
    case register
    /// Odhlášení z termínu
    case unregister
    /// Zápis do fronty čekatelů (plný termín)
    case joinQueue
    /// Odhlášení z fronty čekatelů
    case leaveQueue

    /// Cesta služby v REST API IS/STAG
    var path: String {
        switch self {
        case .register: "terminy/zapisStudentaNaTermin"
        case .unregister: "terminy/odhlasStudentaZTerminu"
        case .joinQueue: "terminy/zapisStudentaDoFronty"
        case .leaveQueue: "terminy/odhlasStudentaZFronty"
        }
    }
}

/// Výsledek zápisu/odhlášení: STAG vrací „OK“, jinak text s důvodem neúspěchu.
nonisolated enum StagTermRegistrationResult: Equatable, Sendable {
    case success
    case failure(String)

    /// Rozpozná odpověď – holý text „OK“, JSON řetězec "\"OK\"", případně objekt/pole s jediným textem.
    /// Mezery, uvozovky i velikost písmen se ignorují. Prázdná odpověď = neúspěch s obecnou hláškou.
    static func parse(_ data: Data) -> StagTermRegistrationResult {
        let message = text(from: data)
        if message.caseInsensitiveCompare("OK") == .orderedSame { return .success }
        return .failure(message.isEmpty
            ? String(localized: "STAG změnu nepotvrdil. Zkontroluj stav termínu na portálu IS/STAG.")
            : message)
    }

    /// Text odpovědi bez obalu (JSON řetězec, uvozovky, bílé znaky)
    static func text(from data: Data) -> String {
        if let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let text = firstText(in: decoded) {
            return clean(text)
        }
        return clean(String(decoding: data, as: UTF8.self))
    }

    private static func firstText(in object: Any) -> String? {
        switch object {
        case let text as String: text
        case let array as [Any]: array.lazy.compactMap(firstText).first
        case let dictionary as [String: Any] where dictionary.count == 1: dictionary.values.first.flatMap(firstText)
        default: nil
        }
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
