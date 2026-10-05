import Foundation
import SwiftData

/// Jediný sdílený ModelContainer aplikace.
/// Používá ho aplikace i akce pro Siri a Zkratky (App Intents), které běží bez otevřeného UI.
enum PersistenceController {
    static let shared: ModelContainer = {
        let schema = Schema([Subject.self, ExamTask.self])
        // isStoredInMemoryOnly: false → data se ukládají trvale do SQLite v kontejneru aplikace.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Bez úložiště aplikace nemůže fungovat – chybu chceme vidět hned při vývoji.
            fatalError("Nepodařilo se vytvořit ModelContainer: \(error)")
        }
    }()
}
