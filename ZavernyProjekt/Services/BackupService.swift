import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Typ souboru

extension UTType {
    /// Záloha Termínovníku (`.terminovnik`, JSON). Deklarovaná v Info.plist (UTExportedTypeDeclarations).
    static let terminovnikBackup = UTType(exportedAs: "cz.liborvyleta.terminovnik.backup", conformingTo: .json)
}

// MARK: - Formát zálohy

/// Obsah souboru zálohy Termínovníku.
///
/// Obsahuje jen vlastní data uživatele (předměty a úkoly) – nikdy přihlašovací údaje, ticket STAGu
/// ani nic z Klíčenky. Vytváří ho ``BackupService/makeBackup(from:now:)``, serializuje
/// ``BackupService/encode(_:)`` a zpět do SwiftData ho zapisuje ``BackupService/restore(_:into:mode:)``.
nonisolated struct BackupFile: Codable, Equatable {
    /// Verze formátu – novější verzi, než aplikace zná, odmítneme
    static let currentVersion = 1

    /// Verze formátu tohoto souboru.
    var version: Int
    /// Okamžik vytvoření zálohy.
    var createdAt: Date
    /// Verze aplikace (`CFBundleShortVersionString`), která zálohu vytvořila.
    var appVersion: String?
    var subjects: [SubjectRecord]
    var tasks: [TaskRecord]

    /// Vytvoří zálohu z připravených záznamů.
    ///
    /// - Parameters:
    ///   - version: Verze formátu (výchozí ``BackupFile/currentVersion``).
    ///   - createdAt: Okamžik vytvoření zálohy.
    ///   - appVersion: Verze aplikace, která zálohu vytvořila.
    ///   - subjects: Záznamy předmětů.
    ///   - tasks: Záznamy úkolů.
    init(version: Int = BackupFile.currentVersion, createdAt: Date, appVersion: String?,
         subjects: [SubjectRecord], tasks: [TaskRecord]) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.subjects = subjects
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey { case version, createdAt, appVersion, subjects, tasks }

    /// Tolerantní dekódování: chybějící pole dostanou výchozí hodnotu, nečitelné položky se přeskočí.
    ///
    /// U nepodporované verze se předměty a úkoly nedekódují (zůstanou prázdné); verzi kontroluje
    /// až ``BackupService/decode(_:)``.
    ///
    /// - Parameter decoder: Dekodér se vstupními daty.
    /// - Throws: `DecodingError`, pokud chybí nebo je nečitelné pole `version`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        appVersion = try? container.decodeIfPresent(String.self, forKey: .appVersion)
        // Neznámou verzi dál nedekódujeme – struktura může být úplně jiná
        guard version <= Self.currentVersion, version >= 1 else {
            subjects = []
            tasks = []
            return
        }
        subjects = ((try? container.decodeIfPresent([Lenient<SubjectRecord>].self, forKey: .subjects)) ?? nil)?
            .compactMap(\.value) ?? []
        tasks = ((try? container.decodeIfPresent([Lenient<TaskRecord>].self, forKey: .tasks)) ?? nil)?
            .compactMap(\.value) ?? []
    }

    /// Záznam jednoho předmětu v záloze.
    ///
    /// Odpovídá modelu `Subject`; shoda při obnově se určuje podle `id`.
    nonisolated struct SubjectRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var code: String
        var hexColor: String
        var credits: Int
        /// Čas poslední změny – při sloučení vyhrává novější verze záznamu.
        var updatedAt: Date?

        /// Vytvoří záznam předmětu.
        ///
        /// - Parameters:
        ///   - id: Identifikátor předmětu.
        ///   - name: Název předmětu.
        ///   - code: Kód předmětu.
        ///   - hexColor: Barva předmětu v hex zápisu.
        ///   - credits: Počet kreditů.
        ///   - updatedAt: Čas poslední změny.
        init(id: UUID, name: String, code: String, hexColor: String, credits: Int, updatedAt: Date?) {
            self.id = id; self.name = name; self.code = code
            self.hexColor = hexColor; self.credits = credits; self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey { case id, name, code, hexColor, credits, updatedAt }

        /// Tolerantně dekóduje záznam předmětu; chybějící pole dostanou výchozí hodnotu.
        ///
        /// - Parameter decoder: Dekodér se vstupními daty.
        /// - Throws: `DecodingError`, pokud chybí nebo je nečitelné povinné pole `id`.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
            hexColor = (try? c.decodeIfPresent(String.self, forKey: .hexColor)) ?? "#007AFF"
            credits = (try? c.decodeIfPresent(Int.self, forKey: .credits)) ?? 0
            updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }

    /// Záznam jednoho úkolu (zkoušky, deadlinu…) v záloze.
    ///
    /// Odpovídá modelu `ExamTask`; vazbu na předmět drží přes `subjectID`.
    nonisolated struct TaskRecord: Codable, Equatable {
        var id: UUID
        var title: String
        /// rawValue `TaskType` – neznámý typ se při obnově převede na „Úkol“
        var taskType: String
        var dueDate: Date
        var isCompleted: Bool
        var pointsOrGrade: String?
        var note: String
        /// Identifikátor termínu ve STAGu, pokud úkol vznikl ze zapsaného termínu.
        var stagTermID: String?
        /// Identifikátor předmětu (``BackupFile/SubjectRecord/id``), ke kterému úkol patří.
        var subjectID: UUID?
        /// Čas poslední změny – při sloučení vyhrává novější verze záznamu.
        var updatedAt: Date?

        /// Vytvoří záznam úkolu.
        ///
        /// - Parameters:
        ///   - id: Identifikátor úkolu.
        ///   - title: Název úkolu.
        ///   - taskType: rawValue `TaskType`.
        ///   - dueDate: Termín úkolu.
        ///   - isCompleted: Zda je úkol splněný.
        ///   - pointsOrGrade: Body nebo známka.
        ///   - note: Poznámka.
        ///   - stagTermID: Identifikátor termínu ve STAGu.
        ///   - subjectID: Identifikátor předmětu.
        ///   - updatedAt: Čas poslední změny.
        init(id: UUID, title: String, taskType: String, dueDate: Date, isCompleted: Bool, pointsOrGrade: String?,
             note: String, stagTermID: String?, subjectID: UUID?, updatedAt: Date?) {
            self.id = id; self.title = title; self.taskType = taskType; self.dueDate = dueDate
            self.isCompleted = isCompleted; self.pointsOrGrade = pointsOrGrade; self.note = note
            self.stagTermID = stagTermID; self.subjectID = subjectID; self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, taskType, dueDate, isCompleted, pointsOrGrade, note, stagTermID, subjectID, updatedAt
        }

        /// Tolerantně dekóduje záznam úkolu; chybějící nepovinná pole dostanou výchozí hodnotu.
        ///
        /// - Parameter decoder: Dekodér se vstupními daty.
        /// - Throws: `DecodingError`, pokud chybí nebo je nečitelné povinné pole `id` nebo `dueDate`.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            dueDate = try c.decode(Date.self, forKey: .dueDate)
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            taskType = (try? c.decodeIfPresent(String.self, forKey: .taskType)) ?? TaskType.ukol.rawValue
            isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
            pointsOrGrade = try? c.decodeIfPresent(String.self, forKey: .pointsOrGrade)
            note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
            stagTermID = try? c.decodeIfPresent(String.self, forKey: .stagTermID)
            subjectID = try? c.decodeIfPresent(UUID.self, forKey: .subjectID)
            updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }
}

/// Obal, který místo chyby vrátí nil – jedna poškozená položka nezmaří celou obnovu.
///
/// Používá ho ``BackupFile/init(from:)`` při dekódování polí předmětů a úkolů.
nonisolated private struct Lenient<Value: Decodable>: Decodable {
    /// Dekódovaná hodnota, nebo `nil`, pokud položka nešla přečíst.
    let value: Value?
    /// Pokusí se dekódovat hodnotu; chybu nepropaguje.
    ///
    /// - Parameter decoder: Dekodér s daty jedné položky.
    /// - Throws: Nikdy – případná chyba se převede na `nil`.
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

// MARK: - Služba

/// Záloha a obnova vlastních dat do souboru.
///
/// Čisté funkce bez UI, notifikací a widgetu – čtou a zapisují předměty a úkoly ve SwiftData
/// a převádějí je na ``BackupFile`` (JSON). O přeplánování připomínek se stará volající (`BackupRestore`).
/// Obsahuje i úklid duplicit vzniklých synchronizací přes iCloud.
enum BackupService {
    /// Chyby při čtení souboru zálohy.
    nonisolated enum BackupError: LocalizedError, Equatable {
        /// Soubor nejde přečíst nebo to není záloha Termínovníku.
        case corrupted
        /// Záloha má novější verzi formátu, než aplikace zná.
        case unsupportedVersion(Int)

        /// Lokalizovaný popis chyby pro uživatele.
        var errorDescription: String? {
            switch self {
            case .corrupted:
                String(localized: "Soubor se nepodařilo přečíst. Není poškozený nebo to není záloha Termínovníku?")
            case .unsupportedVersion(let version):
                String(localized: "Záloha pochází z novější verze aplikace (formát \(version)). Aktualizuj Termínovník a zkus to znovu.")
            }
        }
    }

    /// Způsob obnovy zálohy.
    enum RestoreMode: Equatable {
        /// Ponechá stávající data; shodné záznamy (UUID) přepíše jen novější verzí
        case merge
        /// Smaže stávající předměty a úkoly a nahradí je zálohou
        case replace
    }

    /// Souhrn provedené obnovy (počty přidaných a aktualizovaných záznamů).
    struct RestoreSummary: Equatable {
        var subjectsAdded = 0
        var subjectsUpdated = 0
        var tasksAdded = 0
        var tasksUpdated = 0
    }

    // MARK: - Export

    /// Vytvoří zálohu všech předmětů a úkolů z databáze.
    ///
    /// - Parameters:
    ///   - context: SwiftData kontext, ze kterého se čtou předměty (podle kódu) a úkoly (podle termínu).
    ///   - now: Okamžik vytvoření zálohy (pro testy).
    /// - Returns: Záloha v aktuální verzi formátu.
    /// - Throws: Chybu SwiftData, pokud se nepodaří načíst předměty nebo úkoly.
    static func makeBackup(from context: ModelContext, now: Date = .now) throws -> BackupFile {
        let subjects = try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.code)]))
        let tasks = try context.fetch(FetchDescriptor<ExamTask>(sortBy: [SortDescriptor(\.dueDate)]))
        return BackupFile(
            createdAt: now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            subjects: subjects.map {
                .init(id: $0.id, name: $0.name, code: $0.code, hexColor: $0.hexColor,
                      credits: $0.credits, updatedAt: $0.updatedAt)
            },
            tasks: tasks.map {
                .init(id: $0.id, title: $0.title, taskType: $0.taskType.rawValue, dueDate: $0.dueDate,
                      isCompleted: $0.isCompleted, pointsOrGrade: $0.pointsOrGrade, note: $0.note,
                      stagTermID: $0.stagTermID, subjectID: $0.subject?.id, updatedAt: $0.updatedAt)
            }
        )
    }

    /// Serializuje zálohu do čitelného JSON (ISO 8601 data, seřazené klíče).
    ///
    /// - Parameter backup: Záloha k serializaci.
    /// - Returns: Data souboru zálohy.
    /// - Throws: `EncodingError`, pokud serializace selže.
    nonisolated static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Načte zálohu z dat souboru a ověří verzi formátu.
    ///
    /// - Parameter data: Obsah souboru zálohy (JSON).
    /// - Returns: Dekódovaná záloha v podporované verzi.
    /// - Throws: ``BackupService/BackupError/corrupted``, pokud data nejdou dekódovat nebo je verze menší než 1;
    ///   ``BackupService/BackupError/unsupportedVersion(_:)``, pokud je verze novější než ``BackupFile/currentVersion``.
    nonisolated static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: BackupFile
        do {
            backup = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.corrupted
        }
        guard backup.version >= 1 else { throw BackupError.corrupted }
        guard backup.version <= BackupFile.currentVersion else {
            throw BackupError.unsupportedVersion(backup.version)
        }
        return backup
    }

    /// Vrátí název souboru zálohy bez přípony, např. „Termínovník-záloha-2026-10-11“.
    ///
    /// - Parameters:
    ///   - date: Datum, které se vloží do názvu.
    ///   - calendar: Kalendář pro rozklad data na rok, měsíc a den.
    /// - Returns: Název souboru ve tvaru `Termínovník-záloha-RRRR-MM-DD`.
    nonisolated static func fileName(for date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "Termínovník-záloha-\(stamp)"
    }

    // MARK: - Obnova

    /// Obnoví předměty a úkoly ze zálohy do databáze.
    ///
    /// V režimu ``BackupService/RestoreMode/replace`` nejdřív smaže všechna stávající data; v režimu
    /// ``BackupService/RestoreMode/merge`` přidá chybějící záznamy a existující (shodné UUID) přepíše jen
    /// novější verzí podle `updatedAt`. Úkoly se navážou na předměty podle `subjectID`.
    ///
    /// - Parameters:
    ///   - backup: Načtená záloha.
    ///   - context: SwiftData kontext, do kterého se zapisuje.
    ///   - mode: Způsob obnovy (sloučení nebo nahrazení).
    /// - Returns: Souhrn přidaných a aktualizovaných záznamů.
    /// - Throws: Chybu SwiftData při načítání nebo ukládání kontextu.
    /// - Note: Ukládá přímo `context.save()`, ne přes `TaskService`, aby se zachovalo `updatedAt` ze zálohy.
    ///   Připomínky musí přeplánovat volající.
    @discardableResult
    static func restore(_ backup: BackupFile, into context: ModelContext, mode: RestoreMode) throws -> RestoreSummary {
        if mode == .replace {
            // Úkoly i předměty mažeme jednotlivě (spolehlivě i s kaskádou vazby)
            for task in try context.fetch(FetchDescriptor<ExamTask>()) { context.delete(task) }
            for subject in try context.fetch(FetchDescriptor<Subject>()) { context.delete(subject) }
        }

        var summary = RestoreSummary()
        func isNewer(_ incoming: Date?, than existing: Date?) -> Bool {
            (incoming ?? .distantPast) > (existing ?? .distantPast)
        }

        let existingSubjects = mode == .replace ? [] : try context.fetch(FetchDescriptor<Subject>())
        var subjectsByID = Dictionary(existingSubjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for record in backup.subjects {
            if let subject = subjectsByID[record.id] {
                guard isNewer(record.updatedAt, than: subject.updatedAt) else { continue }
                apply(record, to: subject)
                summary.subjectsUpdated += 1
            } else {
                let subject = Subject(id: record.id, name: record.name, code: record.code,
                                      hexColor: record.hexColor, credits: record.credits)
                subject.updatedAt = record.updatedAt
                context.insert(subject)
                subjectsByID[record.id] = subject
                summary.subjectsAdded += 1
            }
        }

        let existingTasks = mode == .replace ? [] : try context.fetch(FetchDescriptor<ExamTask>())
        var tasksByID = Dictionary(existingTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for record in backup.tasks {
            let subject = record.subjectID.flatMap { subjectsByID[$0] }
            if let task = tasksByID[record.id] {
                guard isNewer(record.updatedAt, than: task.updatedAt) else { continue }
                apply(record, to: task)
                task.subject = subject
                summary.tasksUpdated += 1
            } else {
                let task = ExamTask(id: record.id, title: record.title,
                                    taskType: TaskType(rawValue: record.taskType) ?? .ukol,
                                    dueDate: record.dueDate, isCompleted: record.isCompleted,
                                    pointsOrGrade: record.pointsOrGrade, note: record.note,
                                    stagTermID: record.stagTermID)
                task.updatedAt = record.updatedAt
                context.insert(task)
                task.subject = subject
                tasksByID[record.id] = task
                summary.tasksAdded += 1
            }
        }

        // Bez TaskService.save – ten by přepsal updatedAt na „teď“ a změnil by pořadí verzí
        try context.save()
        return summary
    }

    /// Přepíše vlastnosti existujícího předmětu hodnotami ze zálohy.
    ///
    /// - Parameters:
    ///   - record: Záznam předmětu ze zálohy.
    ///   - subject: Předmět v databázi, který se aktualizuje.
    private static func apply(_ record: BackupFile.SubjectRecord, to subject: Subject) {
        subject.name = record.name
        subject.code = record.code
        subject.hexColor = record.hexColor
        subject.credits = record.credits
        subject.updatedAt = record.updatedAt
    }

    /// Přepíše vlastnosti existujícího úkolu hodnotami ze zálohy (bez vazby na předmět).
    ///
    /// - Parameters:
    ///   - record: Záznam úkolu ze zálohy; neznámý typ se převede na „Úkol“.
    ///   - task: Úkol v databázi, který se aktualizuje.
    private static func apply(_ record: BackupFile.TaskRecord, to task: ExamTask) {
        task.title = record.title
        task.taskType = TaskType(rawValue: record.taskType) ?? .ukol
        task.dueDate = record.dueDate
        task.isCompleted = record.isCompleted
        task.pointsOrGrade = record.pointsOrGrade
        task.note = record.note
        task.stagTermID = record.stagTermID
        task.updatedAt = record.updatedAt
    }

    // MARK: - Duplicity (synchronizace přes iCloud)

    /// Odstraní duplicity, které vzniknou, když STAG import proběhne na dvou zařízeních se synchronizací.
    ///
    /// Duplicitou jsou předměty se shodným kódem (bez ohledu na velikost písmen) a úkoly se shodným `stagTermID`.
    /// Ponechá záznam s nejmenším UUID (deterministicky na všech zařízeních; u úkolů má přednost splněný),
    /// úkoly duplicitních předmětů přesune k ponechanému. Kontext uloží jen při nějaké změně.
    ///
    /// - Parameter context: SwiftData kontext s předměty a úkoly.
    /// - Returns: Počet odstraněných záznamů.
    /// - Throws: Chybu SwiftData při načítání nebo ukládání kontextu.
    @discardableResult
    static func removeStagDuplicates(in context: ModelContext) throws -> Int {
        var removed = 0
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        for (_, group) in Dictionary(grouping: subjects.filter { !$0.code.isEmpty }, by: { $0.code.uppercased() })
        where group.count > 1 {
            let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
            let keep = sorted[0]
            for duplicate in sorted.dropFirst() {
                for task in duplicate.taskList { task.subject = keep }
                context.delete(duplicate)
                removed += 1
            }
        }
        let tasks = try context.fetch(FetchDescriptor<ExamTask>()).filter { $0.stagTermID != nil }
        for (_, group) in Dictionary(grouping: tasks, by: { $0.stagTermID ?? "" }) where group.count > 1 {
            // Přednost má splněný úkol (uživatel ho odškrtl), pak deterministicky podle UUID
            let sorted = group.sorted {
                if $0.isCompleted != $1.isCompleted { return $0.isCompleted }
                return $0.id.uuidString < $1.id.uuidString
            }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                removed += 1
            }
        }
        if removed > 0 { try context.save() }
        return removed
    }
}

// MARK: - Dokument pro fileExporter

/// Obal zálohy pro `fileExporter`/`fileImporter`.
///
/// Obsahuje již serializovaná data z ``BackupService/encode(_:)``; jejich dekódování a kontrolu verze
/// provádí ``BackupService/decode(_:)``.
struct BackupDocument: FileDocument {
    /// Podporované typy souborů: záloha Termínovníku a obecný JSON.
    static var readableContentTypes: [UTType] { [.terminovnikBackup, .json] }

    /// Serializovaný obsah zálohy (JSON).
    var data: Data

    /// Vytvoří dokument z již serializovaných dat.
    ///
    /// - Parameter data: Obsah souboru zálohy.
    init(data: Data) { self.data = data }

    /// Načte dokument ze souboru vybraného uživatelem.
    ///
    /// - Parameter configuration: Konfigurace čtení s obalem souboru.
    /// - Throws: ``BackupService/BackupError/corrupted``, pokud soubor nemá čitelný obsah.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupService.BackupError.corrupted }
        self.data = data
    }

    /// Vytvoří obal souboru pro uložení zálohy.
    ///
    /// - Parameter configuration: Konfigurace zápisu (nevyužívá se).
    /// - Returns: Obal běžného souboru s daty zálohy.
    /// - Throws: Nevyhazuje; signaturu vyžaduje `FileDocument`.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
