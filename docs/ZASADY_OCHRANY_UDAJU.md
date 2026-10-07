# Zásady ochrany osobních údajů – Termínovník

Účinné od 7. října 2026

> Stejný obsah je přímo v aplikaci (Nastavení → O aplikaci → Zásady ochrany osobních údajů,
> soubor `ZavernyProjekt/Views/Settings/PrivacyPolicyView.swift`). Při změně je potřeba upravit obojí.
> Tento text je určený ke zveřejnění na veřejné adrese (např. GitHub Pages); tu pak zadej do
> `AppInfo.privacyPolicyURL` a do App Store Connect → App Information → Privacy Policy URL.

## Shrnutí

**Tvoje data zůstávají v tomto zařízení.** Termínovník nemá vlastní server, nepoužívá analytiku, reklamu ani sledování a nic neposílá vývojáři ani třetím stranám. Komunikuje jen se systémem IS/STAG školy, kterou si zvolíš.

## Jaká data aplikace zpracovává

- **Účet IS/STAG:** jméno a příjmení, osobní číslo, uživatelské jméno, fakulta a zvolená škola.
- **Přístupový klíč:** po přihlášení dostane aplikace od školy přístupový klíč (ticket) platný nejvýše 90 dní. Heslo aplikace nevidí ani neukládá – zadáváš ho přímo na přihlašovací stránce školy.
- **Rozvrh:** předměty, časy, místnosti a jména vyučujících.
- **Termíny zkoušek:** datum, místnost, zkoušející, obsazenost a stav tvého zápisu.
- **Údaje, které zadáš sám:** předměty, deadliny, poznámky, body a známky.

## K čemu data slouží

Data se ze systému IS/STAG tvé školy načítají jen na tvůj pokyn – po přihlášení. Slouží výhradně k tomu, aby se ti zobrazila v aplikaci, ve widgetech, v oznámeních, v Live Activity a v akcích pro Siri a Zkratky.

Když jsi přihlášený, aplikace občas na pozadí obnoví rozvrh a zkontroluje nově vypsané termíny. Připomínky a oznámení plánuje přímo v zařízení – neposílají se přes žádný server.

Událost do Kalendáře se přidá, jen když o to sám požádáš. Aplikace tvůj kalendář nečte.

## Kde jsou data uložena

- **Klíčenka iOS:** přístupový klíč. Zůstává jen v tomto zařízení, nesynchronizuje se přes iCloud a nepřenese se na jiné zařízení.
- **Úložiště aplikace:** údaje o účtu, předměty, deadliny, rozvrh a termíny.
- **Sdílené úložiště pro widget (App Group):** rozvrh, termíny a nejbližší deadliny, aby je mohly zobrazit widgety.

Data jsou uložena jen v tomto zařízení. Mohou být součástí zálohy zařízení (iCloud nebo počítač), kterou spravuješ ty.

## Komu se data předávají

Nikomu dalšímu. Aplikace nemá vlastní server a neobsahuje analytiku, reklamu, sledování ani knihovny (SDK) třetích stran. Vývojář k tvým datům nemá přístup.

Jediná komunikace mimo zařízení je s webovými službami IS/STAG školy, kterou si zvolíš, vždy šifrovaně přes HTTPS. Aplikace jim posílá přístupový klíč a údaje potřebné k dotazu (osobní číslo, semestr, předmět). Server provozuje tvoje škola podle svých pravidel.

## Jak dlouho data uchováváme

Data zůstávají v zařízení, dokud se neodhlásíš, data nesmažeš nebo aplikaci neodinstaluješ. Přístupový klíč platí nejvýše 90 dní; když vyprší, aplikace ho smaže a požádá tě o nové přihlášení.

## Jak data smazat

- **Nastavení → Odhlásit ze STAGu:** smaže přístupový klíč, údaje o účtu, uložený rozvrh a termíny. Předměty a deadliny zůstanou.
- **Nastavení → Smazat všechna data:** smaže předměty, deadliny, připomínky, uložený rozvrh i termíny. Volitelně tě zároveň odhlásí ze STAGu.
- **Odinstalace aplikace:** smaže všechna data aplikace v zařízení.

Údaje přímo v IS/STAG spravuje tvoje škola. Žádosti o jejich opravu, výmaz nebo odvolání souhlasu směřuj na ni.

## Tvoje práva

Podle GDPR máš právo na přístup ke svým údajům, jejich opravu a výmaz, omezení zpracování a přenositelnost a právo podat stížnost u Úřadu pro ochranu osobních údajů ([uoou.gov.cz](https://uoou.gov.cz)).

Protože data zůstávají jen v tvém zařízení, většinu práv uplatníš přímo v aplikaci – údaje si zobrazíš, upravíš i smažeš. S dotazy se obrať na autora.

## Autor a kontakt

- **Autor:** Libor Výleta
- **E-mail:** _doplnit (stejný jako `AppInfo.supportEmail`)_
- **Podpora:** _doplnit (stejná adresa jako `AppInfo.supportURL` a Support URL v App Store Connect)_

Termínovník je neoficiální aplikace. Není produktem IS/STAG ani žádné univerzity; názvy škol slouží jen k připojení k jejich systému. Při změně zásad najdeš aktuální znění vždy v aplikaci a na této stránce.
