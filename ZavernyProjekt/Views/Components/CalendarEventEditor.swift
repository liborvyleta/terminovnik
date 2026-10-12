import SwiftUI
import UIKit
import EventKit
import EventKitUI

/// Systémový editor události v Kalendáři (`EKEventEditViewController`) zabalený pro SwiftUI.
///
/// Od iOS 17 běží editor mimo proces aplikace, takže **nepotřebuje povolení přístupu
/// ke kalendáři** – událost uloží sám uživatel klepnutím na „Přidat“. Aplikace kalendář nečte.
/// Zobrazuj jako `.sheet`; po uložení nebo zrušení se sheet sám zavře a zavolá `onFinish`.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let notes: String?
    /// Konec události (nil = začátek + výchozí délka)
    var end: Date? = nil
    /// Místo konání, např. učebna
    var location: String? = nil
    /// Zavolá se po zavření editoru; parametr říká, jestli uživatel událost uložil
    var onFinish: (_ saved: Bool) -> Void = { _ in }

    /// Délka předvyplněné události
    static let defaultDuration: TimeInterval = 60 * 60

    init(
        title: String,
        start: Date,
        end: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        onFinish: @escaping (_ saved: Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.onFinish = onFinish
    }

    /// Předvyplnění z jednotlivých hodnot (např. z neuloženého formuláře)
    init(
        taskType: TaskType,
        subject: Subject?,
        taskTitle: String,
        dueDate: Date,
        note: String,
        onFinish: @escaping (_ saved: Bool) -> Void = { _ in }
    ) {
        self.init(
            title: Self.eventTitle(taskType: taskType, subjectCode: subject?.code, taskTitle: taskTitle),
            start: dueDate,
            notes: Self.eventNotes(subjectName: subject?.name, note: note),
            onFinish: onFinish
        )
    }

    /// Předvyplnění z uloženého úkolu
    init(task: ExamTask, onFinish: @escaping (_ saved: Bool) -> Void = { _ in }) {
        self.init(
            taskType: task.taskType,
            subject: task.subject,
            taskTitle: task.title,
            dueDate: task.dueDate,
            note: task.note,
            onFinish: onFinish
        )
    }

    // MARK: - Texty události

    /// „Zkouška AP9PT: 1. termín“ – prázdné části se vynechají
    static func eventTitle(taskType: TaskType, subjectCode: String?, taskTitle: String) -> String {
        let prefix = [taskType.title, subjectCode ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? prefix : "\(prefix): \(name)"
    }

    /// Název předmětu a poznámka oddělené prázdným řádkem
    static func eventNotes(subjectName: String?, note: String) -> String? {
        let parts = [subjectName ?? "", note]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = context.coordinator.eventStore
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(Self.defaultDuration)
        event.location = location
        event.notes = notes

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ editor: EKEventEditViewController, context: Context) {
        // Aktuální callback a akce pro zavření sheetu
        context.coordinator.onFinish = onFinish
        context.coordinator.dismiss = context.environment.dismiss
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        /// Úložiště musí žít po celou dobu zobrazení editoru
        let eventStore = EKEventStore()
        var onFinish: (Bool) -> Void = { _ in }
        var dismiss: DismissAction?

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss?()
            onFinish(action == .saved)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CalendarEventEditor(title: "Zkouška AP9PT: 1. termín", start: .now.addingTimeInterval(86_400), notes: "Pokročilé programování")
                .ignoresSafeArea()
        }
}
