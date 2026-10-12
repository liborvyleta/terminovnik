import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Načtená záloha čekající na potvrzení obnovy.
///
/// Obaluje dekódovaný `BackupFile` jedinečným identifikátorem, aby ji šlo
/// zobrazit přes `.sheet(item:)`. Vzniká v `BackupRestore.open(_:)` – ať už
/// soubor vybral uživatel v Nastavení, nebo přišel z aplikace Soubory.
struct PendingBackup: Identifiable {
    /// Jedinečný identifikátor pro prezentaci sheetu.
    let id = UUID()
    /// Dekódovaný obsah zálohy.
    let backup: BackupFile
}

/// Sdílený stav obnovy zálohy.
///
/// Soubor může přijít z `fileImporter` v `BackupSection` i přes `onOpenURL`
/// v `BackupRestoreHandler`. Drží zálohu čekající na potvrzení, chybovou
/// a výsledkovou zprávu a provádí samotnou obnovu přes `BackupService`,
/// včetně přeplánování připomínek a obnovení widgetu.
@Observable
final class BackupRestore {
    /// Sdílená instance používaná celou aplikací.
    static let shared = BackupRestore()

    /// Záloha čekající na potvrzení v náhledu; `nil`, pokud se nic neobnovuje.
    var pending: PendingBackup?
    /// Chybová zpráva pro alert (selhané čtení nebo obnova).
    var errorMessage: String?
    /// Zpráva o úspěšné obnově se souhrnem změn.
    var resultMessage: String?

    /// Klíč UserDefaults s datem poslední zálohy (TimeInterval od roku 1970).
    static let lastBackupKey = "lastBackupDate"

    /// Přečte soubor zálohy a nabídne jeho náhled.
    ///
    /// Funguje i pro soubory mimo sandbox díky security-scoped URL. V ukázkovém
    /// režimu obnovu odmítne a nastaví `errorMessage`; při chybě dekódování
    /// rovněž nastaví `errorMessage`, jinak naplní `pending`.
    /// - Parameter url: Adresa souboru zálohy.
    func open(_ url: URL) {
        guard !DemoMode.isActive else {
            errorMessage = String(localized: "V ukázkovém režimu nelze obnovit zálohu. Nejdřív ukázkový režim ukonči.")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pending = PendingBackup(backup: try BackupService.decode(data))
        } catch let error as BackupService.BackupError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = BackupService.BackupError.corrupted.localizedDescription
        }
    }

    /// Obnoví zálohu a sladí připomínky a widget.
    ///
    /// V ukázkovém režimu nedělá nic. Při režimu `.replace` nejprve zruší
    /// připomínky všech stávajících úkolů. Po obnově přeplánuje notifikace,
    /// obnoví widget a nastaví `resultMessage` (nebo `errorMessage`);
    /// nakonec vynuluje `pending`.
    /// - Parameters:
    ///   - backup: Záloha k obnovení.
    ///   - mode: Režim obnovy – sloučení, nebo nahrazení.
    ///   - context: SwiftData kontext, do kterého se data zapíší.
    func restore(_ backup: BackupFile, mode: BackupService.RestoreMode, in context: ModelContext) {
        guard !DemoMode.isActive else { return }
        if mode == .replace {
            // Připomínky mazaných úkolů zrušíme dřív, než úkoly zmizí
            for task in (try? context.fetch(FetchDescriptor<ExamTask>())) ?? [] {
                NotificationManager.shared.cancelReminder(for: task)
            }
        }
        do {
            let summary = try BackupService.restore(backup, into: context, mode: mode)
            NotificationManager.shared.rescheduleAll(in: context)
            WidgetSync.refresh(from: context)
            resultMessage = String(localized: "Obnoveno: přidáno \(summary.subjectsAdded + summary.tasksAdded), aktualizováno \(summary.subjectsUpdated + summary.tasksUpdated).")
        } catch {
            errorMessage = String(localized: "Obnovu se nepodařilo dokončit.")
        }
        pending = nil
    }
}

/// Modifikátor, který obsluhuje otevírání a obnovu záloh.
///
/// Zachytává soubory `.terminovnik` přes `onOpenURL`, zobrazuje náhled
/// zálohy (`BackupPreviewView`) s volbou Sloučit / Nahradit a alert
/// s výsledkem či chybou. Stav čte ze sdíleného `BackupRestore`.
/// Vkládá se ke kořenovému view aplikace přes `backupRestoreHandler()`.
struct BackupRestoreHandler: ViewModifier {
    /// SwiftData kontext, do kterého se záloha obnovuje.
    @Environment(\.modelContext) private var context
    /// Sdílený stav obnovy zálohy.
    @State private var restore = BackupRestore.shared

    /// Připojí k obsahu obsluhu URL, sheet náhledu a alert výsledku.
    /// - Parameter content: Obsah, na který se modifikátor aplikuje.
    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard url.isFileURL else { return }
                restore.open(url)
            }
            .sheet(item: $restore.pending) { pending in
                BackupPreviewView(backup: pending.backup) { mode in
                    restore.restore(pending.backup, mode: mode, in: context)
                } onCancel: {
                    restore.pending = nil
                }
            }
            .alert("Obnova zálohy", isPresented: Binding(
                get: { restore.errorMessage != nil || restore.resultMessage != nil },
                set: { if !$0 { restore.errorMessage = nil; restore.resultMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restore.errorMessage ?? restore.resultMessage ?? "")
            }
    }
}

extension View {
    /// Připojí obsluhu otevírání a obnovy záloh (`BackupRestoreHandler`).
    /// - Returns: View s připojeným modifikátorem.
    func backupRestoreHandler() -> some View { modifier(BackupRestoreHandler()) }
}

/// Náhled obsahu zálohy před obnovou.
///
/// Zobrazuje datum vytvoření, počet předmětů a deadlinů a verzi aplikace
/// a nabízí akce Sloučit a Nahradit (nahrazení vyžaduje potvrzení).
/// Prezentuje ho `BackupRestoreHandler` jako sheet.
private struct BackupPreviewView: View {
    /// Záloha, jejíž obsah se zobrazuje.
    let backup: BackupFile
    /// Akce volaná se zvoleným režimem obnovy.
    let onRestore: (BackupService.RestoreMode) -> Void
    /// Akce volaná při zrušení náhledu.
    let onCancel: () -> Void

    /// Zda se zobrazuje potvrzovací dialog nahrazení dat.
    @State private var isConfirmingReplace = false

    /// Formulář se sekcí obsahu zálohy a sekcí akcí, s tlačítkem Zrušit v toolbaru.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Vytvořeno", value: backup.createdAt.formatted(date: .long, time: .shortened))
                    LabeledContent("Předměty", value: "\(backup.subjects.count)")
                    LabeledContent("Deadliny", value: "\(backup.tasks.count)")
                    if let version = backup.appVersion {
                        LabeledContent("Verze aplikace", value: version)
                    }
                } header: {
                    Text("Obsah zálohy")
                }

                Section {
                    Button {
                        onRestore(.merge)
                    } label: {
                        Label("Sloučit", systemImage: "arrow.triangle.merge")
                    }
                    Button(role: .destructive) {
                        isConfirmingReplace = true
                    } label: {
                        Label("Nahradit", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Sloučit: stávající data zůstanou, ze zálohy se přidá, co chybí, a shodné záznamy se přepíší, jen pokud jsou v záloze novější. Nahradit: současné předměty a deadliny se smažou a nahradí zálohou.")
                }
            }
            .navigationTitle("Obnovit zálohu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", action: onCancel)
                }
            }
            .confirmationDialog("Nahradit všechna data zálohou?", isPresented: $isConfirmingReplace, titleVisibility: .visible) {
                Button("Nahradit", role: .destructive) { onRestore(.replace) }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Současné předměty a deadliny se smažou. Akci nelze vrátit.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Sekce Nastavení „Záloha a synchronizace“.
///
/// Umožňuje uložit zálohu předmětů a deadlinů do souboru (`fileExporter`)
/// a obnovit ji ze souboru (`fileImporter` → `BackupRestore`). Zobrazuje
/// datum poslední zálohy z `@AppStorage` a informaci o synchronizaci přes
/// iCloud. V ukázkovém režimu jsou akce vypnuté. Používá se v `SettingsView`.
struct BackupSection: View {
    /// SwiftData kontext, ze kterého se vytváří záloha.
    @Environment(\.modelContext) private var context
    /// Datum poslední úspěšné zálohy (TimeInterval od 1970, 0 = nikdy).
    @AppStorage(BackupRestore.lastBackupKey) private var lastBackup: Double = 0

    /// Připravený dokument zálohy pro export.
    @State private var exportDocument: BackupDocument?
    /// Zda je zobrazen dialog pro uložení souboru.
    @State private var isExporting = false
    /// Zda je zobrazen výběr souboru pro obnovu.
    @State private var isImporting = false
    /// Chybová zpráva exportu zobrazená v patičce sekce.
    @State private var exportError: String?

    /// Sekce s tlačítky zálohy a obnovy, datem poslední zálohy a info o iCloudu.
    var body: some View {
        Section {
            Button {
                prepareExport()
            } label: {
                Label("Zálohovat do souboru", systemImage: "square.and.arrow.up")
            }
            // Ukázkový režim: zálohu nelze vytvořit ani obnovit (smyšlená data nemá smysl ukládat)
            .disabled(DemoMode.isActive)

            Button {
                isImporting = true
            } label: {
                Label("Obnovit ze zálohy", systemImage: "square.and.arrow.down")
            }
            .disabled(DemoMode.isActive)

            LabeledContent("Poslední záloha", value: lastBackupText)

            #if !ICLOUD_SYNC
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synchronizace přes iCloud")
                    Text("Vyžaduje placený Apple Developer účet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "icloud.slash")
            }
            .foregroundStyle(.secondary)
            #endif
        } header: {
            Text("Záloha a synchronizace")
        } footer: {
            Text(DemoMode.isActive
                 ? String(localized: "V ukázkovém režimu je záloha vypnutá – data jsou smyšlená a skutečná data zůstávají beze změny.")
                 : exportError ?? String(localized: "Záloha obsahuje předměty a deadliny včetně poznámek. Ulož ji třeba na iCloud Drive. Přihlašovací údaje do STAGu se nezálohují."))
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .terminovnikBackup,
            defaultFilename: BackupService.fileName()
        ) { result in
            switch result {
            case .success: lastBackup = Date.now.timeIntervalSince1970
            case .failure: exportError = String(localized: "Zálohu se nepodařilo uložit.")
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.terminovnikBackup, .json]) { result in
            if case .success(let url) = result {
                BackupRestore.shared.open(url)
            }
        }
    }

    /// Text s datem poslední zálohy, případně „Nikdy“.
    private var lastBackupText: String {
        guard lastBackup > 0 else { return String(localized: "Nikdy") }
        return Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened)
    }

    /// Vytvoří zálohu z kontextu, zakóduje ji a otevře dialog pro uložení.
    ///
    /// Při chybě nastaví `exportError`.
    private func prepareExport() {
        exportError = nil
        do {
            let backup = try BackupService.makeBackup(from: context)
            exportDocument = BackupDocument(data: try BackupService.encode(backup))
            isExporting = true
        } catch {
            exportError = String(localized: "Zálohu se nepodařilo vytvořit.")
        }
    }
}
