import SwiftUI
import SwiftData

/// Formulář pro přidání nebo úpravu předmětu (název, kód, kredity, barva z palety).
struct SubjectFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: SubjectFormViewModel
    /// Volá se po uložení – formulář úkolu tak může nový předmět rovnou vybrat
    private let onSaved: ((Subject) -> Void)?

    init(subject: Subject? = nil, onSaved: ((Subject) -> Void)? = nil) {
        _viewModel = State(initialValue: SubjectFormViewModel(subject: subject))
        self.onSaved = onSaved
    }

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
