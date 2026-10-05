import AppIntents

/// Zkratky aplikace Termínovník (App Shortcuts).
///
/// Nic se nemusí nastavovat: po instalaci aplikace se zkratky automaticky objeví v aplikaci
/// Zkratky (sekce Termínovník) a ve Spotlightu, kde je jde rovnou spustit.
///
/// Hlasová Siri česky neumí, proto má každá zkratka anglické fráze pro Siri (systém v angličtině).
/// České fráze se uplatní při hledání ve Zkratkách a ve Spotlightu.
/// Každá fráze musí obsahovat `\(.applicationName)` – název aplikace z Info.plist.
nonisolated struct TerminovnikShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextLessonIntent(),
            phrases: [
                "Next class in \(.applicationName)",
                "What's my next class in \(.applicationName)",
                "Další hodina v \(.applicationName)",
                "Kdy mám další hodinu v \(.applicationName)"
            ],
            shortTitle: "Další hodina",
            systemImageName: "clock"
        )

        AppShortcut(
            intent: TimetableForDayIntent(),
            phrases: [
                "What's my schedule in \(.applicationName)",
                "Show my timetable in \(.applicationName)",
                "Rozvrh v \(.applicationName)",
                "Rozvrh na \(\.$day) v \(.applicationName)"
            ],
            shortTitle: "Rozvrh na den",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: NextExamIntent(),
            phrases: [
                "Next exam in \(.applicationName)",
                "What's my next deadline in \(.applicationName)",
                "Nejbližší zkouška v \(.applicationName)",
                "Nejbližší termín v \(.applicationName)"
            ],
            shortTitle: "Nejbližší zkouška",
            systemImageName: "graduationcap"
        )

        AppShortcut(
            intent: AddDeadlineIntent(),
            phrases: [
                "Add a deadline in \(.applicationName)",
                "New deadline in \(.applicationName)",
                "Přidat deadline v \(.applicationName)",
                "Nový deadline v \(.applicationName)"
            ],
            shortTitle: "Přidat deadline",
            systemImageName: "plus.circle"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
