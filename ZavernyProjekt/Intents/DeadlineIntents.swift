import AppIntents
import Foundation
import SwiftData
import SwiftUI

// Akce nad deadliny (SwiftData). Běží bez otevření aplikace přes sdílený `PersistenceController`.

/// „Nejbližší zkouška“ – nejbližší nesplněný termín (volitelně jen určitého typu) s odpočtem.
struct NextExamIntent: AppIntent {
    static let title: LocalizedStringResource = "Nejbližší zkouška"
    static let description = IntentDescription("Řekne nejbližší nesplněný termín – zkoušku, zápočet, projekt nebo úkol – a kolik zbývá času.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Typ", default: .vse)
    var kind: DeadlineFilter

    static var parameterSummary: some ParameterSummary {
        Summary("Nejbližší termín typu \(\.$kind)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let filterType = kind.taskType
        let task = IntentStore.upcomingTasks().first { task in
            filterType == nil || task.taskType == filterType
        }

        guard let task else {
            return .result(
                dialog: "\(kind.emptyText)",
                view: DeadlineSnippetView(header: kind.headline, item: nil, emptyText: kind.emptyText)
            )
        }

        let item = DeadlineSnippetItem(task: task)
        let headline = kind == .vse ? "\(kind.headline) (\(task.taskType.title))" : kind.headline
        var sentence = "\(headline): \(task.title)"
        if let code = task.subject?.code, !code.isEmpty {
            sentence += " (\(code))"
        }
        sentence += ", \(task.dueDate.deadlineFormatted) – \(IntentText.lowercasedFirst(item.countdown))."

        return .result(
            dialog: "\(sentence)",
            view: DeadlineSnippetView(header: kind.headline, item: item, emptyText: "")
        )
    }
}

/// „Přidat deadline“ – vytvoří novou povinnost u předmětu a naplánuje k ní připomínku.
struct AddDeadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Přidat deadline"
    static let description = IntentDescription("Přidá zkoušku, zápočet, projekt nebo úkol k předmětu a naplánuje připomínku den předem.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Název", requestValueDialog: "Jak se deadline jmenuje?")
    var name: String

    @Parameter(title: "Předmět", requestValueDialog: "Ke kterému předmětu?")
    var subject: SubjectEntity

    @Parameter(title: "Typ", default: .ukol)
    var kind: DeadlineKind

    @Parameter(title: "Termín", requestValueDialog: "Kdy je termín?")
    var dueDate: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Přidat \(\.$kind) \(\.$name) k předmětu \(\.$subject) na \(\.$dueDate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw $name.needsValueError("Jak se deadline jmenuje?")
        }
        guard let subjectModel = IntentStore.subject(id: subject.id) else {
            throw TerminovnikIntentError.subjectNotFound
        }

        // Stejný postup jako formulář v aplikaci: nejdřív vložit do kontextu, pak navázat předmět.
        let context = IntentStore.context
        let task = ExamTask(title: trimmedName, taskType: kind.taskType, dueDate: dueDate)
        context.insert(task)
        task.subject = subjectModel
        TaskService.save(context) // uloží a aktualizuje widget
        NotificationManager.shared.updateReminder(for: task)

        let item = DeadlineSnippetItem(task: task)
        return .result(
            dialog: "Přidáno: \(trimmedName) – \(item.countdown)",
            view: DeadlineSnippetView(header: "Přidáno", item: item, emptyText: "")
        )
    }
}
