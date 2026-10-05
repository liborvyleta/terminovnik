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

    // Nastavení výuky – klíče sdílí ClassReminderScheduler a LiveActivityManager
    @AppStorage(ClassReminderScheduler.enabledKey) private var classRemindersEnabled = true
    @AppStorage(ClassReminderScheduler.leadMinutesKey) private var classReminderLeadMinutes = ClassReminderScheduler.defaultLeadMinutes
    @AppStorage("lessonLiveActivityEnabled") private var lessonLiveActivityEnabled = true
    /// Upozornění na nově vypsané termíny zkoušek – klíč čte ExamTermStore
    @AppStorage(ExamTermStore.alertsEnabledKey) private var examTermAlertsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                StagAccountSection()
                notificationsSection
                lessonsSection
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

    // MARK: - Výuka

    private var lessonsSection: some View {
        Section {
            Toggle(isOn: $classRemindersEnabled) {
                Label("Upozornit před hodinou", systemImage: "bell.badge")
            }

            if classRemindersEnabled {
                Picker(selection: $classReminderLeadMinutes) {
                    ForEach(ClassReminderScheduler.leadMinuteOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                } label: {
                    Label("Předstih", systemImage: "timer")
                }
            }

            Toggle(isOn: $lessonLiveActivityEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hodina na zamčené obrazovce")
                        Text("Live Activity s odpočtem na zamčené obrazovce a v Dynamic Islandu")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.iphone")
                }
            }

            Toggle(isOn: $examTermAlertsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upozornit na nové termíny")
                        Text("Kontroluje se při otevření aplikace a průběžně na pozadí (iOS spouští kontrolu podle svého uvážení).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "graduationcap")
                }
            }
        } header: {
            Text("Výuka")
        } footer: {
            Text(lessonsFooter)
        }
        .onChange(of: classRemindersEnabled) { _, enabled in
            Task { await viewModel.classRemindersChanged(enabled: enabled) }
        }
        .onChange(of: classReminderLeadMinutes) {
            viewModel.classReminderLeadChanged()
        }
        .onChange(of: lessonLiveActivityEnabled) {
            viewModel.lessonLiveActivityChanged()
        }
        .onChange(of: examTermAlertsEnabled) { _, enabled in
            Task { await viewModel.examTermAlertsChanged(enabled: enabled) }
        }
    }

    private var lessonsFooter: String {
        var text = "Upozornění na hodiny i Live Activity fungují, když je načtený rozvrh ze STAGu. Nové termíny hlídáme, když jsi přihlášený do STAGu."
        if classRemindersEnabled || examTermAlertsEnabled, viewModel.notificationPermission == .denied {
            text += " Oznámení jsou ale v nastavení iOS vypnutá."
        }
        return text
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
