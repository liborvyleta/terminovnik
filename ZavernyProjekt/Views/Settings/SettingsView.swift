import SwiftUI
import SwiftData

/// Obrazovka Nastavení: účet STAG, oznámení, návod k widgetu, správa dat a informace o aplikaci.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @Query private var subjects: [Subject]
    @Query private var tasks: [ExamTask]

    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                StagAccountSection()
                notificationsSection
                widgetSection
                dataSection
                aboutSection
            }
            .navigationTitle("Nastavení")
            .task { await viewModel.refreshNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in
                // Uživatel mohl oznámení změnit v Nastavení iOS – po návratu stav obnovíme
                if phase == .active {
                    Task { await viewModel.refreshNotificationStatus() }
                }
            }
            .confirmationDialog(
                "Smazat všechna data?",
                isPresented: $viewModel.isConfirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Smazat vše", role: .destructive) {
                    viewModel.deleteAllData(in: context)
                }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Smažou se všechny předměty a deadliny včetně připomínek. Akci nelze vrátit. Účet STAG zůstane přihlášený.")
            }
        }
    }

    // MARK: - Oznámení

    private var notificationsSection: some View {
        Section {
            LabeledContent("Stav") {
                Label(viewModel.notificationPermission.title,
                      systemImage: viewModel.notificationPermission.systemImage)
                    .labelStyle(.compact)
                    .foregroundStyle(viewModel.notificationPermission.tint)
            }

            switch viewModel.notificationPermission {
            case .notDetermined:
                Button {
                    Task { await viewModel.requestNotifications() }
                } label: {
                    Label("Povolit oznámení", systemImage: "bell.badge")
                }
            case .authorized, .denied:
                Button {
                    if let url = viewModel.notificationSettingsURL { openURL(url) }
                } label: {
                    Label("Otevřít nastavení iOS", systemImage: "gear")
                }
            case .unknown:
                EmptyView()
            }
        } header: {
            Text("Oznámení")
        } footer: {
            Text("Připomínka přijde den před termínem. Přímo z oznámení můžeš deadline označit jako splněný.")
        }
    }

    // MARK: - Widget

    private var widgetSection: some View {
        Section {
            widgetStep(
                icon: "apps.iphone",
                title: "Plocha",
                text: "Dlouze podrž prázdné místo na ploše → Upravit → Přidat widget → Termínovník."
            )
            widgetStep(
                icon: "lock.iphone",
                title: "Zamčená obrazovka",
                text: "Dlouze podrž zamčenou obrazovku → Přizpůsobit → Zamčená obrazovka → klepni na oblast widgetů → Termínovník."
            )
        } header: {
            Text("Widget")
        } footer: {
            Text("Widget ukazuje nejbližší deadliny a aktualizuje se po každé změně v aplikaci.")
        }
    }

    private func widgetStep(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            LabeledContent("Předměty", value: "\(subjects.count)")
            LabeledContent("Deadliny", value: "\(tasks.count)")

            Button(role: .destructive) {
                viewModel.isConfirmingDeleteAll = true
            } label: {
                Label("Smazat všechna data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .disabled(subjects.isEmpty && tasks.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            Text("Smaže všechny předměty, deadliny a naplánované připomínky. Účet STAG se tím neodhlašuje.")
        }
    }

    // MARK: - O aplikaci

    private var aboutSection: some View {
        Section("O aplikaci") {
            HStack(spacing: 14) {
                AppLogoView(variant: colorScheme == .dark ? .dark : .light)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12.5, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Termínovník")
                        .font(.headline)
                    Text("Chytrý plánovač zkoušek a deadlinů")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            LabeledContent("Verze", value: viewModel.versionText)

            Text("Závěrečný projekt AP9PT · UTB FAI")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
