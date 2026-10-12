import SwiftUI
import SwiftData

/// Formulář pro přidání nebo úpravu předmětu.
///
/// Obsahuje živý náhled, název, kód, kredity a barvu z palety. Stav
/// a ukládání drží `SubjectFormViewModel`. Otevírá se jako sheet
/// ze seznamu a detailu předmětu nebo z formuláře úkolu.
struct SubjectFormSheet: View {
    /// Akce pro zavření sheetu.
    @Environment(\.dismiss) private var dismiss
    /// SwiftData kontext, do kterého se předmět uloží.
    @Environment(\.modelContext) private var modelContext

    /// ViewModel s hodnotami formuláře, validací a uložením.
    @State private var viewModel: SubjectFormViewModel
    /// Volá se po uložení – formulář úkolu tak může nový předmět rovnou vybrat.
    private let onSaved: ((Subject) -> Void)?

    /// Vytvoří formulář.
    /// - Parameters:
    ///   - subject: Upravovaný předmět, nebo `nil` pro nový.
    ///   - onSaved: Volitelná akce s uloženým předmětem.
    init(subject: Subject? = nil, onSaved: ((Subject) -> Void)? = nil) {
        _viewModel = State(initialValue: SubjectFormViewModel(subject: subject))
        self.onSaved = onSaved
    }

    /// Formulář s náhledem, údaji a barvou; toolbar se Zrušit a Uložit.
    var body: some View {
        NavigationStack {
            Form {
                // Živý náhled, jak bude předmět vypadat
                Section {
                    HStack(spacing: 14) {
                        SubjectAvatar(initials: viewModel.initials, color: viewModel.color, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.previewName)
                                .font(.headline)
                            Text(viewModel.previewDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                }

                Section("Údaje o předmětu") {
                    TextField("Název (např. Mobilní aplikace)", text: $viewModel.name)
                    TextField("Kód (např. AP9PT)", text: $viewModel.code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Stepper(value: $viewModel.credits, in: 0...30) {
                        LabeledContent("Kredity", value: "\(viewModel.credits)")
                    }
                }

                Section("Barva") {
                    ColorPaletteView(selection: $viewModel.hexColor)
                }
            }
            .navigationTitle(viewModel.isEditing ? "Upravit předmět" : "Nový předmět")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") {
                        let subject = viewModel.save(in: modelContext)
                        onSaved?(subject)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}

#Preview {
    SubjectFormSheet()
        .modelContainer(for: [Subject.self, ExamTask.self], inMemory: true)
}
