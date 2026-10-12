import SwiftUI
import UIKit
import EventKit
import EventKitUI

/// Systémový editor události v Kalendáři (`EKEventEditViewController`) zabalený pro SwiftUI.
///
/// Předvyplní název, začátek, konec, místo a poznámku události. Od iOS 17 běží editor mimo
/// proces aplikace, takže **nepotřebuje povolení přístupu ke kalendáři** – událost uloží sám
/// uživatel klepnutím na „Přidat“. Aplikace kalendář nečte. Zobrazuj jako `.sheet`; po uložení
/// nebo zrušení se sheet sám zavře a zavolá `onFinish`. Používá se na Přehledu, ve formuláři
/// deadlinu, v detailu předmětu, rozvrhové akce a zkouškového termínu.
struct CalendarEventEditor: UIViewControllerRepresentable {
    /// Název události.
    let title: String
    /// Začátek události.
    let start: Date
    /// Poznámka události, případně `nil`.
    let notes: String?
    /// Konec události (`nil` = začátek + výchozí délka).
    var end: Date? = nil
    /// Místo konání, např. učebna.
    var location: String? = nil
    /// Zavolá se po zavření editoru; parametr říká, jestli uživatel událost uložil.
    var onFinish: (_ saved: Bool) -> Void = { _ in }

    /// Délka předvyplněné události (1 hodina).
    static let defaultDuration: TimeInterval = 60 * 60

    /// Vytvoří editor z hotových hodnot události.
    /// - Parameters:
    ///   - title: název události
    ///   - start: začátek události
    ///   - end: konec události, `nil` = začátek + `defaultDuration`
    ///   - location: místo konání
    ///   - notes: poznámka události
    ///   - onFinish: zavolá se po zavření editoru s informací, zda byla událost uložena
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

    /// Předvyplnění z jednotlivých hodnot (např. z neuloženého formuláře).
    /// - Parameters:
    ///   - taskType: typ deadlinu (součást názvu události)
    ///   - subject: předmět – kód jde do názvu, název do poznámky
    ///   - taskTitle: název deadlinu
    ///   - dueDate: termín, použije se jako začátek události
    ///   - note: poznámka k deadlinu
    ///   - onFinish: zavolá se po zavření editoru s informací, zda byla událost uložena
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

    /// Předvyplnění z uloženého úkolu.
    /// - Parameters:
    ///   - task: uložený deadline
    ///   - onFinish: zavolá se po zavření editoru s informací, zda byla událost uložena
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

    /// Sestaví název události: „Zkouška AP9PT: 1. termín“ – prázdné části se vynechají.
    /// - Parameters:
    ///   - taskType: typ deadlinu
    ///   - subjectCode: kód předmětu, případně `nil`
    ///   - taskTitle: název deadlinu
    /// - Returns: název události.
    static func eventTitle(taskType: TaskType, subjectCode: String?, taskTitle: String) -> String {
        let prefix = [taskType.title, subjectCode ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? prefix : "\(prefix): \(name)"
    }

    /// Sestaví poznámku události: název předmětu a poznámka oddělené prázdným řádkem.
    /// - Parameters:
    ///   - subjectName: název předmětu, případně `nil`
    ///   - note: poznámka k deadlinu
    /// - Returns: text poznámky, nebo `nil`, když jsou obě části prázdné.
    static func eventNotes(subjectName: String?, note: String) -> String? {
        let parts = [subjectName ?? "", note]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    // MARK: - UIViewControllerRepresentable

    /// Vytvoří koordinátor, který drží `EKEventStore` a reaguje na zavření editoru.
    /// - Returns: nový koordinátor.
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Vytvoří předvyplněnou událost a systémový editor s ní.
    /// - Parameter context: kontext reprezentace s koordinátorem.
    /// - Returns: nakonfigurovaný `EKEventEditViewController`.
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

    /// Předá koordinátoru aktuální callback a akci pro zavření sheetu.
    /// - Parameters:
    ///   - editor: zobrazený editor (nemění se)
    ///   - context: kontext s koordinátorem a prostředím
    func updateUIViewController(_ editor: EKEventEditViewController, context: Context) {
        // Aktuální callback a akce pro zavření sheetu
        context.coordinator.onFinish = onFinish
        context.coordinator.dismiss = context.environment.dismiss
    }

    /// Delegát editoru události.
    ///
    /// Drží úložiště událostí po dobu zobrazení editoru a po dokončení zavře sheet a zavolá `onFinish`.
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        /// Úložiště musí žít po celou dobu zobrazení editoru.
        let eventStore = EKEventStore()
        /// Callback po zavření editoru (`true` = událost uložena).
        var onFinish: (Bool) -> Void = { _ in }
        /// Akce pro zavření sheetu z prostředí SwiftUI.
        var dismiss: DismissAction?

        /// Zavře sheet a ohlásí, zda uživatel událost uložil.
        /// - Parameters:
        ///   - controller: editor, který skončil
        ///   - action: způsob ukončení (uložení, zrušení, smazání)
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
