import Foundation
import SwiftData
import os

/// Jediný sdílený ModelContainer aplikace.
///
/// Používá ho aplikace i akce pro Siri a Zkratky (App Intents), které běží bez otevřeného UI.
/// Podle ``DemoMode/isActive`` vrací buď skutečnou databázi SwiftData (SQLite v kontejneru aplikace,
/// volitelně s iCloud synchronizací), nebo demo úložiště v paměti. Přepínání za běhu řídí ``DemoController``.
enum PersistenceController {
    /// `true` = trvalé úložiště se nepodařilo otevřít a aplikace běží z úložiště v paměti
    /// (změny se po ukončení ztratí). UI podle toho zobrazí upozornění.
    static private(set) var isUsingFallbackStore = false

    /// Logger chyb úložiště (jen doména a kód, žádná data)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Terminovnik", category: "persistence")

    /// Schéma SwiftData: předměty a úkoly
    static let schema = Schema([Subject.self, ExamTask.self])

    /// Aktuální úložiště: v ukázkovém režimu demo kontejner v paměti, jinak skutečná databáze.
    /// Díky tomu i App Intents (Siri, Zkratky, tlačítko ve widgetu) v demu pracují jen s demo daty
    /// a skutečnou databázi nezmění.
    static var shared: ModelContainer {
        DemoMode.isActive ? demo : persistent
    }

    /// Demo úložiště v paměti – vzniká při prvním použití v demu, při vstupu/odchodu se zahodí
    private static var demoStorage: ModelContainer?

    /// Demo kontejner; při prvním přístupu ho vytvoří `DemoData.makeContainer(schema:)` a uloží do ``demoStorage``.
    private static var demo: ModelContainer {
        if let demoStorage { return demoStorage }
        let container = DemoData.makeContainer(schema: schema)
        demoStorage = container
        return container
    }

    /// Zahodí demo úložiště (další přístup v demu vytvoří nové, prázdné)
    static func resetDemoContainer() {
        demoStorage = nil
    }

    /// Skutečné trvalé úložiště. V demu se nepoužívá (jen NotificationManager pro akci „Splněno“
    /// u skutečné připomínky, kterou uživatel výslovně potvrdí).
    ///
    /// Otevření se zkusí dvakrát; při neúspěchu vznikne úložiště v paměti a nastaví se ``isUsingFallbackStore``.
    static let persistent: ModelContainer = {
        // isStoredInMemoryOnly: false → data se ukládají trvale do SQLite v kontejneru aplikace.
        // Synchronizace přes iCloud je aktivní jen s compilation flagem ICLOUD_SYNC. Zapnutí dále vyžaduje
        // capability iCloud s CloudKit kontejnerem a Background Modes → Remote notifications
        // (obojí je dostupné jen s placeným vývojářským účtem).
        // Umístění úložiště zůstává výchozí v obou případech.
        #if ICLOUD_SYNC
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic
        #else
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
        #endif
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: cloudKitDatabase)

        // Dva pokusy – první může selhat přechodně (např. soubor dočasně zamčený jiným procesem).
        for attempt in 1...2 {
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // Jen doména a kód chyby, žádné cesty ani obsah dat.
                let nsError = error as NSError
                logger.error("ModelContainer selhal (pokus \(attempt, privacy: .public)): \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            }
        }

        // Záloha: úložiště v paměti – aplikace nespadne, UI upozorní, že se data neukládají.
        // Původní soubor databáze zůstává nedotčený, při dalším spuštění se otevře znovu.
        isUsingFallbackStore = true
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [memoryConfiguration])
        } catch {
            // Úložiště v paměti se prakticky vždy podaří vytvořit; jinak aplikace opravdu nemůže běžet.
            fatalError("Nepodařilo se vytvořit ani dočasné úložiště: \((error as NSError).code)")
        }
    }()
}
