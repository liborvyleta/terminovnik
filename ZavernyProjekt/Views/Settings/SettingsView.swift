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
                if PersistenceController.isUsingFallbackStore {
                    storageWarningSection
                }
                StagAccountSection()
                notificationsSection
                lessonsSection
                widgetSection
                languageSection
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
                if StagAccountStore.shared.isConnected {
                    Button("Smazat vše a odhlásit ze STAGu", role: .destructive) {
                        viewModel.deleteAllData(in: context, signOut: true)
                    }
                }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text(deleteAllMessage)
            }
        }
    }

    // MARK: - Úložiště

    /// Trvalé úložiště se nepodařilo otevřít – aplikace běží z paměti a po zavření o změny přijde
    private var storageWarningSection: some View {
        Section {
            Label("Data se nepodařilo načíst – změny se neuloží", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } footer: {
            Text("Zkus aplikaci ukončit a znovu otevřít. Pokud problém trvá, restartuj zařízení nebo uvolni místo v úložišti.")
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
        var text = String(localized: "Upozornění na hodiny i Live Activity fungují, když je načtený rozvrh ze STAGu. Nové termíny hlídáme, když jsi přihlášený do STAGu.")
        if classRemindersEnabled || examTermAlertsEnabled, viewModel.notificationPermission == .denied {
            text += " " + String(localized: "Oznámení jsou ale v nastavení iOS vypnutá.")
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

    private func widgetStep(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
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

    // MARK: - Jazyk

    /// Jazyk aplikace volí iOS (Nastavení → Termínovník → Jazyk) – tady ho jen ukážeme a nabídneme odkaz
    private var languageSection: some View {
        Section {
            LabeledContent("Jazyk aplikace", value: viewModel.appLanguageName)

            Button {
                if let url = viewModel.appSettingsURL { openURL(url) }
            } label: {
                Label("Změnit jazyk", systemImage: "globe")
            }
        } header: {
            Text("Jazyk")
        } footer: {
            Text("Jazyk aplikace se přepíná v Nastavení iOS → Termínovník → Jazyk.")
        }
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
                    .foregroundStyle(hasAnyData ? Color.red : Color.secondary)
            }
            .disabled(!hasAnyData)
        } header: {
            Text("Data")
        } footer: {
            Text("Smaže všechny předměty, deadliny a připomínky i uložený rozvrh a termíny zkoušek. Zároveň se můžeš odhlásit ze STAGu.")
        }
    }

    /// Je co mazat? Kromě předmětů a deadlinů i rozvrh, termíny nebo přihlášený účet STAG.
    private var hasAnyData: Bool {
        !subjects.isEmpty || !tasks.isEmpty
            || TimetableStore.shared.snapshot != nil
            || !ExamTermStore.shared.terms.isEmpty
            || StagAccountStore.shared.isConnected
    }

    private var deleteAllMessage: String {
        var text = String(localized: "Smažou se všechny předměty, deadliny a připomínky i uložený rozvrh a termíny zkoušek. Akci nelze vrátit.")
        if StagAccountStore.shared.isConnected {
            text += " " + String(localized: "Účet STAG může zůstat přihlášený, nebo se můžeš rovnou odhlásit.")
        }
        return text
    }

    // MARK: - O aplikaci

    private var aboutSection: some View {
        Section {
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

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Zásady ochrany osobních údajů", systemImage: "hand.raised")
            }

            if let url = AppInfo.privacyPolicyURL {
                Link(destination: url) {
                    Label("Zásady ochrany osobních údajů na webu", systemImage: "safari")
                }
            }

            if let url = AppInfo.supportURL {
                Link(destination: url) {
                    Label("Podpora", systemImage: "questionmark.circle")
                }
            }

            if let url = AppInfo.supportMailURL {
                Link(destination: url) {
                    Label("Napsat vývojáři", systemImage: "envelope")
                }
            }

            Text("Závěrečný projekt AP9PT · UTB FAI")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("O aplikaci")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Neoficiální aplikace. Není produktem IS/STAG ani žádné univerzity; názvy škol slouží jen k připojení k jejich systému.")
                Text("© 2026 \(AppInfo.developerName)")
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
