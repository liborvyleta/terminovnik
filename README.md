# Termínovník

**Chytrý plánovač zkoušek a deadlinů** pro iOS 17+ ve Swiftu, SwiftUI a SwiftData s architekturou MVVM.
Předměty si načteš přímo z IS/STAG UTB a aplikace ti den před každým termínem pošle připomínku.

## Funkce

- **Přehled (Dashboard).** Nadcházející nesplněné deadliny seřazené od nejbližšího, rozdělené na *Po termínu*, *Dnes a zítra*, *Příštích 7 dní* a *Později*. Každá položka má barevný odpočet („Dnes“, „Zítra“, „Za 5 dní“), typ úkolu a štítek v barvě předmětu.
- **Odškrtnutí jedním klepnutím** na kolečko, s animací a haptickou odezvou. Swipe doprava splní, swipe doleva upraví nebo smaže.
- **Vyhledávání** (`.searchable`) v názvu, předmětu, kódu, typu i poznámce a segmentový přepínač *Vše / Blížící se / Splněné*.
- **Předměty** v kartách s postupem, kredity a nejbližším deadlinem. Detail předmětu ukazuje kroužek postupu a všechny jeho úkoly.
- **Import ze STAGu.** Po přihlášení školním účtem načte jen předměty, které máš zapsané (název, kód, kredity).
- **Formulář deadlinu:** předmět, název, typ (zkouška, zápočet, projekt, úkol), datum a čas, poznámka. Při úpravě i stav a body nebo známka.
- **Lokální notifikace 1 den před termínem** s tlačítkem **„Splněno“** přímo v oznámení. Přeplánuje se při každé změně a zruší se po splnění nebo smazání.
- **Widget** na plochu (malý, střední, velký) a na zamčenou obrazovku s odpočtem do nejbližších deadlinů.
- **Přidat do Kalendáře** ve formuláři i v nabídce po dlouhém stisku řádku. Systémový editor nepotřebuje přístup ke kalendáři.
- **Nastavení:** připojený účet STAG s aktualizací předmětů jedním klepnutím, stav oznámení, návod k widgetu, smazání dat a informace o aplikaci.
- **Prázdné stavy**, úvodní obrazovka při prvním spuštění, plná podpora světlého i tmavého režimu a ikona ve třech variantách.

## Struktura projektu

```
ZavernyProjekt/
├── App/TerminovnikApp.swift          vstupní bod, konfigurace ModelContaineru
├── Models/                           SwiftData modely
│   ├── Subject.swift                 předmět + vazba 1:N na úkoly (cascade)
│   ├── ExamTask.swift                deadline
│   └── TaskType.swift                enum: zkouška, zápočet, projekt, úkol
├── ViewModels/                       logika obrazovek (@Observable)
├── Views/
│   ├── ContentView.swift             záložky + úvodní obrazovka
│   ├── Dashboard/                    přehled, řádek deadlinu, statistiky
│   ├── Subjects/                     seznam, karta, detail, formulář, import ze STAGu
│   ├── Tasks/TaskFormSheet.swift     přidání/úprava deadlinu
│   ├── Onboarding/                   úvodní obrazovka
│   └── Components/                   znovupoužitelné prvky (logo, prázdný stav, štítky…)
├── Services/
│   ├── NotificationManager.swift     lokální notifikace + akce „Splněno“
│   ├── StagService.swift             klient webových služeb IS/STAG
│   ├── StagAccountStore.swift        uložený účet STAG (ticket v Klíčence)
│   ├── StagSubjectSync.swift         aktualizace předmětů ze STAGu
│   ├── WidgetSync.swift              zápis dat pro widget do App Group
│   ├── TaskService.swift             sdílené operace (splnění, mazání)
│   └── SampleData.swift              ukázková data a data pro #Preview
└── Helpers/                          pomocné rozšíření pro modely
Shared/                               kód sdílený aplikací a widgetem (barvy, odpočet, data pro widget)
ZkouskovnikWidget/                    rozšíření s widgety (WidgetKit)
Tools/RenderAppIcon.swift             generátor ikony z AppLogoView
```

### Jak je řešené MVVM se SwiftData

`@Query` funguje jen uvnitř View, protože jen tam se automaticky překresluje při změně dat. View proto data načte a předá je ViewModelu. ViewModel (`@Observable`) řeší filtrování, vyhledávání, seskupení, validaci formulářů a akce. Formuláře drží rozpracované hodnoty ve ViewModelu, takže „Zrušit“ nic nezmění a data se zapíšou až po „Uložit“.

## Nastavení v Xcode

1. Otevři `ZavernyProjekt.xcodeproj` v Xcode 26 nebo novějším.
2. V **Signing & Capabilities** vyber svůj tým, pokud chceš aplikaci spustit na fyzickém iPhonu. Bundle ID si případně změň.
3. Vyber simulátor nebo zařízení s iOS 17+ a spusť aplikaci pomocí ⌘R.

Projekt používá složku synchronizovanou se souborovým systémem. Nové soubory ve složce `ZavernyProjekt/` se do targetu přidají automaticky. Žádné balíčky ani klíče v Info.plist nejsou potřeba.

### Konfigurace ModelContaineru

Kontejner se vytváří jednou v `App/TerminovnikApp.swift` a vkládá se do prostředí celé aplikace:

```swift
@main
struct TerminovnikApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Subject.self, ExamTask.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Nepodařilo se vytvořit ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(modelContainer)   // všechna View pak mají @Query a modelContext
    }
}
```

- `Schema` vyjmenuje modely. Vazbu `Subject.tasks` ↔ `ExamTask.subject` SwiftData odvodí z `@Relationship(deleteRule: .cascade, inverse:)`.
- `isStoredInMemoryOnly: false` ukládá data trvale do SQLite v kontejneru aplikace.
- Previews používají vlastní kontejner v paměti s ukázkovými daty (`SampleData.previewContainer`) nebo prázdný `.modelContainer(for: [...], inMemory: true)`.
- Ve View se k datům přistupuje přes `@Query(sort: \ExamTask.dueDate)` a `@Environment(\.modelContext)`.

## Import předmětů ze STAGu

Aplikace používá veřejné REST rozhraní IS/STAG UTB (`https://stag-ws.utb.cz/ws`).

1. Na úvodní obrazovce nebo v záložce **Předměty** (ikona stažení) zvol **Přihlásit se do IS/STAG**.
2. Systém otevře zabezpečený prohlížeč (`ASWebAuthenticationSession`) s přihlášením UTB.
3. STAG po přihlášení přesměruje na `zkousky://stag-login?stagUserTicket=…&stagUserInfo=…`. Aplikace z toho získá dočasný ticket a osobní číslo studenta.
4. Služba `predmety/getPredmetyByStudent` vrátí předměty zapsané ve zvoleném semestru. Ty, které už v aplikaci máš, jsou označené a nevybírají se.
5. Chybějící kredity se doplní z veřejné služby `predmety/getPredmetInfo`.

**Soukromí:** aplikace heslo nikdy nevidí. Dlouhodobý ticket (`longTicket=1`, platí až 90 dní) se ukládá do Klíčenky, takže import i aktualizace v Nastavení fungují bez nového přihlášení. Odhlášením se ticket smaže. Pro jinou školu stačí změnit `StagService.baseURL`.

## Widget a App Group

Widget nemá přístup k databázi aplikace. Aplikace proto po každé změně zapíše přehled nejbližších deadlinů do sdíleného úložiště App Group `group.devplaceholder.OXGLLP23.zkouskovnik` a widget ho jen čte. Na simulátoru funguje bez dalšího nastavení. Pro fyzický iPhone musí tvůj vývojářský tým povolit schopnost App Groups. Když změníš bundle ID aplikace, uprav i bundle ID widgetu tak, aby jím začínalo.

## Notifikace

- O povolení se aplikace zeptá v kontextu, při prvním uložení deadlinu, jak doporučují Apple Human Interface Guidelines.
- Připomínka přijde přesně 1 den před termínem ve stejný čas. U termínu za méně než 24 hodin se už nenaplánuje a formulář na to upozorní.
- **Rychlý test:** vytvoř deadline na zítřek o 2 minuty později, než je teď. Připomínka přijde za 2 minuty. Banner se ukáže i při otevřené aplikaci.

## První spuštění a ukázková data

- Aplikace startuje s **prázdnou databází**. Úvodní obrazovka nabídne přihlášení do STAGu a import tvých zapsaných předmětů. Jde ji přeskočit a předměty přidat ručně.
- Ukázková data (`SampleData`) slouží jen pro SwiftUI Previews. Pro ruční testování je lze vložit argumentem `-seedSampleData` v **Product → Scheme → Edit Scheme → Run → Arguments**. Ve schématu není nastavený, funguje jen v Debug buildu a jen nad prázdnou databází.
- Pro opakování „prvního spuštění“ aplikaci ze simulátoru smaž. Tím se smaže i databáze a stav úvodní obrazovky.

## Ikona

Logo je nakreslené ve SwiftUI (`Views/Components/AppLogoView.swift`) a stejný kód je použitý na úvodní obrazovce. Ikona se z něj vygeneruje takto:

```bash
swiftc -parse-as-library ZavernyProjekt/Views/Components/AppLogoView.swift \
  Shared/Color+Hex.swift Tools/RenderAppIcon.swift -o /tmp/render-icon
/tmp/render-icon ZavernyProjekt/Assets.xcassets/AppIcon.appiconset
```
