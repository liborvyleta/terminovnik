import Foundation
import Testing
@testable import ZavernyProjekt

/// Zápis na termíny – zpracování odpovědí a volba akce (bez sítě, STAG se nikdy nevolá).
@Suite("STAG – zápis na termíny")
struct StagTermRegistrationTests {

    // MARK: - Odpověď služby

    @Test("„OK“ v různých obalech je úspěch", arguments: ["OK", "ok", " OK \n", "\"OK\"", "\" ok \"", "[\"OK\"]", "{\"result\":\"OK\"}"])
    func okVariants(_ body: String) {
        #expect(StagTermRegistrationResult.parse(Data(body.utf8)) == .success)
    }

    @Test("Jiný text je neúspěch s důvodem ze STAGu")
    func failureReason() {
        let plain = StagTermRegistrationResult.parse(Data("Termín je již plně obsazen.".utf8))
        #expect(plain == .failure("Termín je již plně obsazen."))

        let json = StagTermRegistrationResult.parse(Data(#""Nelze se odhlásit – uplynul termín odhlašování.""#.utf8))
        #expect(json == .failure("Nelze se odhlásit – uplynul termín odhlašování."))
    }

    @Test("Text, který jen začíná na OK, není úspěch")
    func okPrefixIsNotSuccess() {
        #expect(StagTermRegistrationResult.parse(Data("OK, ale ne".utf8)) != .success)
    }

    @Test("Prázdná odpověď je neúspěch s obecnou hláškou")
    func emptyResponse() {
        guard case .failure(let message) = StagTermRegistrationResult.parse(Data()) else {
            Issue.record("Prázdná odpověď nesmí být úspěch")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("Cesty služeb podle dokumentace IS/STAG")
    func servicePaths() {
        #expect(StagTermRegistrationAction.register.path == "terminy/zapisStudentaNaTermin")
        #expect(StagTermRegistrationAction.unregister.path == "terminy/odhlasStudentaZTerminu")
        #expect(StagTermRegistrationAction.joinQueue.path == "terminy/zapisStudentaDoFronty")
        #expect(StagTermRegistrationAction.leaveQueue.path == "terminy/odhlasStudentaZFronty")
    }

    // MARK: - Volba akce

    @MainActor
    @Test("Zapsaný → odhlásit, plný → fronta, ve frontě → opustit frontu, volný → zapsat")
    func actionChoice() {
        let samples = ExamTerm.samples
        #expect(ExamTermsViewModel.registrationAction(for: samples[0], isQueued: false) == .unregister)
        #expect(ExamTermsViewModel.registrationAction(for: samples[1], isQueued: false) == .register)
        #expect(ExamTermsViewModel.registrationAction(for: samples[2], isQueued: false) == .joinQueue)
        #expect(ExamTermsViewModel.registrationAction(for: samples[2], isQueued: true) == .leaveQueue)
        // Proběhlý termín nic nenabízí
        #expect(ExamTermsViewModel.registrationAction(for: samples[1], isQueued: false, now: samples[1].start.addingTimeInterval(60)) == nil)
    }

    @MainActor
    @Test("Kód budovy z místnosti")
    func buildingCode() {
        #expect(ExamTermsViewModel.buildingCode(from: "52/202") == "52")
        #expect(ExamTermsViewModel.buildingCode(from: " U5 / 101 ") == "U5")
        #expect(ExamTermsViewModel.buildingCode(from: "202") == nil)
        #expect(ExamTermsViewModel.buildingCode(from: nil) == nil)
    }
}
