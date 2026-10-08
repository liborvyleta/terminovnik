import SwiftUI
import SwiftData

/// Požadavek na změnu zápisu – čeká na potvrzení uživatelem v dialogu
struct ExamTermRegistrationRequest: Identifiable, Equatable {
    let term: ExamTerm
    let action: StagTermRegistrationAction
    let subjectName: String?
    var id: String { "\(term.id)-\(action.rawValue)" }
}

/// Výsledek provedené změny zápisu
struct ExamTermRegistrationOutcome: Identifiable, Equatable {
    let id = UUID()
    let termID: String
    let action: StagTermRegistrationAction
    let result: StagTermRegistrationResult

    var isSuccess: Bool { result == .success }

    /// Úspěch: text pro akci; neúspěch: důvod ze STAGu
    var message: String {
        switch result {
        case .success: action.successText
        case .failure(let message): message
        }
    }
}

/// Potvrzení → provedení → výsledek (haptika, upozornění) pro zápis na termín.
///
/// Ostrá operace ve STAGu se spustí VÝHRADNĚ tlačítkem v potvrzovacím dialogu.
private struct ExamTermRegistrationFlow: ViewModifier {
    @Binding var request: ExamTermRegistrationRequest?
    let viewModel: ExamTermsViewModel
    /// Úspěch ukázat upozorněním (seznam); detail ho ukazuje přímo v obsahu
    let showsSuccessAlert: Bool
    let onOutcome: (ExamTermRegistrationOutcome) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var alertOutcome: ExamTermRegistrationOutcome?
    @State private var successCount = 0
    @State private var errorCount = 0

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
    /// Potvrzovací dialog a zpracování výsledku změny zápisu na termín
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

/// Položka kontextové nabídky řádku termínu (akce se jen připraví – provede se až po potvrzení)
struct ExamTermRegistrationMenuItem: View {
    let term: ExamTerm
    let subjectName: String?
    let viewModel: ExamTermsViewModel
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
