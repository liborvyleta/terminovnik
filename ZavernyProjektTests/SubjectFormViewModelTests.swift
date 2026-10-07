import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import ZavernyProjekt

/// Formulář předmětu: výchozí hodnoty, validace, iniciály a živý náhled.
///
/// `save(in:)` se netestuje: přes `TaskService.save` volá `WidgetSync.refresh`,
/// který přepíše data widgetu v App Group uživatele.
@MainActor
@Suite("Formulář předmětu")
struct SubjectFormViewModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - Výchozí hodnoty

    @Test("Nový předmět: prázdný, 5 kreditů, barva z palety")
    func newSubjectDefaults() {
        let viewModel = SubjectFormViewModel()
        #expect(!viewModel.isEditing)
        #expect(viewModel.name.isEmpty)
        #expect(viewModel.code.isEmpty)
        #expect(viewModel.credits == 5)
        #expect(SubjectPalette.entries.map(\.hex).contains(viewModel.hexColor))
        #expect(!viewModel.isValid)
    }

    @Test("Úprava předmětu předvyplní formulář")
    func editingPrefills() {
        let subject = Subject(name: "Datamining", code: "AP9DM", hexColor: "#12A594", credits: 4)
        context.insert(subject)
        let viewModel = SubjectFormViewModel(subject: subject)
        #expect(viewModel.isEditing)
        #expect(viewModel.name == "Datamining")
        #expect(viewModel.code == "AP9DM")
        #expect(viewModel.hexColor == "#12A594")
        #expect(viewModel.credits == 4)
        #expect(viewModel.isValid)
    }

    // MARK: - Validace

    @Test("Povinný je název i kód, mezery se nepočítají")
    func validation() {
        let viewModel = SubjectFormViewModel()
        viewModel.name = "Datamining"
        #expect(!viewModel.isValid)
        viewModel.code = "AP9DM"
        #expect(viewModel.isValid)
        viewModel.name = "   "
        #expect(!viewModel.isValid)
        viewModel.name = "Datamining"
        viewModel.code = " \n "
        #expect(!viewModel.isValid)
    }

    // MARK: - Iniciály

    @Test("Iniciály z prvních dvou slov názvu")
    func initialsFromName() {
        let viewModel = SubjectFormViewModel()
        viewModel.name = "Pokročilé mobilní technologie"
        #expect(viewModel.initials == "PM")
        viewModel.name = "datamining"
        #expect(viewModel.initials == "D")
        viewModel.name = "  úvod do programování  "
        #expect(viewModel.initials == "ÚD")
        // Slova nezačínající písmenem se přeskočí
        viewModel.name = "3D grafika a animace"
        #expect(viewModel.initials == "GA")
    }

    @Test("Bez názvu iniciály z kódu, bez obojího otazník")
    func initialsFallback() {
        let viewModel = SubjectFormViewModel()
        #expect(viewModel.initials == "?")
        viewModel.code = " ap9pt "
        #expect(viewModel.initials == "AP")
        viewModel.name = "123 456"
        #expect(viewModel.initials == "AP")
    }

    @Test("Statické Subject.initials odpovídá modelu")
    func subjectInitials() {
        #expect(Subject.initials(name: "Evoluční výpočetní techniky", code: "AP9EV") == "EV")
        #expect(Subject.initials(name: "", code: "x") == "X")
        #expect(Subject.initials(name: "", code: "") == "")

        let subject = Subject(name: "Bezpečnost informačních systémů", code: "AP9BI", hexColor: "#E5484D")
        context.insert(subject)
        #expect(subject.initials == "BI")
    }

    // MARK: - Náhled

    @Test("Náhled: kód velkými písmeny, kredity, zástupné texty")
    func preview() {
        let viewModel = SubjectFormViewModel()
        #expect(viewModel.previewName == "Název předmětu")
        #expect(viewModel.previewDetail == "KÓD · 5 kreditů")

        viewModel.name = "  Datamining "
        viewModel.code = " ap9dm "
        viewModel.credits = 6
        #expect(viewModel.previewName == "Datamining")
        #expect(viewModel.previewDetail == "AP9DM · 6 kreditů")
    }

    @Test("Náhled barvy používá hex z formuláře")
    func previewColor() {
        let viewModel = SubjectFormViewModel()
        viewModel.hexColor = "#E5484D"
        #expect(viewModel.color == Color(hex: "#E5484D"))
    }
}
