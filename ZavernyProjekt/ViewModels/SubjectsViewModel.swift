import Foundation
import Observation
import SwiftData

/// ViewModel seznamu předmětů – stav sheetů, mazání a souhrnné statistiky.
///
/// Předměty získává View přes `@Query` a předává je sem; ViewModel počítá součet kreditů a aktivních úkolů, řídí zobrazení formuláře, importu ze STAGu a potvrzení smazání a maže předmět přes `TaskService`.
@Observable
final class SubjectsViewModel {
    /// Zda je otevřený sheet pro přidání předmětu.
    var isAddingSubject = false
    /// Zda je otevřený sheet importu předmětů ze STAGu.
    var isImportingFromStag = false
    /// Předmět otevřený ve formuláři úprav.
    var subjectToEdit: Subject?
    /// Předmět čekající na potvrzení smazání.
    var subjectToDelete: Subject?

    /// Binding pro potvrzovací dialog mazání; nastavení na `false` zruší výběr předmětu.
    var isConfirmingDelete: Bool {
        get { subjectToDelete != nil }
        set { if !newValue { subjectToDelete = nil } }
    }

    /// Sečte kredity předmětů.
    /// - Parameter subjects: Předměty.
    /// - Returns: Celkový počet kreditů.
    func totalCredits(of subjects: [Subject]) -> Int {
        subjects.reduce(0) { $0 + $1.credits }
    }

    /// Sečte aktivní (nesplněné) úkoly předmětů.
    /// - Parameter subjects: Předměty.
    /// - Returns: Celkový počet aktivních úkolů.
    func activeTaskCount(of subjects: [Subject]) -> Int {
        subjects.reduce(0) { $0 + $1.activeCount }
    }

    /// Smaže předmět přes `TaskService` a zavře potvrzení.
    /// - Parameters:
    ///   - subject: Předmět ke smazání.
    ///   - context: SwiftData kontext, ze kterého se předmět odstraní.
    func delete(_ subject: Subject, in context: ModelContext) {
        TaskService.delete(subject, in: context)
        subjectToDelete = nil
    }
}
