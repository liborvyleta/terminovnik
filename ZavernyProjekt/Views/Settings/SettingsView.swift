import SwiftUI
import SwiftData

/// Obrazovka Nastavení aplikace.
///
/// Obsahuje účet STAG (`StagAccountSection`), stav a povolení oznámení,
/// nastavení výuky (připomínky hodin, Live Activity, upozornění na změny
/// rozvrhu, nové termíny a známky), návod k widgetu, jazyk, zálohu
/// (`BackupSection`), správu dat se smazáním všeho a informace o aplikaci.
/// Počty čte přes `@Query`, logiku deleguje na `SettingsViewModel`
/// a přepínače ukládá do `@AppStorage`. Jedna ze záložek hlavní navigace.
struct SettingsView: View {
    /// SwiftData kontext pro smazání všech dat.
    @Environment(\.modelContext) private var context
    /// Fáze scény – po návratu do aplikace se obnoví stav oznámení.
    @Environment(\.scenePhase) private var scenePhase
    /// Barevné schéma pro volbu varianty loga.
    @Environment(\.colorScheme) private var colorScheme
    /// Akce pro otevření systémového nastavení.
    @Environment(\.openURL) private var openURL

    /// Všechny předměty (pro počet a kontrolu, zda je co mazat).
    @Query private var subjects: [Subject]
    /// Všechny deadliny (pro počet a kontrolu, zda je co mazat).
    @Query private var tasks: [ExamTask]

    /// ViewModel s oprávněním oznámení, mazáním dat a informacemi o aplikaci.
    @State private var viewModel = SettingsViewModel()

    // Nastavení výuky – klíče sdílí ClassReminderScheduler a LiveActivityManager
    /// Zda jsou zapnuté připomínky před hodinou.
    @AppStorage(ClassReminderScheduler.enabledKey) private var classRemindersEnabled = true
    /// Předstih připomínky hodiny v minutách.
    @AppStorage(ClassReminderScheduler.leadMinutesKey) private var classReminderLeadMinutes = ClassReminderScheduler.defaultLeadMinutes
    /// Zda se zobrazuje Live Activity s probíhající hodinou.
    @AppStorage("lessonLiveActivityEnabled") private var lessonLiveActivityEnabled = true
    /// Upozornění na nově vypsané termíny zkoušek – klíč čte `ExamTermStore`.
    @AppStorage(ExamTermStore.alertsEnabledKey) private var examTermAlertsEnabled = true
    /// Upozornění na nové známky – klíč čte `GradeStore`.
    @AppStorage(GradeStore.alertsEnabledKey) private var gradeAlertsEnabled = true
    /// Upozornění na změny v rozvrhu – klíč čte `TimetableStore`.
    @AppStorage(TimetableStore.changeAlertsEnabledKey) private var timetableChangeAlertsEnabled = true

    /// Formulář se všemi sekcemi, dialogem pro smazání dat a obnovou stavu oznámení.
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
                BackupSection()
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

    /// Varování, že trvalé úložiště se nepodařilo otevřít.
    ///
    /// Aplikace běží z paměti a po zavření o změny přijde.
    private var storageWarningSection: some View {
        Section {
            Label("Data se nepodařilo načíst – změny se neuloží", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } footer: {
            Text("Zkus aplikaci ukončit a znovu otevřít. Pokud problém trvá, restartuj zařízení nebo uvolni místo v úložišti.")
        }
    }

    // MARK: - Oznámení

    /// Stav oprávnění oznámení s tlačítkem pro povolení nebo otevření nastavení iOS.
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

    /// Přepínače výuky a upozornění; změny předává `SettingsViewModel`.
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

            Toggle(isOn: $timetableChangeAlertsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upozornit na změny v rozvrhu")
                        Text("Dáme vědět, když se ve STAGu zruší nebo přesune hodina v příštích dvou týdnech.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
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

            Toggle(isOn: $gradeAlertsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upozornit na nové známky")
                        Text("Dáme vědět, jakmile ti vyučující zapíše do STAGu zápočet nebo známku ze zkoušky.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "rosette")
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
        .onChange(of: gradeAlertsEnabled) { _, enabled in
            Task { await viewModel.gradeAlertsChanged(enabled: enabled) }
        }
    }

    /// Patička sekce Výuka, doplněná o varování při vypnutých oznámeních.
    private var lessonsFooter: String {
        var text = String(localized: "Upozornění na hodiny i Live Activity fungují, když je načtený rozvrh ze STAGu. Nové termíny a známky hlídáme, když jsi přihlášený do STAGu.")
        if classRemindersEnabled || examTermAlertsEnabled || gradeAlertsEnabled, viewModel.notificationPermission == .denied {
            text += " " + String(localized: "Oznámení jsou ale v nastavení iOS vypnutá.")
        }
        return text
    }

    // MARK: - Widget

    /// Návod, jak přidat widget na plochu a zamčenou obrazovku.
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

    /// Řádek jednoho kroku návodu k widgetu.
    /// - Parameters:
    ///   - icon: Název SF Symbolu.
    ///   - title: Nadpis kroku.
    ///   - text: Popis postupu.
    /// - Returns: View řádku kroku.
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

    /// Sekce s jazykem aplikace a odkazem do nastavení iOS.
    ///
    /// Jazyk volí iOS (Nastavení → Termínovník → Jazyk) – tady ho jen ukážeme.
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

    /// Počty předmětů a deadlinů a tlačítko pro smazání všech dat.
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
            Text("Smaže všechny předměty, deadliny a připomínky i uložený rozvrh, termíny zkoušek a známky. Zároveň se můžeš odhlásit ze STAGu.")
        }
    }

    /// Zda je co mazat.
    ///
    /// Kromě předmětů a deadlinů i rozvrh, termíny, známky nebo přihlášený účet STAG.
    private var hasAnyData: Bool {
        !subjects.isEmpty || !tasks.isEmpty
            || TimetableStore.shared.snapshot != nil
            || !ExamTermStore.shared.terms.isEmpty
            || GradeStore.shared.hasGrades
            || StagAccountStore.shared.isConnected
    }

    /// Text potvrzovacího dialogu smazání, doplněný o zmínku o účtu STAG.
    private var deleteAllMessage: String {
        var text = String(localized: "Smažou se všechny předměty, deadliny a připomínky i uložený rozvrh, termíny zkoušek a známky. Akci nelze vrátit.")
        if StagAccountStore.shared.isConnected {
            text += " " + String(localized: "Účet STAG může zůstat přihlášený, nebo se můžeš rovnou odhlásit.")
        }
        return text
    }

    // MARK: - O aplikaci

    /// Logo, název, verze, odkazy na zásady a podporu a copyright.
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
