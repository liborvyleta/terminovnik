import Foundation
import SwiftData
import os

/// Jediný sdílený ModelContainer aplikace.
/// Používá ho aplikace i akce pro Siri a Zkratky (App Intents), které běží bez otevřeného UI.
enum PersistenceController {
    /// `true` = trvalé úložiště se nepodařilo otevřít a aplikace běží z úložiště v paměti
    /// (změny se po ukončení ztratí). UI podle toho zobrazí upozornění.
    static private(set) var isUsingFallbackStore = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Terminovnik", category: "persistence")

    static let shared: ModelContainer = {
        let schema = Schema([Subject.self, ExamTask.self])
        // isStoredInMemoryOnly: false → data se ukládají trvale do SQLite v kontejneru aplikace.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memoryConfiguration])
        } catch {
            // Úložiště v paměti se prakticky vždy podaří vytvořit; jinak aplikace opravdu nemůže běžet.
            fatalError("Nepodařilo se vytvořit ani dočasné úložiště: \((error as NSError).code)")
        }
    }()
}
