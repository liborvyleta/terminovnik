import Foundation

/// Správné české tvary podle počtu: 1 kredit, 2–4 kredity, 5+ kreditů.
enum CzechPlural {
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        switch abs(count) {
        case 1: one
        case 2...4: few
        default: many
        }
    }

    static func credits(_ count: Int) -> String {
        form(count, one: "kredit", few: "kredity", many: "kreditů")
    }

    static func tasks(_ count: Int) -> String {
        form(count, one: "úkol", few: "úkoly", many: "úkolů")
    }

    static func days(_ count: Int) -> String {
        form(count, one: "den", few: "dny", many: "dní")
    }
}
