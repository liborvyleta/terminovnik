import Foundation
import Testing
@testable import ZavernyProjekt

/// Základní kontrola, že se testovací target sestaví a vidí kód aplikace.
///
/// Obsahuje jediný jednoduchý test nad seznamem škol s IS/STAG.
struct SmokeTests {
    @Test("Všechny školy používají HTTPS")
    func schoolsUseHTTPS() {
        #expect(StagSchool.all.allSatisfy { $0.baseURL.scheme == "https" })
    }
}
