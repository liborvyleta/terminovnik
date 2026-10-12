import Foundation
import Observation
import SwiftData
import AuthenticationServices
import SwiftUI // WebAuthenticationSession je ve spojení SwiftUI + AuthenticationServices

/// ViewModel importu předmětů z IS/STAG.
///
/// Uživatel si zvolí školu, přihlásí se školním účtem ve vestavěném prohlížeči (`WebAuthenticationSession`) a aplikace přes `StagService` načte jen předměty, které má zapsané ve zvoleném semestru. Vybrané předměty uloží do SwiftData a chybějící názvy či kredity doplní z veřejné služby. Připojený účet si pamatuje `StagAccountStore` (ticket v Klíčence, platí až 90 dní), takže při dalším importu se obrazovka rovnou načte bez přihlašování. Používá ho obrazovka importu ze STAGu.
@Observable
final class StagImportViewModel {
    /// Stav obrazovky importu: nečinnost, načítání s popisem, nebo chyba s hláškou.
    enum Status: Equatable {
        case idle
        case loading(String)
        case failed(String)
    }

    /// Aktuální stav načítání nebo chyby zobrazovaný v UI.
    var status: Status = .idle
    /// Semestr, pro který se načítají zapsané předměty („ZS“ / „LS“).
    var semester = "ZS"
    /// Identifikátory předmětů vybraných k importu.
    var selectedIDs: Set<String> = []

    /// Předměty načtené ze STAGu bez duplicit, seřazené podle kódu.
    private(set) var results: [StagSubject] = []
    /// Nadpis seznamu načtených předmětů.
    private(set) var resultsTitle = ""
    /// Aktuální období STAGu (akademický rok a semestr).
    private(set) var period: StagPeriod?

    /// Úložiště připojeného účtu (nil = jen v paměti, např. v náhledech – nesahá do Klíčenky).
    private let accountStore: StagAccountStore?
    /// Účet bez trvalého úložiště (použije se, jen když `accountStore` je nil).
    private var localAccount: StagAccount?
    /// Klient STAGu – po přihlášení / obnovení účtu nese ticket a stagUser.
    private var service: StagService
    /// Škola zvolená pro přihlášení (u připojeného účtu jeho škola).
    private(set) var school: StagSchool
    /// Ověřování vlastní adresy školy.
    private(set) var isValidatingSchool = false
    /// Kódy předmětů, které už v aplikaci jsou (nebudeme je importovat dvakrát).
    private var existingCodes: Set<String> = []

    /// Vytvoří ViewModel; školu převezme z připojeného účtu, jinak z uložené volby.
    /// - Parameter accountStore: Úložiště účtu; `nil` = účet jen v paměti (náhledy).
    init(accountStore: StagAccountStore? = .shared) {
        self.accountStore = accountStore
        let school = accountStore?.account?.resolvedSchool ?? StagSchoolPreference.selected
        self.school = school
        self.service = StagService(baseURL: school.baseURL)
    }

    // MARK: - Výběr školy

    /// Změna školy před přihlášením (zapamatuje se).
    ///
    /// Po přihlášení nebo při stejné škole nic nedělá; jinak vytvoří nového klienta, vynuluje období a znovu ho načte.
    /// - Parameter newSchool: Nově zvolená škola.
    func selectSchool(_ newSchool: StagSchool) {
        guard !isLoggedIn, newSchool != school else { return }
        school = newSchool
        StagSchoolPreference.selected = newSchool
        service = StagService(baseURL: newSchool.baseURL)
        period = nil
        status = .idle
        Task { await loadPeriod() }
    }

    /// Ověří vlastní adresu serveru IS/STAG (musí odpovědět veřejná služba s aktuálním obdobím).
    /// - Parameter address: Adresa zadaná uživatelem.
    /// - Returns: Chybová hláška, nebo `nil` při úspěchu (škola se rovnou vybere).
    func validateCustomSchool(address: String) async -> String? {
        guard let custom = StagSchool.custom(address: address) else {
            return String(localized: "Zadej adresu serveru, např. stag-ws.skola.cz (jen HTTPS).")
        }
        isValidatingSchool = true
        defer { isValidatingSchool = false }
        do {
            _ = try await StagService(baseURL: custom.baseURL).currentPeriod()
            selectSchool(custom)
            return nil
        } catch {
            let host = custom.displayHost
            return String(localized: "Na adrese \(host) jsme IS/STAG nenašli.")
        }
    }

    // MARK: - Odvozený stav

    /// Připojený účet STAG (z úložiště, v náhledech z paměti).
    var account: StagAccount? {
        if let accountStore { return accountStore.account }
        return localAccount
    }

    /// Celé jméno připojeného studenta.
    var studentName: String? { account?.fullName }
    /// Osobní číslo připojeného studenta.
    var osCislo: String? { account?.osCislo }
    /// Fakulta připojeného studenta.
    var faculty: String? { account?.faculty }

    /// Příznak, zda je účet STAG připojený.
    var isLoggedIn: Bool { account != nil }

    /// Příznak, zda právě probíhá načítání.
    var isLoading: Bool {
        if case .loading = status { return true }
        return false
    }

    /// Předměty, které lze vybrat (ještě nejsou v aplikaci).
    var importableResults: [StagSubject] { results.filter { !isAlreadyImported($0) } }

    /// Počet vybraných importovatelných předmětů.
    var selectedCount: Int { importableResults.filter { selectedIDs.contains($0.id) }.count }

    /// Zda jsou vybrané všechny importovatelné předměty (a nějaké existují).
    var allSelected: Bool {
        !importableResults.isEmpty && importableResults.allSatisfy { selectedIDs.contains($0.id) }
    }

    /// Popis aktuálního semestru, např. „Aktuálně zimní semestr …“; bez období `nil`.
    var periodTitle: String? {
        guard let period else { return nil }
        let year = period.academicYearTitle
        return period.obdobi == "ZS"
            ? String(localized: "Aktuálně zimní semestr \(year)")
            : String(localized: "Aktuálně letní semestr \(year)")
    }

    // MARK: - Výběr

    /// Zapamatuje si kódy předmětů, které už v aplikaci jsou.
    /// - Parameter existingSubjects: Předměty uložené v aplikaci.
    func configure(existingSubjects: [Subject]) {
        existingCodes = Set(existingSubjects.map { $0.code.uppercased() })
    }

    /// Zjistí, zda předmět už v aplikaci je (podle kódu bez ohledu na velikost písmen).
    /// - Parameter subject: Předmět ze STAGu.
    /// - Returns: `true`, pokud je předmět už importovaný.
    func isAlreadyImported(_ subject: StagSubject) -> Bool {
        existingCodes.contains(subject.zkratka.uppercased())
    }

    /// Přepne výběr předmětu; již importované předměty ignoruje.
    /// - Parameter subject: Předmět ze STAGu.
    func toggleSelection(_ subject: StagSubject) {
        guard !isAlreadyImported(subject) else { return }
        if selectedIDs.contains(subject.id) {
            selectedIDs.remove(subject.id)
        } else {
            selectedIDs.insert(subject.id)
        }
    }

    /// Vybere všechny importovatelné předměty, nebo – jsou-li všechny vybrané – výběr zruší.
    func toggleSelectAll() {
        selectedIDs = allSelected ? [] : Set(importableResults.map(\.id))
    }

    // MARK: - Načítání ze STAGu

    /// Volá se při otevření obrazovky.
    ///
    /// Je-li účet STAG připojený (a předměty ještě nejsou načtené), rovnou načte aktuální období a zapsané předměty – bez přihlašovací obrazovky. Jinak načte jen období.
    func start() async {
        if let saved = accountStore?.makeService() {
            service = saved
        }
        guard isLoggedIn, results.isEmpty, !isLoading else {
            await loadPeriod()
            return
        }
        status = .loading(String(localized: "Načítám tvoje předměty…"))
        await loadPeriod()
        await loadMySubjects()
    }

    /// Aktuální semestr – podle něj se předvybere ZS/LS.
    ///
    /// Služba je veřejná, volá se proto bez ticketu (neovlivní ji ani vypršené přihlášení). Je-li období už načtené, nic nedělá; chyba se tiše ignoruje.
    func loadPeriod() async {
        guard period == nil else { return }
        if let current = try? await StagService(baseURL: (account?.resolvedSchool ?? school).baseURL).currentPeriod() {
            period = current
            semester = current.obdobi
        }
    }

    /// Přihlášení přes webovou stránku STAGu.
    ///
    /// Systém otevře zabezpečený prohlížeč, po přihlášení STAG přesměruje na `zkousky://stag-login?stagUserTicket=…`. Relace prohlížeče je dočasná (`.ephemeral`) – SSO přihlášení školy nezůstane sdílené se Safari a po odhlášení ze STAGu se další uživatel bez hesla nepřihlásí. Po přihlášení uloží účet, načte předměty a případně požádá o povolení oznámení. Zrušení přihlášení uživatelem se nebere jako chyba.
    /// - Parameter session: Webová autentizační relace z prostředí SwiftUI.
    func login(using session: WebAuthenticationSession) async {
        status = .loading(String(localized: "Přihlašování do IS/STAG…"))
        do {
            let callbackURL = try await session.authenticate(
                using: StagService.loginURL(baseURL: school.baseURL),
                callbackURLScheme: StagService.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            let (ticket, attachedInfo) = try StagService.parseLoginCallback(callbackURL)
            service = StagService(baseURL: school.baseURL, ticket: ticket)

            // Role uživatele STAG obvykle přiloží rovnou, jinak si je vyžádáme službou.
            let info: StagUserInfo
            if let attachedInfo {
                info = attachedInfo
            } else {
                info = try await service.userInfo(forTicket: ticket)
            }
            guard let student = info.studentRoles.first, let number = student.osCislo else {
                throw StagError.noStudentRole
            }

            service.stagUser = student.userName
            // Účet si zapamatujeme – příště se už přihlašovat nemusí (ticket platí až 90 dní)
            let account = StagAccount(
                fullName: info.fullName.isEmpty ? student.userName : info.fullName,
                osCislo: number,
                stagUser: student.userName,
                faculty: student.fakulta,
                connectedAt: .now,
                school: school
            )
            if let accountStore {
                try accountStore.connect(account, ticket: ticket)
            } else {
                localAccount = account
            }

            await loadPeriod()
            await loadMySubjects()

            // Připomínky zkoušek, hodin a nových termínů potřebují povolená oznámení.
            // Zeptáme se až po načtení předmětů (dialog nebrzdí import), a jen pokud to ještě nebylo rozhodnuto.
            if accountStore != nil {
                await NotificationManager.shared.requestAuthorizationIfNeeded()
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = .idle  // uživatel přihlášení zavřel – nejde o chybu
        } catch {
            fail(error)
        }
    }

    /// Načte předměty zapsané ve zvoleném semestru a předvybere ty, které v aplikaci ještě nejsou.
    func loadMySubjects() async {
        guard let osCislo else { return }
        guard let year = period?.akademRok else {
            status = .failed(String(localized: "Nepodařilo se zjistit aktuální akademický rok."))
            return
        }
        status = .loading(String(localized: "Načítám tvoje předměty…"))
        do {
            let subjects = try await service.studentSubjects(osCislo: osCislo, semester: semester, year: year)
            show(
                subjects,
                title: semester == "ZS"
                    ? String(localized: "Zapsané předměty – zimní semestr")
                    : String(localized: "Zapsané předměty – letní semestr"),
                emptyMessage: String(localized: "V tomto semestru nemáš ve STAGu zapsané žádné předměty.")
            )
        } catch {
            fail(error)
        }
    }

    // MARK: - Import do SwiftData

    /// Vytvoří vybrané předměty. Chybějící kredity a názvy doplní z veřejné služby getPredmetInfo.
    ///
    /// Každý předmět dostane jinou barvu z palety; po uložení označí účet jako synchronizovaný a výběr vyprázdní.
    /// - Parameter context: SwiftData kontext, do kterého se předměty vkládají.
    /// - Returns: Počet importovaných předmětů.
    func importSelected(into context: ModelContext) async -> Int {
        let chosen = importableResults.filter { selectedIDs.contains($0.id) }
        guard !chosen.isEmpty else { return 0 }

        status = .loading(String(localized: "Importuji \(chosen.count) předmětů…"))
        var colorIndex = existingCodes.count

        for stagSubject in chosen {
            var name = stagSubject.nazev
            var credits = stagSubject.kreditu

            if name == nil || credits == nil, let year = stagSubject.rok ?? period?.akademRok {
                let detail = try? await service.subjectInfo(
                    department: stagSubject.katedra,
                    code: stagSubject.zkratka,
                    year: year
                )
                name = name ?? detail?.nazev
                credits = credits ?? detail?.kreditu
            }

            // Každý importovaný předmět dostane jinou barvu z palety
            let subject = Subject(
                name: name ?? stagSubject.zkratka,
                code: stagSubject.zkratka.uppercased(),
                hexColor: SubjectPalette.hex(colorIndex),
                credits: credits ?? 0
            )
            context.insert(subject)
            existingCodes.insert(subject.code)
            colorIndex += 1
        }

        TaskService.save(context)
        accountStore?.markSynced()
        selectedIDs.removeAll()
        status = .idle
        return chosen.count
    }

    // MARK: - Pomocné

    /// Odhlášení – smaže ticket z Klíčenky, uložený účet i načtená data.
    func logout() {
        forgetAccount()
        status = .idle
    }

    /// Zapomene účet: odhlásí ho v úložišti, vytvoří klienta bez ticketu a vymaže výsledky i výběr.
    private func forgetAccount() {
        accountStore?.signOut()
        localAccount = nil
        service = StagService(baseURL: school.baseURL)
        results = []
        resultsTitle = ""
        selectedIDs = []
    }

    /// Zobrazí načtené předměty bez duplicit, seřazené podle kódu, a předvybere importovatelné.
    /// - Parameters:
    ///   - subjects: Předměty ze STAGu.
    ///   - title: Nadpis seznamu.
    ///   - emptyMessage: Hláška zobrazená jako chyba, když je seznam prázdný.
    private func show(_ subjects: [StagSubject], title: String, emptyMessage: String) {
        // Odstraníme duplicity (stejný předmět může přijít víckrát) a seřadíme podle kódu
        var seen = Set<String>()
        results = subjects
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.zkratka < $1.zkratka }
        resultsTitle = title
        // Předvybereme vše, co v aplikaci ještě není
        selectedIDs = Set(importableResults.map(\.id))
        status = results.isEmpty ? .failed(emptyMessage) : .idle
    }

    /// Zpracuje chybu; při vypršeném ticketu účet odpojí a vyzve k novému přihlášení.
    /// - Parameter error: Zachycená chyba.
    private func fail(_ error: Error) {
        if let stagError = error as? StagError, case .unauthorized = stagError {
            // Ticket vypršel – účet odpojíme a vrátíme se k tlačítku přihlášení
            forgetAccount()
            status = .failed(String(localized: "Přihlášení do STAGu vypršelo, přihlas se znovu."))
            return
        }
        status = .failed(error.localizedDescription)
    }
}

#if DEBUG
// MARK: - Náhled

/// Náhledové instance ``StagImportViewModel`` pro #Preview.
extension StagImportViewModel {
    /// Stav po přihlášení s reálnými předměty UTB – pro #Preview, bez sítě, Klíčenky a přihlášení.
    static var previewLoggedIn: StagImportViewModel {
        let viewModel = StagImportViewModel(accountStore: nil)
        viewModel.localAccount = StagAccount(
            fullName: "Jan Novák",
            osCislo: "A23456",
            stagUser: "st23456",
            faculty: "FAI",
            connectedAt: .now
        )
        viewModel.period = StagPeriod(obdobi: "ZS", akademRok: "2026")
        viewModel.show(
            [
                StagSubject(katedra: "AUIUI", zkratka: "AP9PT", nazev: "Pokročilé mobilní technologie", kreditu: 4, rok: "2026"),
                StagSubject(katedra: "AUIUI", zkratka: "AP9DM", nazev: "Datamining", kreditu: 5, rok: "2026"),
                StagSubject(katedra: "AUIUI", zkratka: "AP9BI", nazev: "Bezpečnost informačních systémů", kreditu: 5, rok: "2026"),
                StagSubject(katedra: "AUIUI", zkratka: "AP9SS", nazev: "Simulace systémů", kreditu: 5, rok: "2026"),
                StagSubject(katedra: "AUIUI", zkratka: "AP9VH", nazev: "Vývoj počítačových her", kreditu: 4, rok: "2026")
            ],
            title: String(localized: "Zapsané předměty – zimní semestr"),
            emptyMessage: ""
        )
        return viewModel
    }
}
#endif
