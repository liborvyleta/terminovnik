import Foundation
import Observation
import SwiftData

/// ViewModel seznamu předmětů – stav sheetů, mazání a souhrnné statistiky.
@Observable
final class SubjectsViewModel {
    var isAddingSubject = false
    var isImportingFromStag = false
    var subjectToEdit: Subject?
    var subjectToDelete: Subject?

    /// Binding pro potvrzovací dialog mazání
    var isConfirmingDelete: Bool {
        get { subjectToDelete != nil }
        set { if !newValue { subjectToDelete = nil } }
    }

    func totalCredits(of subjects: [Subject]) -> Int {
        subjects.reduce(0) { $0 + $1.credits }
    }

    func activeTaskCount(of subjects: [Subject]) -> Int {
        subjects.reduce(0) { $0 + $1.activeCount }
    }

    func delete(_ subject: Subject, in context: ModelContext) {
        TaskService.delete(subject, in: context)
        subjectToDelete = nil
    }
}
