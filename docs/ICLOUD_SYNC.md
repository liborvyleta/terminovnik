# Synchronizace přes iCloud (připravená, vypnutá)

Synchronizace SwiftData přes CloudKit vyžaduje **placený Apple Developer Program** – s bezplatným
Personal Teamem nejde iCloud entitlement podepsat. Do té doby slouží záloha do souboru
(Nastavení → Záloha a synchronizace).

## Jak zapnout
1. Xcode → target **ZavernyProjekt** → Signing & Capabilities:
   - **+ iCloud** → zaškrtnout **CloudKit**, kontejner `iCloud.cz.liborvyleta.terminovnik`.
   - **+ Background Modes** → **Remote notifications** (CloudKit posílá tiché push notifikace o změnách).
2. Build Settings → *Active Compilation Conditions* (Debug i Release) → přidat `ICLOUD_SYNC`.
3. `PersistenceController` pak použije `cloudKitDatabase: .automatic` (jinak `.none`), úložiště zůstává na stejném místě.
4. V CloudKit Console po prvním spuštění v Debug nasadit schéma do Production (*Deploy Schema Changes*).

Modely jsou už CloudKit-kompatibilní: žádné `@Attribute(.unique)`, všechny vlastnosti mají výchozí
hodnotu nebo jsou volitelné, vazba `Subject.tasks` je volitelná s inverzí `ExamTask.subject`.

## Co se synchronizuje
- **Synchronizuje se:** SwiftData – předměty (`Subject`) a deadliny/zkoušky (`ExamTask`) včetně poznámek,
  splnění, výsledku a `stagTermID`.
- **Nesynchronizuje se:** účet STAG (Klíčenka, zůstává na zařízení), rozvrh, termíny zkoušek a známky
  (JSON v App Group – každé zařízení si je stáhne ze STAGu samo), nastavení, naplánovaná oznámení.

## Duplicity ze STAGu
Import předmětů (`StagSubjectSync`) páruje podle kódu a zapsané termíny (`ExamTermStore`) podle
`stagTermID`. Když ale dvě zařízení naimportují totéž dřív, než se stihnou synchronizovat, vzniknou dva
záznamy s různým UUID. Proto `BackupService.removeStagDuplicates(in:)`:
- sloučí předměty se stejným kódem (bez ohledu na velikost písmen) – úkoly přesune k ponechanému,
- smaže úkoly se stejným `stagTermID` (přednost má splněný),
- ponechaný záznam volí deterministicky (nejnižší UUID), takže všechna zařízení dojdou ke stejnému výsledku.

S flagem `ICLOUD_SYNC` se volá při startu aplikace (`TerminovnikApp.init`). Doporučení: volat ji i po
`StagSubjectSync.sync` a po synchronizaci termínů a po přijetí vzdálené změny
(`NSPersistentStoreRemoteChange`).

## Upozornění
- Jedinečnost `id` už nehlídá databáze, ale aplikace (UUID + sloučení při obnově zálohy).
- Data, která už v iCloudu jsou, nelze snadno „vrátit“ – před prvním zapnutím udělej zálohu do souboru.
