import Foundation
import SwiftData

/// Aktualizace předmětů z IS/STAG pomocí uloženého účtu – bez nového přihlášení.
///
/// Načte předměty zapsané v aktuálním semestru: nové přidá, u existujících
/// (shoda kódu bez ohledu na velikost písmen) aktualizuje název a kredity.
/// Nic nemaže – předměty, které uživatel přidal ručně, zůstanou beze změny.
enum StagSubjectSync {
    /// Výsledek jedné aktualizace
    struct SyncResult: Equatable {
        /// Počet nově přidaných předmětů
        var added: Int
        /// Počet existujících předmětů, u kterých se změnil název nebo kredity
        var updated: Int
        /// Kolik předmětů má student ve STAGu zapsaných
        var total: Int

        var hasChanges: Bool { added > 0 || updated > 0 }

        /// Text pro uživatele, např. „Přidáno 2, aktualizováno 1“ nebo „Vše je aktuální“
        var summary: String {
            guard total > 0 else { return String(localized: "V aktuálním semestru nemáš ve STAGu zapsané žádné předměty.") }
            guard hasChanges else { return String(localized: "Vše je aktuální") }
            var parts: [String] = []
            if added > 0 { parts.append(String(localized: "přidáno \(added)", comment: "Počet předmětů přidaných ze STAGu (část věty, první písmeno se zvětší)")) }
            if updated > 0 { parts.append(String(localized: "aktualizováno \(updated)", comment: "Počet předmětů aktualizovaných ze STAGu (část věty)")) }
            let text = parts.joined(separator: ", ")
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }

    /// Chyby aktualizace, které nepocházejí přímo ze STAGu
    nonisolated enum SyncError: LocalizedError {
        case notConnected

        var errorDescription: String? {
            switch self {
            case .notConnected: String(localized: "Nejsi přihlášen do IS/STAG. Přihlas se a zkus to znovu.")
            }
        }
    }

    /// Stáhne zapsané předměty aktuálního semestru a promítne je do databáze.
    /// Při vypršeném přihlášení (`StagError.unauthorized`) účet odhlásí a chybu předá dál.
    static func sync(in context: ModelContext) async throws -> SyncResult {
        try await sync(in: context, store: .shared)
    }

    /// Varianta s konkrétním úložištěm účtu
    static func sync(in context: ModelContext, store: StagAccountStore) async throws -> SyncResult {
        guard let service = store.makeService(), let osCislo = store.account?.osCislo else {
            throw SyncError.notConnected
        }

        do {
            let period = try await service.currentPeriod()
            let stagSubjects = try await service.studentSubjects(
                osCislo: osCislo,
                semester: period.obdobi,
                year: period.akademRok
            )

            // Stávající předměty podle kódu (velká písmena = porovnání bez ohledu na velikost)
            let existing = try context.fetch(FetchDescriptor<Subject>())
            var byCode: [String: Subject] = [:]
            for subject in existing {
                byCode[subject.code.uppercased()] = subject
            }

            // Stejný předmět může přijít víckrát – necháme jen první výskyt, seřadíme podle kódu
            var seen = Set<String>()
            let unique = stagSubjects
                .filter { seen.insert($0.zkratka.uppercased()).inserted }
                .sorted { $0.zkratka < $1.zkratka }

            var added = 0
            var updated = 0

            for stagSubject in unique {
                var name = stagSubject.nazev.flatMap { $0.isEmpty ? nil : $0 }
                var credits = stagSubject.kreditu

                // Chybějící název nebo kredity doplníme z veřejné služby getPredmetInfo.
                // Selhání detailu aktualizaci nezastaví – jen se dané údaje nezmění.
                if name == nil || credits == nil {
                    let detail = try? await service.subjectInfo(
                        department: stagSubject.katedra,
                        code: stagSubject.zkratka,
                        year: stagSubject.rok ?? period.akademRok
                    )
                    name = name ?? detail?.nazev.flatMap { $0.isEmpty ? nil : $0 }
                    credits = credits ?? detail?.kreditu
                }

                let code = stagSubject.zkratka.uppercased()
                if let subject = byCode[code] {
                    var changed = false
                    if let name, subject.name != name {
                        subject.name = name
                        changed = true
                    }
                    if let credits, subject.credits != credits {
                        subject.credits = credits
                        changed = true
                    }
                    if changed { updated += 1 }
                } else {
                    // Každý nový předmět dostane další barvu z palety
                    let subject = Subject(
                        name: name ?? stagSubject.zkratka,
                        code: code,
                        hexColor: SubjectPalette.hex(existing.count + added),
                        credits: credits ?? 0
                    )
                    context.insert(subject)
                    byCode[code] = subject
                    added += 1
                }
            }

            let result = SyncResult(added: added, updated: updated, total: unique.count)
            if result.hasChanges {
                TaskService.save(context)
            }
            store.markSynced()
            return result
        } catch StagError.unauthorized {
            // Ticket vypršel nebo byl zneplatněn – bez nového přihlášení už se nedá nic načíst
            store.signOut()
            throw StagError.unauthorized
        }
    }
}
