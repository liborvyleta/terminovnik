import Foundation

/// Jedna změna rozvrhu zjištěná porovnáním dvou snapshotů.
///
/// Vytváří ji ``TimetableChangeDetector/diff(old:new:now:calendar:horizonDays:)``;
/// ``NotificationManager/notifyTimetableChanges(_:)`` z ní skládá text oznámení
/// a podle ``fingerprint`` brání opakovanému oznámení stejné změny.
nonisolated struct TimetableChange: Hashable {
    /// Druh změny rozvrhu.
    enum Kind: String, Hashable {
        /// Akce zmizela, nebo zmizel některý její nejbližší výskyt
        case cancelled
        /// Stejná akce (roakIdno) má jiný den, čas, místnost nebo týdny
        case moved
        /// Nová akce v rozvrhu
        case added
    }

    /// Druh změny.
    let kind: Kind
    /// Akce před změnou (nil u nové hodiny)
    let old: TimetableEvent?
    /// Akce po změně (nil u zrušené akce)
    let new: TimetableEvent?
    /// Nejbližší dotčený výskyt (u zrušeného výskytu jeho začátek)
    let date: Date?

    /// Dotčená akce – nová podoba, nebo u zrušené akce ta původní.
    /// - Important: Předpokládá, že alespoň jedno z ``old`` a ``new`` je vyplněné.
    var event: TimetableEvent { (new ?? old)! }

    /// Stabilní otisk změny – podle něj se nepošle stejné oznámení dvakrát.
    var fingerprint: String {
        func describe(_ e: TimetableEvent?) -> String {
            guard let e else { return "-" }
            return TimetableChangeDetector.relevantKey(of: e)
        }
        return "\(kind.rawValue)|\(event.id)|\(describe(old))|\(describe(new))|\(date?.timeIntervalSince1970 ?? 0)"
    }
}

/// Porovnání rozvrhů bez vedlejších efektů + formátování textu oznámení.
///
/// Porovnává uložený a nově stažený `TimetableSnapshot` (``TimetableStore``) v horizontu
/// ``horizonDays`` dní a výsledné ``TimetableChange`` převádí na česky lokalizované texty
/// pro ``NotificationManager``. Nic neukládá.
nonisolated enum TimetableChangeDetector {
    /// Kolik dní dopředu nás změny zajímají.
    static let horizonDays = 14

    /// Rozdíl mezi starým a novým rozvrhem.
    /// Bez starého snapshotu nebo při jiném semestru / akademickém roce vrátí prázdné pole.
    /// Ignoruje akce, které už proběhly (nemají žádný budoucí výskyt v horizontu).
    /// Akce se párují podle `id`; změna jen ubytých výskytů ve stejném slotu je zrušení,
    /// jen přibylých výskytů nová hodina, jinak přesun.
    /// - Parameters:
    ///   - old: Předchozí snapshot rozvrhu (nil = zatím žádný).
    ///   - new: Nově načtený snapshot.
    ///   - now: Aktuální okamžik, od kterého se hledají budoucí výskyty.
    ///   - calendar: Kalendář pro výpočet dnů a výskytů.
    ///   - horizonDays: Kolik dní dopředu se změny sledují.
    /// - Returns: Změny seřazené podle druhu (zrušené, přesunuté, nové), pak podle data a `id` akce.
    static func diff(
        old: TimetableSnapshot?,
        new: TimetableSnapshot,
        now: Date = .now,
        calendar: Calendar = .current,
        horizonDays: Int = horizonDays
    ) -> [TimetableChange] {
        guard let old,
              old.semester == new.semester,
              old.academicYear == new.academicYear
        else { return [] }

        let oldByID = Dictionary(old.events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func upcoming(_ event: TimetableEvent) -> [Date] {
            upcomingStarts(of: event, now: now, calendar: calendar, horizonDays: horizonDays)
        }

        var changes: [TimetableChange] = []

        for (id, oldEvent) in oldByID {
            let oldStarts = upcoming(oldEvent)
            guard let newEvent = newByID[id] else {
                // Akce zmizela – zajímá nás jen, pokud se ještě měla konat
                if let first = oldStarts.first {
                    changes.append(TimetableChange(kind: .cancelled, old: oldEvent, new: nil, date: first))
                }
                continue
            }
            guard relevantKey(of: oldEvent) != relevantKey(of: newEvent) else { continue }
            let newStarts = upcoming(newEvent)
            // Změna jen v minulosti nebo mimo horizont → nezajímá
            guard !oldStarts.isEmpty || !newStarts.isEmpty else { continue }

            let sameSlot = slotKey(of: oldEvent) == slotKey(of: newEvent)
            let oldSet = Set(oldStarts), newSet = Set(newStarts)
            if sameSlot, newSet.isSubset(of: oldSet) {
                // Stejný den/čas/místnost, jen ubyly výskyty (např. zkrácená platnost, jiné týdny)
                if let missing = oldStarts.first(where: { !newSet.contains($0) }) {
                    changes.append(TimetableChange(kind: .cancelled, old: oldEvent, new: newEvent, date: missing))
                }
            } else if sameSlot, oldSet.isSubset(of: newSet) {
                // Jen přibyly výskyty – oznámíme jako novou hodinu
                if let extra = newStarts.first(where: { !oldSet.contains($0) }) {
                    changes.append(TimetableChange(kind: .added, old: oldEvent, new: newEvent, date: extra))
                }
            } else {
                changes.append(TimetableChange(kind: .moved, old: oldEvent, new: newEvent, date: newStarts.first ?? oldStarts.first))
            }
        }

        for (id, newEvent) in newByID where oldByID[id] == nil {
            if let first = upcoming(newEvent).first {
                changes.append(TimetableChange(kind: .added, old: nil, new: newEvent, date: first))
            }
        }

        let order: [TimetableChange.Kind: Int] = [.cancelled: 0, .moved: 1, .added: 2]
        return changes.sorted {
            if $0.kind != $1.kind { return order[$0.kind]! < order[$1.kind]! }
            return ($0.date ?? .distantFuture, $0.event.id) < ($1.date ?? .distantFuture, $1.event.id)
        }
    }

    /// Otisk sady změn (seřazený, aby nezáleželo na pořadí).
    /// - Parameter changes: Změny k otisknutí.
    /// - Returns: Otisky jednotlivých změn spojené novým řádkem.
    static func fingerprint(of changes: [TimetableChange]) -> String {
        changes.map(\.fingerprint).sorted().joined(separator: "\n")
    }

    // MARK: - Porovnání

    /// Podstatná pole akce – změna jinde (vyučující, název, barva…) se neoznamuje.
    /// - Parameter e: Akce rozvrhu.
    /// - Returns: Klíč ze slotu, parity týdne a dnů platnosti.
    static func relevantKey(of e: TimetableEvent) -> String {
        let days = [e.dateFrom, e.dateTo, e.singleDate].map { $0.map { String(Int($0.timeIntervalSince1970 / 86_400)) } ?? "-" }
        return "\(slotKey(of: e))|\(normalized(e.weekParity))|\(days.joined(separator: ","))"
    }

    /// Klíč ze dne, času a místa akce.
    /// - Parameter e: Akce rozvrhu.
    /// - Returns: Den v týdnu, začátek, konec, budova a místnost oddělené `|`.
    private static func slotKey(of e: TimetableEvent) -> String {
        "\(e.weekday.map(String.init) ?? "-")|\(e.startMinutes ?? -1)|\(e.endMinutes ?? -1)|\(normalized(e.building))|\(normalized(e.room))"
    }

    /// Normalizuje text pro porovnání (bez okrajových mezer, malými písmeny).
    /// - Parameter s: Vstupní text (nil = prázdný).
    /// - Returns: Normalizovaný text.
    private static func normalized(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Začátky budoucích výskytů (konec po `now`) v příštích `horizonDays` dnech.
    /// - Parameters:
    ///   - event: Akce rozvrhu.
    ///   - now: Aktuální okamžik.
    ///   - calendar: Kalendář pro výpočet dnů.
    ///   - horizonDays: Počet dní dopředu (včetně dneška).
    /// - Returns: Začátky výskytů chronologicky.
    static func upcomingStarts(of event: TimetableEvent, now: Date, calendar: Calendar, horizonDays: Int) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0...horizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let occurrence = event.occurrence(on: day, calendar: calendar),
                  occurrence.end > now
            else { return nil }
            return occurrence.start
        }
    }

    // MARK: - Text oznámení

    /// Nadpis a tělo oznámení. Jedna změna → konkrétní věta, víc změn → souhrn s výpisem (nejvýš 6 položek).
    /// - Parameters:
    ///   - changes: Změny k oznámení.
    ///   - calendar: Kalendář pro formátování dat.
    /// - Returns: Dvojice nadpisu a těla oznámení.
    static func notificationText(for changes: [TimetableChange], calendar: Calendar = .current) -> (title: String, body: String) {
        if changes.count == 1, let change = changes.first {
            return (String(localized: "Změna v rozvrhu"), describe(change, calendar: calendar))
        }
        let body = changes.prefix(6).map { "• " + describe($0, calendar: calendar) }.joined(separator: "\n")
        let more = changes.count > 6 ? "\n" + String(localized: "a další (\(changes.count - 6))") : ""
        return (String(localized: "\(changes.count) změn v rozvrhu"), body + more)
    }

    /// Popis jedné změny, např. „AP9PT přednáška přesunuta z út 9:45 na st 11:30, místnost 52/204“.
    /// - Parameters:
    ///   - change: Popisovaná změna.
    ///   - calendar: Kalendář pro formátování dat.
    /// - Returns: Lokalizovaná věta pro oznámení.
    static func describe(_ change: TimetableChange, calendar: Calendar = .current) -> String {
        let e = change.event
        let name = "\(e.subjectCode) \(e.typeName.lowercased())"
        switch change.kind {
        case .cancelled:
            let when = change.date.map { dateText($0, calendar: calendar) } ?? slotText(change.old ?? e)
            return String(localized: "\(name) zrušena (\(when))")
        case .added:
            let when = change.date.map { dateText($0, calendar: calendar) } ?? slotText(e)
            let room = e.locationText.map { ", " + String(localized: "místnost \($0)") } ?? ""
            return String(localized: "Nová hodina: \(name) \(when)") + room
        case .moved:
            guard let old = change.old, let new = change.new else { return name }
            let timeChanged = old.weekday != new.weekday || old.startMinutes != new.startMinutes
                || old.endMinutes != new.endMinutes || old.singleDate != new.singleDate
            let roomChanged = old.locationText != new.locationText
            var text: String
            if timeChanged {
                text = String(localized: "\(name) přesunuta z \(slotText(old)) na \(slotText(new))")
            } else if roomChanged {
                text = String(localized: "\(name) (\(slotText(new))) v jiné místnosti")
            } else {
                text = String(localized: "\(name) (\(slotText(new))) má změněné týdny výuky")
            }
            if roomChanged, let room = new.locationText {
                text += ", " + String(localized: "místnost \(room)")
            }
            return text
        }
    }

    /// Den a čas akce: „út 9:45“, u jednorázové akce „13. 10. 9:45“.
    /// - Parameter e: Akce rozvrhu.
    /// - Returns: Text dne a času (chybějící části se vynechají).
    static func slotText(_ e: TimetableEvent) -> String {
        let time = e.startTime.map(trimmedTime) ?? ""
        let day: String
        if let single = e.singleDate {
            day = dateOnlyText(single)
        } else {
            day = e.weekday.map(weekdayShort) ?? ""
        }
        return [day, time].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Datum s dnem a časem: „út 13. 10. 9:45“.
    /// - Parameters:
    ///   - date: Formátovaný okamžik.
    ///   - calendar: Kalendář pro rozklad data.
    /// - Returns: Text data.
    static func dateText(_ date: Date, calendar: Calendar = .current) -> String {
        let weekday = weekdayShort(TimetableEvent.weekday(of: date, calendar: calendar))
        let c = calendar.dateComponents([.day, .month, .hour, .minute], from: date)
        return "\(weekday) \(c.day ?? 0). \(c.month ?? 0). \(c.hour ?? 0):\(String(format: "%02d", c.minute ?? 0))"
    }

    /// Jen den a měsíc: „13. 10.“.
    /// - Parameter date: Formátované datum.
    /// - Returns: Text data.
    private static func dateOnlyText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 0). \(c.month ?? 0)."
    }

    /// Lokalizovaná zkratka dne v týdnu.
    /// - Parameter weekday: Den v týdnu 1 = pondělí … 6 = sobota, cokoli jiného = neděle.
    /// - Returns: Zkratka dne („po“, „út“ …).
    static func weekdayShort(_ weekday: Int) -> String {
        switch weekday {
        case 1: String(localized: "po", comment: "Zkratka pondělí")
        case 2: String(localized: "út", comment: "Zkratka úterý")
        case 3: String(localized: "st", comment: "Zkratka středa")
        case 4: String(localized: "čt", comment: "Zkratka čtvrtek")
        case 5: String(localized: "pá", comment: "Zkratka pátek")
        case 6: String(localized: "so", comment: "Zkratka sobota")
        default: String(localized: "ne", comment: "Zkratka neděle")
        }
    }

    /// Odstraní úvodní nulu z času: „09:45“ → „9:45“.
    /// - Parameter time: Čas ve formátu HH:mm.
    /// - Returns: Čas bez úvodní nuly.
    private static func trimmedTime(_ time: String) -> String {
        time.hasPrefix("0") && time.count == 5 ? String(time.dropFirst()) : time
    }
}
