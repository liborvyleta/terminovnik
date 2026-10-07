# Bezpečnostní a compliance audit – Termínovník

| | |
|---|---|
| **Datum** | 7. 10. 2026 |
| **Rozsah** | commit `fcfdb1e` + rozpracované (necommitnuté) změny pracovního stromu ke dni auditu: výběr školy (`Models/StagSchool.swift`), lokalizace, testy |
| **Cíle** | aplikace `ZavernyProjekt` (iOS 17+), rozšíření `ZkouskovnikWidgetExtension` (widgety + Live Activity), App Intents |
| **Metoda** | statická kontrola kódu, `Info.plist`, entitlements a `project.pbxproj`; aplikace se nespouštěla |
| **Měřítko** | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) ([CZ](https://developer.apple.com/app-store/review/guidelines/cz/)), [Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), obecné zásady bezpečnosti iOS |

> Čísla řádků odpovídají pracovnímu stromu ke dni auditu. Kód paralelně upravují další úpravy, proto je u každého nálezu uvedený i název typu nebo funkce.

---

## 1. Shrnutí

**Aplikace zatím není připravená k odeslání do App Review.** Technicky je postavená dobře. Heslo nikdy nevidí, ticket je v Klíčence, komunikace jde jen přes HTTPS, aplikace nemá žádné SDK třetích stran ani sledování a o oprávnění žádá v kontextu. Chybí ale několik povinných náležitostí. Bez nich App Store Connect build nepřijme, nebo ho App Review zamítne.

**Co odeslání blokuje:**

1. **K-01: chybí Privacy Manifest** (`PrivacyInfo.xcprivacy`) v aplikaci i ve widgetu. Aplikace i widget používají `UserDefaults`, což je required reason API. Od 1. 5. 2024 App Store Connect takový build odmítne (ITMS-91053).
2. **K-02: chybí zásady ochrany osobních údajů.** Podle 5.1.1(i) musí být odkaz na zásady v App Store Connect i přímo v aplikaci.
3. **V-01: App Review se nedostane k hlavním funkcím.** Rozvrh, termíny zkoušek, upozornění na nové termíny a widget „Další hodina“ vyžadují studentský účet IS/STAG. Podle 2.1 je nutné dodat demo účet, nebo vestavěný ukázkový režim schválený Applem.
4. **V-02: bundle ID a App Group mají zástupné hodnoty** (`devplaceholder.OXGLLP23…`). Po prvním nahrání build se bundle ID už nedá změnit.
5. **V-03: chybí svolení k použití služby a názvů** (5.2.1, 5.2.2). Aplikace volá webové služby IS/STAG a uvádí názvy UTB a dalších šesti univerzit. Zároveň působí, že s nimi souvisí („Závěrečný projekt AP9PT · UTB FAI“).

Po opravě kritických a vysokých nálezů a po ručních krocích v kapitole 7 je šance na schválení dobrá. Aplikace má bohatou nativní funkčnost (4.2) a funguje i bez přihlášení (5.1.1(v)).

| Závažnost | Počet |
|---|---|
| Kritická | 2 |
| Vysoká | 3 |
| Střední | 5 |
| Nízká | 10 |
| Info | 8 |

---

## 2. Jaká osobní data aplikace zpracovává

### 2.1 Co a kde je uloženo

| Údaj | Zdroj | Kde je uložený | Ochrana | Kdy se smaže |
|---|---|---|---|---|
| Ticket IS/STAG (bearer token, platí až 90 dní, `longTicket=1`) | návratová adresa po přihlášení | Klíčenka, `kSecClassGenericPassword`, service `cz.utb.zkouskovnik.stag`, account `stagTicket` | `AfterFirstUnlockThisDeviceOnly`, nesynchronizuje se, nepřenese se na jiné zařízení | odhlášení, automaticky při 401/403, při prvním spuštění po přeinstalaci |
| Jméno a příjmení, osobní číslo, uživatelské jméno (`stagUser`), fakulta, škola (URL serveru), časy připojení a synchronizace | `stagUserInfo` | `UserDefaults.standard`, klíč `stagAccount.v1` (plist v `Library/Preferences`) | výchozí Data Protection (`CompleteUntilFirstUserAuthentication`), je v zálohách zařízení | odhlášení |
| Rozvrh: předměty, místnosti, **jména vyučujících včetně titulů**, časy | `rozvrhy/getRozvrhByStudent` | App Group `UserDefaults`, klíč `timetableSnapshot.v1` (čte ho widget) | výchozí | odhlášení |
| Termíny zkoušek: zkoušející, obsazenost, poznámky, stav zápisu | `terminy/getTerminyProStudenta` | App Group `UserDefaults`, klíče `examTerms.v1`, `examTerms.seenIDs`, `examTerms.newIDs` | výchozí | odhlášení |
| Předměty, deadliny, poznámky, body a známky (`pointsOrGrade`) a zkoušky vytvořené ze zapsaných termínů (s místností a zkoušejícím) | uživatel a STAG | SwiftData (SQLite) v kontejneru App Group (`Library/Application Support/default.store`) | výchozí | „Smazat všechna data“ nebo smazání aplikace. **Odhlášení je nemaže.** |
| Data pro widget (12 nejbližších deadlinů) | SwiftData | App Group `UserDefaults`, `widgetSnapshot.v1` | výchozí | přepíše se při každé změně |
| Obsah oznámení a Live Activity: předmět, název, místnost, vyučující | aplikace | systém (zamčená obrazovka, Centrum oznámení) | podle systémového nastavení náhledů | doručená oznámení zůstávají |
| HTTP cache a cookies ze STAG API | `URLSession.shared` | `Library/Caches/<bundle-id>/Cache.db`, `Library/Cookies` (podle hlaviček serveru) | výchozí | **nemaže se** (S-02) |
| SSO cookies školního přihlášení | `ASWebAuthenticationSession` (sdílená relace se Safari) | úložiště cookies Safari | | **nemaže se** (N-01) |

### 2.2 Co odchází ze zařízení

Data jdou **jen na server IS/STAG školy, kterou si uživatel zvolil**. Ticket je svázaný s účtem a jeho školou (`StagAccount.school`), takže se nepošle na jiný server. Odchází:

- ticket v hlavičce `Authorization: Basic …`, kromě jedné záložní služby, viz N-02,
- v query parametrech osobní číslo (`osCislo`), `stagUser`, semestr, rok, katedra a zkratka předmětu.

Žádný server vývojáře, analytika, sledování ani SDK třetích stran. Aplikace tak data **nesbírá** ve smyslu App Privacy (kapitola 5).

---

## 3. Tabulka nálezů

| ID | Závažnost | Oblast | Pravidlo | Soubor:řádek | Popis | Doporučená oprava |
|---|---|---|---|---|---|---|
| K-01 | **Kritická** | Privacy Manifest | 5.1.1, 5.1.2; Required Reason API (ITMS-91053) | chybí `ZavernyProjekt/PrivacyInfo.xcprivacy` a `ZkouskovnikWidget/PrivacyInfo.xcprivacy`; použití: `Services/StagAccountStore.swift:40`, `Shared/WidgetSnapshot.swift:7`, `@AppStorage` ve View | Aplikace používá `UserDefaults.standard` i `UserDefaults(suiteName:)` (App Group), widget App Group. Chybí deklarace důvodů, takže App Store Connect build odmítne. | Přidat dva manifesty s přesným obsahem z kapitoly 4, K-01: aplikace `CA92.1` + `1C8F.1`, widget `1C8F.1`, `NSPrivacyTracking=false`, prázdné `NSPrivacyCollectedDataTypes`. |
| K-02 | **Kritická** | Zásady ochrany osobních údajů | 5.1.1(i) | `Views/Settings/SettingsView.swift:239` (`aboutSection`), `Views/Subjects/StagImportView.swift` (přihlášení), `Views/Onboarding/OnboardingView.swift` | V aplikaci není odkaz na zásady ochrany osobních údajů a zásady neexistují. Pole Privacy Policy URL v App Store Connect je povinné. | Zveřejnit zásady na veřejné URL (osnova v kapitole 4, K-02). Přidat `Link` do sekce „O aplikaci“ a odkaz pod tlačítko přihlášení do STAGu. |
| V-01 | **Vysoká** | Přístup pro App Review | 2.1(a), 2.3.1(a) | `Views/Subjects/StagImportView.swift`, `App/TerminovnikApp.swift:20-25` (`-seedSampleData` jen v DEBUG) | Rozvrh, termíny, nové termíny, widget „Další hodina“ a Live Activity hodin vyžadují reálný studentský účet. Reviewer žádný nemá. | Získat od UTB testovací studentský účet, nebo přidat viditelný „Ukázkový režim“ (se svolením Applu). Do Review Notes popsat přihlášení a přiložit video (kapitola 4, V-01). |
| V-02 | **Vysoká** | Identifikátory | 2.1; App ID je po prvním nahrání neměnné | `project.pbxproj:393, 437, 468, 497` (`PRODUCT_BUNDLE_IDENTIFIER = devplaceholder.…`), `ZavernyProjekt.entitlements:7`, `ZkouskovnikWidget.entitlements:7`, `Shared/WidgetSnapshot.swift:5`, `Info.plist` + `Services/BackgroundRefresh.swift:11` (`cz.utb.terminovnik.refresh`), `Services/KeychainStore.swift:6` (`cz.utb.zkouskovnik.stag`) | Bundle ID a App Group mají zástupné hodnoty Xcode. Identifikátory úlohy na pozadí a Klíčenky používají doménu `cz.utb`, která autorovi nepatří. | Zvolit vlastní reverzní doménu, například `cz.vyleta.terminovnik`. Změnit ji na všech uvedených místech (kapitola 4, V-02). Widget musí mít prefix `…terminovnik.widget`. |
| V-03 | **Vysoká** | Duševní vlastnictví, služba třetí strany | 5.2.1, 5.2.2, 2.3.7 | `Views/Settings/SettingsView.swift:259` („Závěrečný projekt AP9PT · UTB FAI“), `Models/StagSchool.swift:23-38` (7 univerzit), `Services/StagService.swift` (STAG API) | Aplikace volá webové služby IS/STAG a uvádí názvy univerzit bez doloženého svolení. Text v „O aplikaci“ budí dojem oficiální aplikace UTB. Podle 5.2.2 musí být svolení na požádání doložitelné. | Získat písemné svolení správce IS/STAG na UTB, případně omezit seznam škol na ty se svolením. Přidat prohlášení „neoficiální aplikace“ (kapitola 4, V-03). Nepoužívat loga škol, v metadatech nepsat „UTB“ ani „STAG“ jako klíčová slova. |
| S-01 | Střední | Kontakt na vývojáře | 1.5 | `Views/Settings/SettingsView.swift:239` (`aboutSection`) | V aplikaci není kontakt ani odkaz na podporu. 1.5 to zdůrazňuje u aplikací používaných ve výuce. | Do „O aplikaci“ přidat `Link` na Support URL a `mailto:` (kapitola 4, S-01). Stejnou Support URL uvést v App Store Connect. |
| S-02 | Střední | Síť, ukládání dat | 5.1.1(i) (retence a mazání); OWASP MASVS-STORAGE | `Services/StagService.swift:379` (`var session: URLSession = .shared`) | `URLSession.shared` může ukládat odpovědi s osobními daty (rozvrh, termíny, jméno a role) do `Cache.db` a cookies ze STAGu do `Library/Cookies`. Odhlášení je nemaže. | Pro STAG použít `URLSessionConfiguration.ephemeral` bez cache a cookies. Při odhlášení jednorázově vyčistit `URLCache.shared` a cookies (kapitola 4, S-02). |
| S-03 | Střední | Osobní údaje třetích osob | 5.1.1, 5.2.1, GDPR | `Shared/TimetableSnapshot.swift:180-184`, `Models/ExamTerm.swift:71` | Ukázková data v Release buildu (náhled a galerie widgetů, Previews, budoucí screenshoty) obsahují **skutečná jména vyučujících UTB** (Ing. F. Vabroušek, Ing. A. Viktorin, doc. R. Šenkeřík, doc. P. Šilhavý). | Nahradit je smyšlenými jmény (např. „Ing. Jan Novák“, „doc. Ing. Eva Dvořáková, Ph.D.“). Na screenshotech používat jen smyšlená data. |
| S-04 | Střední | Stabilita | 2.1(a) (pády) | `Services/PersistenceController.swift:12-16` | Když se úložiště SwiftData nepodaří otevřít (chyba migrace, poškozený soubor, spuštění na pozadí před prvním odemčením), `fatalError` aplikaci shodí, a to i v App Intents a úloze na pozadí. Schéma nemá `VersionedSchema` ani `SchemaMigrationPlan`. | Místo `fatalError` použít záložní řešení: zalogovat chybu, přepnout na úložiště v paměti a zobrazit upozornění. Před další změnou modelů zavést `VersionedSchema` + `SchemaMigrationPlan` (kapitola 4, S-04). |
| S-05 | Střední | Mazání dat a odhlášení | 5.1.1(i), 5.1.1(ii) (odvolání souhlasu) | `Services/StagAccountStore.swift:70-76` (`signOut`), `ViewModels/SettingsViewModel.swift:125` (`deleteAllData`), `Views/Settings/SettingsView.swift:218` | Odhlášení nemaže HTTP cache a cookies, SSO cookies, běžící Live Activity (`LiveActivityManager.endAll()` se nevolá) ani doručená oznámení. „Smazat všechna data“ nemaže snímky rozvrhu a termínů, účet ani ticket. Pokud v aplikaci není žádný předmět, tlačítko je navíc neaktivní. | Do `signOut()` doplnit `LiveActivityManager.shared.endAll()`, `removeAllDeliveredNotifications()` a vyčištění cache. Přidat volbu „Smazat vše včetně účtu STAG“, která odhlásí, smaže SwiftData, App Group i UserDefaults. Popsat to v zásadách (kapitola 4, S-05). |
| N-01 | Nízká | Přihlášení | 4.8 (výjimka platí); best practice | `ViewModels/StagImportViewModel.swift:169-172` | `WebAuthenticationSession` běží ve sdílené relaci se Safari. SSO přihlášení školy proto přežije „Odhlásit ze STAGu“ a další člověk na stejném zařízení se přihlásí bez hesla. Systém navíc zobrazí dialog „… chce k přihlášení použít …“. | Volat `authenticate(using:callbackURLScheme:preferredBrowserSession: .ephemeral)` (iOS 16.4+). |
| N-02 | Nízká | Ticket | best practice | `Services/StagService.swift:455-456` (`userInfo(forTicket:)`), `:391-398` (`longTicket=1`) | V záložní službě `getStagUserListForLoginTicket` jde ticket v query URL, kde může skončit v logu serveru nebo proxy. Ticket platí 90 dní a odhlášení ho na serveru nezneplatní. | Volat službu jen s hlavičkou `Authorization` (ticket už v ní je) a parametr `ticket` posílat, jen pokud ho server vyžaduje. Ověřit v dokumentaci IS/STAG, zda jde ticket zneplatnit, a při odhlášení to zavolat. |
| N-03 | Nízká | Klíčenka | robustnost | `Services/KeychainStore.swift:17-37`, `Services/StagAccountStore.swift:39-49, 57-61` | `string(for:)` vrací `nil` při jakékoli chybě, tedy i `errSecInteractionNotAllowed`, a `init` pak účet i ticket smaže. `set` maže a přidává neatomicky a chybu jen vypíše, takže `connect()` „uspěje“ i bez uloženého ticketu. | Rozlišit `errSecItemNotFound` od ostatních chyb. Úklid po přeinstalaci řídit značkou v `UserDefaults`. `set` udělat přes `SecItemUpdate`, při `errSecItemNotFound` přes `SecItemAdd`, a vracet `Bool`/`throws` (kapitola 4, N-03). |
| N-04 | Nízká | Zamčené zařízení | 5.1.1; HIG | `Services/NotificationManager.swift:35-39` (akce „Splněno“ `options: []`), `Intents/DeadlineIntents.swift:51-54` (`AddDeadlineIntent`) | Akce v oznámení i Siri a Zkratky jdou spustit na zamčeném zařízení bez odemčení. Kdokoli s telefonem může odškrtnout nebo přidat deadline a nechat si přečíst rozvrh. | `UNNotificationAction(…, options: [.authenticationRequired])`. V `AddDeadlineIntent` nastavit `static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication`, pro čtecí intenty zvážit totéž. |
| N-05 | Nízká | Zamčená obrazovka | 5.1.1(iv) | `ZkouskovnikWidget/DeadlineWidget.swift:14-17`, `NextClassWidget.swift:14-17` (`accessory*`), `Services/LiveActivityManager.swift:40`, `Views/Settings/SettingsView.swift:19` | Widgety na zamčené obrazovce a automatická Live Activity (ve výchozím stavu **zapnutá**) ukazují předmět, místnost a vyučujícího bez odemčení. | Texty v `accessory*` widgetech označit `.privacySensitive()`. Automatickou Live Activity nechat ve výchozím stavu vypnutou, nebo ji nabídnout v onboardingu. |
| N-06 | Nízká | Vlastní server školy (rozpracováno) | 5.1.1; phishing | `Models/StagSchool.swift:47-62` (`custom(address:)`) | Uživatel může zadat libovolný HTTPS server a jeho přihlašovací stránka se otevře v systémovém okně, což zneužije phishing („použij server stag-ws.skola-login.cz“). `URLComponents` nemaže `user`/`password` z adresy. | Vynulovat `components.user` a `password`, zobrazit celý host na tlačítku přihlášení a přidat varování „Heslo zadávej jen na serveru své školy“. Zvážit, zda vlastní server ve verzi pro App Store vůbec nabízet. |
| N-07 | Nízká | Export compliance | App Store Connect, exportní pravidla USA | `ZavernyProjekt/Info.plist`, `project.pbxproj` | Chybí `ITSAppUsesNonExemptEncryption`. App Store Connect se proto na šifrování ptá u každého buildu. | Do `ZavernyProjekt/Info.plist` přidat `<key>ITSAppUsesNonExemptEncryption</key><false/>`. Aplikace používá jen HTTPS přes systémová API, což je výjimka. |
| N-08 | Nízká | Oprávnění, funkčnost | 2.1, 4.5.4 | `Views/Tasks/TaskFormSheet.swift:50` (jediné místo mimo Nastavení), `ViewModels/StagImportViewModel.swift` (`login`), `Services/StagService.swift:484` | O oznámení se aplikace ptá jen při ručním uložení deadlinu. Kdo použije jen import ze STAGu, nedostane připomínky zkoušek, hodin ani nových termínů a neví proč. HTTP 403 se navíc bere jako vypršené přihlášení a uživatele odhlásí. | Po úspěšném přihlášení do STAGu ukázat vysvětlení a zavolat `requestAuthorization()`. Rozlišit 401 (`unauthorized` → odhlásit) od 403 (`forbidden` → jen zobrazit chybu). |
| N-09 | Nízká | Uložení osobních údajů | MASVS-STORAGE | `Services/StagAccountStore.swift:40, 86` | Jméno a osobní číslo jsou v čitelném plistu `UserDefaults`. Ten je součástí nešifrovaných záloh v počítači. | Přijatelné, ale lepší je uložit `StagAccount` (JSON) také do Klíčenky (`ThisDeviceOnly`), nebo to aspoň popsat v zásadách. |
| N-10 | Nízká | iPad, metadata | 2.1, 2.3 | `project.pbxproj:404, 448` (`TARGETED_DEVICE_FAMILY = "1,2"`), `Views/Settings/SettingsView.swift` (přepínač Live Activity) | Aplikace je univerzální, takže ji App Review otestuje i na iPadu a App Store Connect vyžaduje iPad screenshoty. Live Activity na iPadu nefungují, ale přepínač je vidět. | Otestovat UI na iPadu a dodat screenshoty 13". Přepínač skrýt, když `!ActivityAuthorizationInfo().areActivitiesEnabled`. Případně aplikaci omezit jen na iPhone (`TARGETED_DEVICE_FAMILY = 1`). |
| I-01 | Info | Login Services | 4.8 | – | Přihlášení školním účtem spadá pod výjimku 4.8 („vzdělávací … aplikace, která vyžaduje přihlášení k existujícímu školnímu účtu“). Přihlášení navíc není povinné. Sign in with Apple není potřeba. | Nic, jen to zmínit v Review Notes. |
| I-02 | Info | Smazání účtu | 5.1.1(v) | – | Aplikace účty nezakládá, jen se připojuje k existujícímu, takže povinnost smazat účet v aplikaci neplatí. Odhlášení existuje. | Uvést v Review Notes („no account creation“). |
| I-03 | Info | Režim na pozadí | 2.5.4 | `ZavernyProjekt/Info.plist` (`UIBackgroundModes = fetch`, `BGTaskSchedulerPermittedIdentifiers`) | `fetch` se používá k zamýšlenému účelu (`BGAppRefreshTask`: obnova termínů a rozvrhu). Jiné režimy nejsou deklarované. | Popsat v Review Notes, jak to ověřit. |
| I-04 | Info | Kalendář | 5.1.1(iii) | `Views/Components/CalendarEventEditor.swift` | `EKEventEditViewController` běží od iOS 17 mimo proces aplikace. Oprávnění ani purpose string nejsou potřeba, aplikace kalendář nečte. | Ověřit na zařízení, že uložení funguje bez `NSCalendars…UsageDescription`. |
| I-05 | Info | Data Protection | – | entitlements | Výchozí třída `CompleteUntilFirstUserAuthentication` je správná, protože widget a úloha na pozadí čtou data při zamčeném zařízení. `NSFileProtectionComplete` by je rozbilo. | Neměnit. |
| I-06 | Info | Logování | – | 9 volání `print` (např. `Services/KeychainStore.swift:24`) | Žádné nevypisuje ticket ani osobní údaje. | Přejít na `os.Logger` s `privacy: .private` u dynamických hodnot, aby to tak zůstalo. |
| I-07 | Info | Build nastavení | – | `project.pbxproj:373-375, 417-419` | `ENABLE_APP_SANDBOX` a `ENABLE_USER_SELECTED_FILES` jsou nastavení pro macOS. Na iOS se ignorují, ale matou. Debug kód je za `#if DEBUG` (`-seedSampleData`, `startDemoLesson`, náhledové ViewModely). | Volitelně tato nastavení odstranit. |
| I-08 | Info | 5.1.1(viii) | 5.1.1(viii) | – | Jména vyučujících pocházejí z rozvrhu, který si uživatel načetl ze svého účtu. Aplikace nevytváří databázi osob, takže pravidlo není porušené. | Nic. |

---

## 4. Detail vybraných nálezů a přesné opravy

### K-01: Privacy Manifest

**Kde se používají required reason API (kategorie `NSPrivacyAccessedAPICategoryUserDefaults`):**

- aplikace: `UserDefaults.standard` (`StagAccountStore`, `StagSchoolPreference`, `ClassReminderScheduler`, `LiveActivityManager`, `ExamTermStore`) a `@AppStorage` (`ContentView`, `SettingsView`, `DashboardView`, `SubjectDetailView`, `TimetableView`) → důvod **CA92.1** („informace dostupné jen aplikaci samotné“),
- aplikace i widget: `UserDefaults(suiteName: AppGroup.identifier)` (`Shared/WidgetSnapshot.swift`, `Shared/TimetableSnapshot.swift`, `ExamTermStore`) → důvod **1C8F.1** („informace dostupné jen členům stejné App Group“).

Jiná required reason API (časová razítka souborů, čas od spuštění systému, volné místo na disku, aktivní klávesnice) kód aplikace přímo nevolá. Interní použití v systémových frameworcích (SwiftData, WidgetKit) se nedeklaruje.

**Soubor `ZavernyProjekt/PrivacyInfo.xcprivacy` (aplikace):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
				<string>1C8F.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

**Soubor `ZkouskovnikWidget/PrivacyInfo.xcprivacy` (widget a Live Activity):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>1C8F.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

**Poznámky:**

- Složky `ZavernyProjekt/` a `ZkouskovnikWidget/` jsou synchronizované skupiny (`PBXFileSystemSynchronizedRootGroup`), takže se soubor sám přidá do Resources správného targetu.
- **Nedávat ho do `Shared/`.** Ta složka patří oběma targetům a hrozila by kolize stejnojmenných souborů. Aplikace navíc potřebuje i `CA92.1`.
- Ověření: v archivu musí být `ZavernyProjekt.app/PrivacyInfo.xcprivacy` i `PlugIns/ZkouskovnikWidgetExtension.appex/PrivacyInfo.xcprivacy`. V Organizeru zvolit pravým tlačítkem na archiv **Generate Privacy Report**.
- Kdyby se později přidalo SDK (crash reporting, analytika), musí mít vlastní manifest. Pokud SDK data odesílá, je nutné aktualizovat `NSPrivacyCollectedDataTypes` i App Privacy v App Store Connect.

### K-02: Zásady ochrany osobních údajů

**Kód.** V `SettingsView.aboutSection` doplnit (URL nahradit skutečnou):

```swift
Link(destination: URL(string: "https://<tvoje-domena>/terminovnik/soukromi")!) {
    Label("Zásady ochrany osobních údajů", systemImage: "hand.raised")
}
```

Stejný odkaz dát pod tlačítko „Přihlásit se do IS/STAG“ v `StagImportView`, ideálně s větou „Přihlášením souhlasíš se zpracováním údajů podle zásad“.

**Kde zásady zveřejnit.** Repozitář je soukromý. Použít například GitHub Pages ze samostatného veřejného repozitáře nebo vlastní web. URL musí být veřejně dostupná bez přihlášení. Pokud má aplikace anglickou lokalizaci, zásady mít v češtině i v angličtině.

**Osnova zásad (5.1.1(i) vyžaduje každý bod):**

1. **Správce a kontakt:** jméno autora a e-mail.
2. **Jaká data se zpracovávají:** tabulka z kapitoly 2.1 (jméno, osobní číslo, uživatelské jméno, fakulta, rozvrh včetně jmen vyučujících, termíny zkoušek, údaje zadané uživatelem).
3. **Jak a proč:** data se načítají z IS/STAG školy na pokyn uživatele (přihlášení), jen aby se mohla zobrazit v aplikaci, ve widgetech, v oznámeních a v Live Activity. Heslo aplikace nevidí.
4. **Kde jsou data:** jen v zařízení (Klíčenka, úložiště aplikace a sdílené úložiště widgetu). Data se neposílají vývojáři ani třetím stranám kromě serveru IS/STAG zvolené školy. Žádná analytika, reklama ani sledování.
5. **Doba uložení:** do odhlášení, smazání dat nebo odinstalace. Ticket platí nejvýše 90 dní.
6. **Jak data smazat a odvolat souhlas:** Nastavení → Odhlásit ze STAGu, Smazat všechna data, odinstalace. Odvolání souhlasu se zpracováním v IS/STAG se řeší se školou.
7. **Třetí strany:** jen server IS/STAG školy, který provozuje škola podle svých pravidel. Žádné SDK.
8. **Práva podle GDPR** a datum účinnosti.

### V-01: Přístup pro App Review

Podle 2.1(a) je nutné dodat buď **aktivní demo účet**, nebo **plnohodnotný ukázkový režim**. Ten vyžaduje předchozí souhlas Applu, pokud demo účet nejde dodat z právních nebo bezpečnostních důvodů.

**Doporučený postup:**

1. **Požádat UTB (CIT nebo správce IS/STAG) o testovací studentský účet** se zapsanými předměty a vypsanými termíny. Údaje vložit do App Store Connect → App Review Information → Sign-in required. Jde o nejčistší řešení.
2. **Pokud to nejde, přidat viditelný ukázkový režim**, například tlačítko „Vyzkoušet bez školního účtu (ukázka)“ v onboardingu a v `StagImportView`. Režim naplní `TimetableStore` a `ExamTermStore` daty z `TimetableSnapshot.sample` a `ExamTerm.samples` (se smyšlenými jmény, viz S-03) a označí se v UI, například „Ukázkový režim“. **Nesmí být skrytý** (2.3.1(a) zakazuje skryté funkce), takže ho nespouštět launch argumentem ani tajným gestem.
3. Do Review Notes (anglicky) napsat například:

   > Termínovník is an unofficial study planner for students of Czech universities using the IS/STAG student information system. Core features (subjects, deadlines, reminders, widgets, calendar export, Siri shortcuts) work **without signing in**: tap “Continue without signing in”. Signing in uses the university's own web login via ASWebAuthenticationSession (education account, guideline 4.8 exception). The app never sees the password; it receives an access ticket stored in the Keychain. Demo credentials: … / A demo video of the IS/STAG features is attached: … Background App Refresh is used only to check for newly published exam dates and to refresh the timetable. The app does not create accounts; users can sign out and delete all data in Settings. Written permission from the university to use the IS/STAG web services is attached.

4. Přiložit **video na zařízení**, které ukáže přihlášení, rozvrh, termíny, oznámení o novém termínu, widget „Další hodina“ a Live Activity.

### V-02: Identifikátory

Příklad pro doménu `cz.vyleta.terminovnik` (zvolit doménu nebo jméno, které autorovi skutečně patří):

| Místo | Nyní | Nově |
|---|---|---|
| `project.pbxproj` aplikace (Debug + Release) | `devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)` | `cz.vyleta.terminovnik` |
| `project.pbxproj` widget (Debug + Release) | `devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).ZavernyProjekt.Widget` | `cz.vyleta.terminovnik.widget` |
| `ZavernyProjekt.entitlements`, `ZkouskovnikWidget.entitlements` | `group.devplaceholder.OXGLLP23.zkouskovnik` | `group.cz.vyleta.terminovnik` |
| `Shared/WidgetSnapshot.swift:5` `AppGroup.identifier` | totéž | `group.cz.vyleta.terminovnik` |
| `ZavernyProjekt/Info.plist` `BGTaskSchedulerPermittedIdentifiers` + `BackgroundRefresh.taskIdentifier` | `cz.utb.terminovnik.refresh` | `cz.vyleta.terminovnik.refresh` |
| `KeychainStore.service` | `cz.utb.zkouskovnik.stag` | `cz.vyleta.terminovnik.stag` |
| README (sekce Widget a App Group) | zástupná App Group | nová hodnota |

V Apple Developer portálu zaregistrovat App ID aplikace i widgetu a App Group a přiřadit ji oběma. Při `REGISTER_APP_GROUPS = YES` a automatickém podepisování to Xcode udělá sám. **Změnit to ještě před prvním nahráním**, potom už bundle ID změnit nejde.

### V-03: Názvy škol a IS/STAG

- **Svolení (5.2.2).** Požádat správce IS/STAG na UTB (CIT UTB) o písemné svolení k použití webových služeb v aplikaci distribuované přes App Store a uchovat ho. Apple ho může vyžádat. U dalších škol v `StagSchool.all` buď získat svolení také, nebo je ve verzi pro App Store vynechat a ponechat jen UTB a vlastní adresu serveru (s ohledem na N-06).
- **Prohlášení** do „O aplikaci“ a do popisu v App Store:

  > Termínovník je neoficiální aplikace. Nevyvíjí ji ani neprovozuje Univerzita Tomáše Bati ve Zlíně, jiná vysoká škola ani autoři systému IS/STAG. Data se načítají z webových služeb IS/STAG tvé školy.

- **Text „Závěrečný projekt AP9PT · UTB FAI“** (`SettingsView.swift:259`) nahradit například textem „© 2026 Libor Výleta“ a prohlášením výše. Formulace „závěrečný projekt“ může působit jako ukázka nebo beta (2.2).
- V metadatech (název, podtitul, klíčová slova) nepoužívat „UTB“ ani „IS/STAG“ jako marketingová slova (2.3.7). V popisu stačí věcně uvést „podporuje školy s IS/STAG“. Nepoužívat loga škol.

### S-01: Kontakt a podpora

```swift
Link(destination: URL(string: "https://<tvoje-domena>/terminovnik/podpora")!) {
    Label("Podpora a kontakt", systemImage: "questionmark.circle")
}
Link(destination: URL(string: "mailto:<podpora@tvoje-domena>?subject=Term%C3%ADnovn%C3%ADk")!) {
    Label("Napsat vývojáři", systemImage: "envelope")
}
```

Stránka podpory (Support URL v App Store Connect) musí obsahovat kontakt, třeba e-mail nebo formulář, a ideálně i FAQ: jak se přihlásit, co dělat, když přihlášení vyprší, jak smazat data.

### S-02: Ephemeral URLSession

```swift
// StagService
static let urlSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral   // nic na disk
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 20
    return URLSession(configuration: configuration)
}()
var session: URLSession = StagService.urlSession
```

V `StagAccountStore.signOut()` jednorázově uklidit, co se mohlo uložit dřív:

```swift
URLCache.shared.removeAllCachedResponses()
HTTPCookieStorage.shared.removeCookies(since: .distantPast)
```

### S-04: Bez pádu při chybě úložiště

```swift
enum PersistenceController {
    /// true = trvalé úložiště se nepodařilo otevřít, běžíme z paměti (UI ukáže upozornění)
    nonisolated(unsafe) static private(set) var isUsingFallbackStore = false

    static let shared: ModelContainer = {
        let schema = Schema([Subject.self, ExamTask.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            Logger(subsystem: "cz.vyleta.terminovnik", category: "persistence")
                .error("ModelContainer selhal: \(error.localizedDescription, privacy: .public)")
            isUsingFallbackStore = true
            // Úložiště v paměti se prakticky vždy podaří vytvořit; jinak je pád oprávněný.
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
    }()
}
```

Před další změnou `@Model` zavést `VersionedSchema` (V1 = aktuální stav) a `SchemaMigrationPlan`. V `BackgroundRefresh.run()` a v App Intents nic nezapisovat, když je `isUsingFallbackStore == true`.

### S-05: Kompletní odhlášení a smazání

```swift
func signOut() {
    KeychainStore.remove(ticketKey)
    account = nil
    UserDefaults.standard.removeObject(forKey: defaultsKey)
    TimetableStore.shared.clear()
    ExamTermStore.shared.clear()
    LiveActivityManager.shared.endAll()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    URLCache.shared.removeAllCachedResponses()
    HTTPCookieStorage.shared.removeCookies(since: .distantPast)
}
```

V Nastavení přidat druhou destruktivní akci „Smazat vše včetně účtu STAG“: `signOut()` + `deleteAllData` + `AppGroup.defaults?.removePersistentDomain(forName: AppGroup.identifier)` + `WidgetCenter.shared.reloadAllTimelines()`. Tlačítko nesmí být neaktivní jen proto, že nejsou žádné předměty.

### N-03: Robustní Klíčenka

```swift
enum KeychainStore {
    enum ReadResult { case value(String), notFound, failure(OSStatus) }

    static func read(_ key: String) -> ReadResult {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else { return .failure(status) }
            return .value(text)
        case errSecItemNotFound: return .notFound
        default: return .failure(status)   // např. errSecInteractionNotAllowed – zařízení zamčené
        }
    }

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data,
                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary
        var status = SecItemUpdate(baseQuery(key) as CFDictionary, update)
        if status == errSecItemNotFound {
            var attributes = baseQuery(key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
```

V `StagAccountStore.init` mazat ticket jen při prvním spuštění po instalaci, například když chybí `UserDefaults` klíč `installMarker.v1`. Při `.failure` účet nechat a zkusit to později. `connect()` má při neúspěšném `set` vrátit chybu do UI.

---

## 5. Privacy Nutrition Labels (App Store Connect → App Privacy)

**Doporučená odpověď: „Data Not Collected“ (Data se neshromažďují).**

Odůvodnění podle definice Applu: „collect“ znamená přenos dat ze zařízení tak, že k nim má vývojář nebo jeho partner přístup déle, než je nutné k obsloužení požadavku. Termínovník posílá osobní číslo a ticket jen na server IS/STAG školy uživatele, a to jen kvůli okamžitému načtení jeho vlastních dat. Škola není partner vývojáře a vývojář k datům přístup nemá. Všechno ostatní se zpracovává jen v zařízení.

- Tracking: **No**. ATT ani `NSUserTrackingUsageDescription` nejsou potřeba.
- Pokud se později přidá vlastní server, analytika nebo crash reporting třetí strany, je nutné odpovědi přepracovat (typicky Identifiers, Diagnostics, Contact Info → Name) a aktualizovat `NSPrivacyCollectedDataTypes`.
- Odpovědi musí odpovídat zásadám (K-02) a Privacy Manifestu (K-01), jinak hrozí zamítnutí podle 2.3 a 5.1.1.

---

## 6. Co je v pořádku

- **Přihlášení přes `ASWebAuthenticationSession`.** Heslo zadává uživatel na stránce školy, aplikace ho nevidí. Callback schéma `zkousky` není registrované v `CFBundleURLTypes`, takže nejde podvrhnout odkazem z jiné aplikace a návratovou adresu dostane jen probíhající relace. Anonymní přihlášení se odmítne (`StagError.anonymousLogin`).
- **Ticket v Klíčence** s `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: nesynchronizuje se do iCloudu, nepřenese se na jiné zařízení a funguje i pro kontrolu na pozadí. Po přeinstalaci se starý ticket zahodí, při 401 se účet automaticky odpojí.
- **Ticket jde v hlavičce `Authorization`**, ne v URL (kromě N-02). Ticket je svázaný se školou účtu a nepošle se na jiný server.
- **Jen HTTPS, žádné výjimky ATS.** Vlastní adresu serveru aplikace vynucuje jako `https`.
- **Tolerantní dekódování** (`Lossy<T>`). Vadné položky se přeskočí, data ze sítě se nerozbalují násilně a chybové hlášky neobsahují citlivá data.
- **Žádná SDK třetích stran, analytika ani reklama.** ATT není potřeba.
- **Oznámení se vyžadují v kontextu** (uložení deadlinu, Nastavení). Aplikace bez nich funguje (4.5.4, 5.1.2(i)) a Nastavení má odkaz do systémového nastavení oznámení.
- **Aplikace funguje bez přihlášení** (5.1.1(v)). Onboarding nabízí „Pokračovat bez přihlášení“.
- **Kalendář** přes out-of-process `EKEventEditViewController`, bez oprávnění (5.1.1(iii)).
- **Režim na pozadí** jen `fetch` s `BGTaskSchedulerPermittedIdentifiers`, použitý k zamýšlenému účelu (2.5.4).
- **Live Activity** bez push tokenu, `NSSupportsLiveActivities` je deklarované a uživatel ji může vypnout.
- **Debug kód** (`-seedSampleData`, `startDemoLesson`, náhledové ViewModely) je za `#if DEBUG`. `Tools/RenderAppIcon.swift` není v žádném targetu.
- **Logy** (`print`) neobsahují ticket ani osobní údaje.
- **Jen veřejná API** (2.5.1), včetně `UIApplication.openNotificationSettingsURLString`.
- **4.2 Minimální funkčnost:** bohatá nativní aplikace (widgety, Live Activity, Siri, oznámení, offline režim), nejde o obal webu.

---

## 7. Co musí autor udělat ručně (mimo kód)

**Účet a identifikátory**

1. Mít aktivní **Apple Developer Program** (placený). Pro distribuci v EU vyplnit v App Store Connect **status obchodníka podle DSA** (Digital Services Act). Jako „trader“ by se veřejně zobrazila adresa a telefon. Soukromá osoba bez obchodního záměru může zvolit „non-trader“.
2. Zaregistrovat **bundle ID aplikace a widgetu a App Group** (V-02) a vytvořit záznam aplikace v App Store Connect.

**Svolení a přístupy**

3. Získat **písemné svolení** správce IS/STAG na UTB k použití webových služeb a názvu (V-03). U ostatních škol svolení získat, nebo je ve verzi pro App Store vynechat.
4. Získat **testovací studentský účet** pro App Review, nebo požádat Apple o souhlas s ukázkovým režimem (V-01).

**Webové stránky**

5. Zveřejnit **zásady ochrany osobních údajů** na veřejné URL (K-02) a zadat je do App Store Connect → App Information → Privacy Policy URL.
6. Zveřejnit **stránku podpory s kontaktem** (Support URL, 1.5). Volitelně Marketing URL.

**App Store Connect**

7. **App Privacy:** „Data Not Collected“, Tracking = No (kapitola 5).
8. **Content Rights:** odpovědět „Yes, contains/accesses third-party content“ a potvrdit, že k tomu má autor práva (svolení z bodu 3).
9. **Věkové hodnocení:** dotazník → bez nevhodného obsahu, bez obsahu od uživatelů a bez neomezeného prohlížení webu (přihlášení je jen na přihlašovací stránku školy). Výsledek **4+**.
10. **Export compliance:** „None of the algorithms…/exempt“ (jen HTTPS přes systém). Případně přidat `ITSAppUsesNonExemptEncryption = NO` (N-07).
11. **Metadata:**
    - název (do 30 znaků) ověřit, že „Termínovník“ v App Store ještě není,
    - podtitul a klíčová slova bez ochranných známek (2.3.7),
    - v popisu prohlášení „neoficiální aplikace“,
    - kategorie Education (vedlejší Productivity),
    - Copyright „2026 Libor Výleta“.
12. **Screenshoty** pro iPhone 6,9" a (při podpoře iPadu) iPad 13". Používat jen smyšlená data: žádné skutečné osobní číslo, jméno studenta ani jména vyučujících (S-03). Screenshoty musí ukazovat skutečnou aplikaci (2.3.3).
13. **App Review Information:**
    - kontakt (jméno, telefon, e-mail),
    - demo účet,
    - Review Notes podle šablony ve V-01,
    - přiložené video,
    - svolení školy jako přílohu nebo odkaz.

**Před odesláním**

14. **Otestovat Release build na fyzickém iPhonu** (případně i na iPadu) přes TestFlight (2.1):
    - čistá instalace,
    - přihlášení a odhlášení,
    - oznámení,
    - widgety na ploše i na zamčené obrazovce,
    - Live Activity,
    - Siri a Zkratky,
    - kontrola na pozadí (v Xcode: Debug → Simulate Background Fetch, případně `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"…"]`).
15. V Organizeru vygenerovat **Privacy Report** a zkontrolovat, že App Store Connect po nahrání nehlásí ITMS-91053.

---

## Stav oprav (7. 10. 2026)

| ID | Stav | Co se změnilo |
|---|---|---|
| K-01 | Opraveno | `PrivacyInfo.xcprivacy` v aplikaci (CA92.1, 1C8F.1) i ve widgetu (1C8F.1) |
| K-02 | Částečně | Zásady jsou v aplikaci (Nastavení a přihlášení) a v `docs/ZASADY_OCHRANY_UDAJU.md`; **zbývá je zveřejnit na webu a vyplnit `AppInfo.privacyPolicyURL`** |
| V-01 | Ruční krok | Testovací studentský účet / Review Notes pro Apple |
| V-02 | Ruční rozhodnutí | Změna bundle ID, App Group a služby Klíčenky před prvním nahráním (vede ke ztrátě lokálních dat současné instalace) |
| V-03 | Částečně | Prohlášení „neoficiální aplikace“ a © v Nastavení; svolení škol a metadata jsou ruční krok |
| S-01 | Částečně | Odkazy na podporu se zobrazí po vyplnění `AppInfo.supportURL` / `supportEmail` |
| S-02 | Opraveno | Ephemeral `URLSession` bez cache a cookies; při odhlášení se cache maže |
| S-03 | Opraveno | Ukázková data používají smyšlená jména |
| S-04 | Opraveno | Záložní úložiště v paměti místo pádu + varování v Nastavení |
| S-05 | Opraveno | Úplné odhlášení (Live Activity, oznámení, cache, cookies) a „Smazat vše“ včetně rozvrhu a termínů |
| N-01 | Opraveno | Přihlášení v soukromém (ephemeral) okně prohlížeče |
| N-03 | Opraveno | Klíčenka rozlišuje chybějící položku od chyby; účet se při přechodné chybě nemaže |
| N-04 | Opraveno | Akce „Splněno“ a přidání deadlinu přes Siri vyžadují odemčené zařízení |
| N-06 | Opraveno | Vlastní server: odstranění jména/hesla z adresy, zobrazení celého hostu a varování |
| N-07 | Opraveno | `ITSAppUsesNonExemptEncryption = false` |
| N-08 | Opraveno | Žádost o oznámení po přihlášení; HTTP 403 už neodhlašuje |
| N-09 | Opraveno | Údaje o účtu v Klíčence (automatický přesun z UserDefaults, ověřeno na existující instalaci) |
| N-02, N-05, N-10 | Ponecháno | Ticket v query `getStagUserListForLoginTicket` (dáno API STAGu); widgety na zamčené obrazovce záměrně bez `privacySensitive`; test na iPadu je ruční krok |

Unit testy (123) navíc odhalily a opravily: posun hodin rozvrhu v den změny času, odmítnutí serveru začínajícího na „http“ a pád palety při záporném indexu.
