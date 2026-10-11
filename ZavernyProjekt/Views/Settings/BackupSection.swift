import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Načtená záloha čekající na potvrzení obnovy (z Nastavení nebo z aplikace Soubory)
struct PendingBackup: Identifiable {
    let id = UUID()
    let backup: BackupFile
}

/// Sdílený stav obnovy – soubor může přijít z `fileImporter` v Nastavení i přes `onOpenURL`.
@Observable
final class BackupRestore {
    static let shared = BackupRestore()

    var pending: PendingBackup?
    var errorMessage: String?
    var resultMessage: String?

    /// Klíč UserDefaults s datem poslední zálohy (TimeInterval od 1970)
    static let lastBackupKey = "lastBackupDate"

    /// Přečte soubor zálohy (i mimo sandbox – security-scoped URL) a nabídne náhled
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

    /// Obnoví zálohu a sladí připomínky a widget
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

/// Náhled zálohy s volbou Sloučit / Nahradit a otevírání souborů `.terminovnik`.
/// Vkládá se ke kořenovému view aplikace.
struct BackupRestoreHandler: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var restore = BackupRestore.shared

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
    func backupRestoreHandler() -> some View { modifier(BackupRestoreHandler()) }
}

private struct BackupPreviewView: View {
    let backup: BackupFile
    let onRestore: (BackupService.RestoreMode) -> Void
    let onCancel: () -> Void

    @State private var isConfirmingReplace = false

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

/// Sekce Nastavení „Záloha a synchronizace“
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @AppStorage(BackupRestore.lastBackupKey) private var lastBackup: Double = 0

    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportError: String?

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

    private var lastBackupText: String {
        guard lastBackup > 0 else { return String(localized: "Nikdy") }
        return Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened)
    }

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
