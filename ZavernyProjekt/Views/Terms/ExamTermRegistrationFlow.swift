import SwiftUI
import SwiftData

/// Požadavek na změnu zápisu na termín, který čeká na potvrzení uživatelem v dialogu.
///
/// Nese termín, požadovanou akci (zápis/odhlášení) a název předmětu pro text dialogu.
/// Vytváří ho `ExamTermRegistrationMenuItem` nebo detail termínu a zpracovává
/// modifikátor `examTermRegistrationFlow`.
struct ExamTermRegistrationRequest: Identifiable, Equatable {
    /// Termín, kterého se změna týká.
    let term: ExamTerm
    /// Požadovaná akce ve STAGu (zápis nebo odhlášení).
    let action: StagTermRegistrationAction
    /// Název předmětu pro text potvrzovacího dialogu.
    let subjectName: String?
    /// Identifikátor složený z ID termínu a akce.
    var id: String { "\(term.id)-\(action.rawValue)" }
}

/// Výsledek provedené změny zápisu na termín.
///
/// Vzniká v `ExamTermRegistrationFlow` po odpovědi STAGu a předává se volajícímu
/// přes `onOutcome` a do upozornění.
struct ExamTermRegistrationOutcome: Identifiable, Equatable {
    /// Jedinečné ID výsledku, aby šlo stejný výsledek zobrazit opakovaně.
    let id = UUID()
    /// ID termínu, kterého se změna týkala.
    let termID: String
    /// Provedená akce.
    let action: StagTermRegistrationAction
    /// Výsledek operace vrácený STAGem.
    let result: StagTermRegistrationResult

    /// Zda změna proběhla úspěšně.
    var isSuccess: Bool { result == .success }

    /// Text výsledku: při úspěchu text pro danou akci, při neúspěchu důvod ze STAGu.
    var message: String {
        switch result {
        case .success: action.successText
        case .failure(let message): message
        }
    }
}

/// Modifikátor řídící potvrzení, provedení a výsledek změny zápisu na termín.
///
/// Zobrazí potvrzovací dialog pro `request`, po potvrzení zavolá
/// `ExamTermsViewModel.performRegistration`, spustí haptiku a ukáže upozornění s výsledkem
/// (úspěch jen při `showsSuccessAlert`). Ostrá operace ve STAGu se spustí VÝHRADNĚ
/// tlačítkem v potvrzovacím dialogu. Používá se přes `examTermRegistrationFlow`.
private struct ExamTermRegistrationFlow: ViewModifier {
    /// Čekající požadavek; nenil otevře potvrzovací dialog.
    @Binding var request: ExamTermRegistrationRequest?
    /// ViewModel, který změnu ve STAGu provede.
    let viewModel: ExamTermsViewModel
    /// Zda ukázat úspěch upozorněním (seznam); detail ho ukazuje přímo v obsahu.
    let showsSuccessAlert: Bool
    /// Callback volaný s výsledkem každé provedené změny.
    let onOutcome: (ExamTermRegistrationOutcome) -> Void

    /// Kontext SwiftData předávaný ViewModelu pro uložení změn.
    @Environment(\.modelContext) private var modelContext
    /// Výsledek zobrazovaný v upozornění.
    @State private var alertOutcome: ExamTermRegistrationOutcome?
    /// Počítadlo úspěchů spouštějící haptiku úspěchu.
    @State private var successCount = 0
    /// Počítadlo chyb spouštějící haptiku chyby.
    @State private var errorCount = 0

    /// Obalí obsah potvrzovacím dialogem, upozorněním s výsledkem a haptikou.
    /// - Parameter content: Obsah, na který se modifikátor aplikuje.
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                request?.action.confirmationTitle ?? "",
                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                titleVisibility: .visible,
                presenting: request
            ) { request in
                Button(request.action.confirmButtonTitle, role: request.action.isDestructive ? .destructive : nil) {
                    perform(request)
                }
                Button("Zrušit", role: .cancel) {}
            } message: { request in
                Text(ExamTermsViewModel.confirmationMessage(request.action, term: request.term, subjectName: request.subjectName))
            }
            .alert(
                alertOutcome.map { $0.isSuccess ? String(localized: "Hotovo") : String(localized: "Změnu se nepodařilo provést") } ?? "",
                isPresented: Binding(get: { alertOutcome != nil }, set: { if !$0 { alertOutcome = nil } }),
                presenting: alertOutcome
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { outcome in
                Text(outcome.message)
            }
            .sensoryFeedback(.success, trigger: successCount)
            .sensoryFeedback(.error, trigger: errorCount)
    }

    /// Asynchronně provede potvrzenou změnu zápisu a zpracuje výsledek.
    ///
    /// Zvýší příslušné počítadlo haptiky, podle výsledku nastaví upozornění a zavolá `onOutcome`.
    /// - Parameter request: Potvrzený požadavek na změnu zápisu.
    private func perform(_ request: ExamTermRegistrationRequest) {
        Task {
            let result = await viewModel.performRegistration(request.action, for: request.term, context: modelContext)
            let outcome = ExamTermRegistrationOutcome(termID: request.term.id, action: request.action, result: result)
            if outcome.isSuccess {
                successCount += 1
                if showsSuccessAlert { alertOutcome = outcome }
            } else {
                errorCount += 1
                alertOutcome = outcome
            }
            onOutcome(outcome)
        }
    }
}

extension View {
    /// Připojí potvrzovací dialog a zpracování výsledku změny zápisu na termín.
    /// - Parameters:
    ///   - request: Vazba na čekající požadavek; nastavením se otevře dialog.
    ///   - viewModel: ViewModel, který změnu ve STAGu provede.
    ///   - showsSuccessAlert: Zda ukázat úspěch upozorněním.
    ///   - onOutcome: Callback volaný s výsledkem změny.
    /// - Returns: Pohled s připojeným modifikátorem `ExamTermRegistrationFlow`.
    func examTermRegistrationFlow(
        _ request: Binding<ExamTermRegistrationRequest?>,
        viewModel: ExamTermsViewModel,
        showsSuccessAlert: Bool = true,
        onOutcome: @escaping (ExamTermRegistrationOutcome) -> Void = { _ in }
    ) -> some View {
        modifier(ExamTermRegistrationFlow(request: request, viewModel: viewModel,
                                          showsSuccessAlert: showsSuccessAlert, onOutcome: onOutcome))
    }
}

/// Položka kontextové nabídky řádku termínu pro zápis nebo odhlášení.
///
/// Akci určí `ExamTermsViewModel.registrationAction(for:)`; klepnutí jen připraví
/// `ExamTermRegistrationRequest`, provede se až po potvrzení v dialogu. Je neaktivní,
/// když STAG změnu nedovoluje nebo už jiná změna probíhá, a pak zobrazí důvod v patičce.
/// Používá se v kontextových nabídkách řádků v `ExamTermsView`.
struct ExamTermRegistrationMenuItem: View {
    /// Termín, ke kterému se položka vztahuje.
    let term: ExamTerm
    /// Název předmětu pro text potvrzovacího dialogu.
    let subjectName: String?
    /// ViewModel určující dostupnou akci a probíhající změnu.
    let viewModel: ExamTermsViewModel
    /// Vazba na požadavek, který se po klepnutí nastaví.
    @Binding var request: ExamTermRegistrationRequest?

    var body: some View {
        if let action = viewModel.registrationAction(for: term) {
            let enabled = ExamTermsViewModel.isRegistrationActionEnabled(action, term: term)
            Section {
                Button(role: action.isDestructive ? .destructive : nil) {
                    request = ExamTermRegistrationRequest(term: term, action: action, subjectName: subjectName)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
                .disabled(!enabled || viewModel.pendingRegistration != nil)
            } footer: {
                if !enabled {
                    Text(ExamTermsViewModel.blockReasonText(term) ?? String(localized: "STAG teď změnu zápisu nedovoluje."))
                }
            }
        }
    }
}
