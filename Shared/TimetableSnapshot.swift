import Foundation

// Rozvrh studenta – sdíleno aplikací (záložka Rozvrh, akce Siri), widgetem („Další hodina“) i hodinkami.

/// Jedna rozvrhová akce (přednáška, cvičení, seminář…) převedená z IS/STAG.
///
/// Popisuje opakující se nebo jednorázovou akci; konkrétní výskyty v kalendáři vrací
/// `occurrence(on:calendar:)`. Ukládá se jako součást `TimetableSnapshot`.
nonisolated struct TimetableEvent: Codable, Identifiable, Hashable {
    /// Identifikátor akce ve STAGu (pole `roakIdno`).
    let id: String
    /// Kód předmětu, např. „AP9PT“.
    let subjectCode: String
    /// Katedra, např. „AUIUI“.
    let department: String
    /// Název předmětu.
    let subjectName: String
    /// Typ akce slovy („Přednáška“, „Cvičení“, „Seminář“).
    let typeName: String
    /// Zkratka typu („Př“, „Cv“, „Se“).
    let typeShort: String
    /// Den v týdnu 1 = pondělí … 7 = neděle; `nil` = akce bez pevného dne.
    let weekday: Int?
    /// Začátek ve formátu „HH:mm“.
    let startTime: String?
    /// Konec ve formátu „HH:mm“.
    let endTime: String?
    /// Označení budovy, např. „52“.
    let building: String?
    /// Číslo místnosti, např. „202“.
    let room: String?
    /// Vyučující včetně titulů.
    let teacher: String?
    /// Týden výuky ze STAGu: „Každý“, „Sudý“, „Lichý“, „Jiný“.
    let weekParity: String?
    /// Začátek platnosti akce (rozsah semestru).
    let dateFrom: Date?
    /// Konec platnosti akce (rozsah semestru).
    let dateTo: Date?
    /// Den jednorázové akce; je-li vyplněný, akce se koná jen tento den.
    let singleDate: Date?
    /// Barva předmětu z aplikace („#RRGGBB“), pokud předmět v aplikaci existuje.
    var hexColor: String?
}

/// Jeden konkrétní výskyt akce v kalendáři (např. úterý 6. 10. 11:00–13:00).
///
/// Neukládá se – vzniká výpočtem z `TimetableEvent` pro zobrazení v aplikaci, widgetu a akcích Siri.
nonisolated struct TimetableOccurrence: Identifiable, Hashable {
    /// Rozvrhová akce, ke které výskyt patří.
    let event: TimetableEvent
    /// Začátek výskytu.
    let start: Date
    /// Konec výskytu.
    let end: Date
    /// Identifikátor složený z ID akce a začátku výskytu.
    var id: String { "\(event.id)-\(start.timeIntervalSince1970)" }
}

// MARK: - Výpočty nad akcí

nonisolated extension TimetableEvent {
    /// Čas začátku v minutách od půlnoci; `nil` při chybějícím nebo neplatném čase.
    var startMinutes: Int? { Self.minutes(from: startTime) }
    /// Čas konce v minutách od půlnoci; `nil` při chybějícím nebo neplatném čase.
    var endMinutes: Int? { Self.minutes(from: endTime) }

    /// Budova a místnost „52/202“; chybí-li jedna část, jen ta druhá, bez obou `nil`.
    var locationText: String? {
        switch (building?.isEmpty == false ? building : nil, room?.isEmpty == false ? room : nil) {
        case let (building?, room?): return "\(building)/\(room)"
        case let (nil, room?): return room
        case let (building?, nil): return building
        default: return nil
        }
    }

    /// Lokalizovaný text „Sudý týden“ / „Lichý týden“, jinak `nil` (výuka každý týden).
    var parityText: String? {
        switch weekParity {
        case "Sudý": return String(localized: "Sudý týden")
        case "Lichý": return String(localized: "Lichý týden")
        default: return nil
        }
    }

    /// Zjistí, zda se akce koná v daný den.
    ///
    /// Zohlední jednorázové datum, den v týdnu, platnost od–do a sudý/lichý týden (číslo týdne podle ISO 8601).
    /// - Parameters:
    ///   - date: Libovolný okamžik zkoumaného dne.
    ///   - calendar: Kalendář pro výpočet, výchozí je aktuální.
    /// - Returns: `true`, pokud se akce ten den koná.
    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let singleDate {
            return calendar.isDate(singleDate, inSameDayAs: day)
        }
        guard let weekday, Self.weekday(of: day, calendar: calendar) == weekday else { return false }
        if let dateFrom, day < calendar.startOfDay(for: dateFrom) { return false }
        if let dateTo, day > calendar.startOfDay(for: dateTo) { return false }
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: day)
        switch weekParity {
        case "Sudý": return week % 2 == 0
        case "Lichý": return week % 2 == 1
        default: return true
        }
    }

    /// Vytvoří výskyt akce v daný den.
    /// - Parameters:
    ///   - date: Libovolný okamžik požadovaného dne.
    ///   - calendar: Kalendář pro výpočet, výchozí je aktuální.
    /// - Returns: Výskyt se začátkem a koncem, nebo `nil`, pokud se akce ten den nekoná nebo nemá čas.
    func occurrence(on date: Date, calendar: Calendar = .current) -> TimetableOccurrence? {
        guard occurs(on: date, calendar: calendar),
              let startMinutes, let endMinutes else { return nil }
        let day = calendar.startOfDay(for: date)
        // Nastavujeme čas „na hodinách“ – přičítání minut od půlnoci by v den změny času posunulo hodinu o 60 min
        guard let start = calendar.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: day),
              let end = calendar.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: day)
        else { return nil }
        return TimetableOccurrence(event: self, start: start, end: end)
    }

    /// Určí den v týdnu ve formátu 1 = pondělí … 7 = neděle.
    /// - Parameters:
    ///   - date: Zkoumané datum.
    ///   - calendar: Kalendář pro výpočet, výchozí je aktuální.
    /// - Returns: Číslo dne v týdnu 1–7.
    static func weekday(of date: Date, calendar: Calendar = .current) -> Int {
        let sundayBased = calendar.component(.weekday, from: date) // 1 = neděle
        return (sundayBased + 5) % 7 + 1
    }

    /// Převede čas „HH:mm“ na minuty od půlnoci.
    /// - Parameter time: Čas jako text.
    /// - Returns: Počet minut, nebo `nil` při chybějícím nebo neplatném vstupu.
    private static func minutes(from time: String?) -> Int? {
        guard let parts = time?.split(separator: ":"), parts.count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
    }
}

// MARK: - Uložený rozvrh

/// Rozvrh uložený v App Group – aplikace ho zapisuje po načtení ze STAGu, widget ho čte.
///
/// Ukládá se jako JSON pod klíčem `timetableSnapshot.v1`; čtou ho i akce Siri a Zkratek.
nonisolated struct TimetableSnapshot: Codable {
    /// Všechny rozvrhové akce semestru.
    var events: [TimetableEvent]
    /// Semestr: „ZS“ / „LS“.
    var semester: String
    /// Začátek akademického roku, např. „2026“.
    var academicYear: String
    /// Okamžik načtení rozvrhu ze STAGu.
    var fetchedAt: Date

    private static let storageKey = "timetableSnapshot.v1"

    /// Načte uložený rozvrh z App Group.
    /// - Returns: Rozvrh, nebo `nil`, pokud chybí nebo nejde dekódovat.
    static func load() -> TimetableSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(TimetableSnapshot.self, from: data)
    }

    /// Uloží rozvrh do App Group jako JSON (při chybě kódování neudělá nic).
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults?.set(data, forKey: Self.storageKey)
    }

    /// Smaže uložený rozvrh z App Group.
    static func clear() {
        AppGroup.defaults?.removeObject(forKey: storageKey)
    }

    /// Vrátí výskyty všech akcí v daný den.
    /// - Parameters:
    ///   - date: Libovolný okamžik požadovaného dne.
    ///   - calendar: Kalendář pro výpočet, výchozí je aktuální.
    /// - Returns: Výskyty seřazené podle začátku.
    func occurrences(on date: Date, calendar: Calendar = .current) -> [TimetableOccurrence] {
        events.compactMap { $0.occurrence(on: date, calendar: calendar) }.sorted { $0.start < $1.start }
    }

    /// Vrátí nejbližší výskyty od daného okamžiku; probíhající hodina se počítá.
    /// - Parameters:
    ///   - now: Okamžik, od kterého se hledá, výchozí je aktuální čas.
    ///   - limit: Nejvyšší počet vrácených výskytů.
    ///   - daysAhead: Kolik dní po dnešku se nejvýše prohledává.
    ///   - calendar: Kalendář pro výpočet, výchozí je aktuální.
    /// - Returns: Nejvýše `limit` výskytů seřazených chronologicky.
    func upcoming(after now: Date = .now, limit: Int = 5, daysAhead: Int = 14, calendar: Calendar = .current) -> [TimetableOccurrence] {
        var result: [TimetableOccurrence] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0...daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            result += occurrences(on: day, calendar: calendar).filter { $0.end > now }
            if result.count >= limit { break }
        }
        return Array(result.prefix(limit))
    }

    /// Akce bez pevného dne v týdnu i jednorázového data (zobrazují se zvlášť).
    var unscheduledEvents: [TimetableEvent] {
        events.filter { $0.weekday == nil && $0.singleDate == nil }
    }
}

// MARK: - Ukázková data (náhledy, galerie widgetů)

nonisolated extension TimetableSnapshot {
    /// Realistický rozvrh studenta FAI UTB pro náhledy – platí vždy (bez omezení dat).
    ///
    /// Jména vyučujících jsou smyšlená – ukázky se zobrazují i v Release (galerie widgetů, snímky obrazovky).
    static var sample: TimetableSnapshot {
        func event(_ id: String, _ code: String, _ name: String, _ type: String, _ short: String,
                   _ day: Int, _ from: String, _ to: String, _ building: String, _ room: String,
                   _ teacher: String, _ color: String) -> TimetableEvent {
            TimetableEvent(id: id, subjectCode: code, department: "AUIUI", subjectName: name,
                           typeName: type, typeShort: short, weekday: day, startTime: from, endTime: to,
                           building: building, room: room, teacher: teacher, weekParity: "Každý",
                           dateFrom: nil, dateTo: nil, singleDate: nil, hexColor: color)
        }
        return TimetableSnapshot(
            events: [
                event("s1", "AP9PT", "Pokročilé mobilní technologie", "Přednáška", "Př", 2, "12:00", "13:00", "54", "110", "Mgr. Petr Svoboda", "#3E63DD"),
                event("s2", "AP9PT", "Pokročilé mobilní technologie", "Cvičení", "Cv", 2, "10:00", "12:00", "52", "202", "Mgr. Petr Svoboda", "#3E63DD"),
                event("s3", "AP9EV", "Evoluční výpočetní techniky", "Cvičení", "Cv", 1, "08:00", "10:00", "54", "304", "Ing. Martin Horák", "#B8860B"),
                event("s4", "AP9EV", "Evoluční výpočetní techniky", "Přednáška", "Př", 2, "18:00", "20:00", "51", "219", "doc. Ing. Eva Dvořáková, Ph.D.", "#B8860B"),
                event("s5", "AP9DM", "Datamining", "Přednáška", "Př", 3, "09:00", "11:00", "54", "211", "doc. Ing. Karel Procházka, Ph.D.", "#12A594"),
                event("s6", "AP9DM", "Datamining", "Cvičení", "Cv", 4, "13:00", "15:00", "52", "104", "Ing. Tomáš Kučera", "#12A594"),
                event("s7", "AP9BI", "Bezpečnost informačních systémů", "Seminář", "Se", 5, "10:00", "12:00", "53", "309", "Ing. Petra Svobodová", "#E5484D")
            ],
            semester: "ZS",
            academicYear: "2026",
            fetchedAt: .now
        )
    }
}
