import SwiftUI

/// Zásady ochrany osobních údajů přímo v aplikaci (App Store Review Guidelines 5.1.1(i)).
///
/// Stejný obsah je v `docs/ZASADY_OCHRANY_UDAJU.md` ke zveřejnění na webu –
/// při změně je potřeba upravit obojí (a datum účinnosti).
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            summarySection
            dataSection
            purposeSection
            storageSection
            sharingSection
            retentionSection
            deletionSection
            rightsSection
            contactSection
        }
        .navigationTitle("Ochrana osobních údajů")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Shrnutí

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Tvoje data zůstávají v tomto zařízení", systemImage: "lock.iphone")
                    .labelStyle(.compact(spacing: 8))
                    .font(.headline)
                Text("Termínovník nemá vlastní server, nepoužívá analytiku, reklamu ani sledování a nic neposílá vývojáři ani třetím stranám. Komunikuje jen se systémem IS/STAG školy, kterou si zvolíš.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Zásady ochrany osobních údajů")
        } footer: {
            Text("Účinné od 7. října 2026")
        }
    }

    // MARK: - Jaká data

    private var dataSection: some View {
        Section {
            item(icon: "person.text.rectangle", title: "Účet IS/STAG",
                 text: "Jméno a příjmení, osobní číslo, uživatelské jméno, fakulta a zvolená škola.")
            item(icon: "key", title: "Přístupový klíč",
                 text: "Po přihlášení dostane aplikace od školy přístupový klíč (ticket) platný nejvýše 90 dní. Heslo aplikace nevidí ani neukládá – zadáváš ho přímo na přihlašovací stránce školy.")
            item(icon: "calendar", title: "Rozvrh",
                 text: "Předměty, časy, místnosti a jména vyučujících.")
            item(icon: "graduationcap", title: "Termíny zkoušek",
                 text: "Datum, místnost, zkoušející, obsazenost a stav tvého zápisu.")
            item(icon: "square.and.pencil", title: "Údaje, které zadáš sám",
                 text: "Předměty, deadliny, poznámky, body a známky.")
        } header: {
            Text("Jaká data aplikace zpracovává")
        }
    }

    // MARK: - K čemu

    private var purposeSection: some View {
        Section {
            paragraph("Data se ze systému IS/STAG tvé školy načítají jen na tvůj pokyn – po přihlášení. Slouží výhradně k tomu, aby se ti zobrazila v aplikaci, ve widgetech, v oznámeních, v Live Activity a v akcích pro Siri a Zkratky.")
            paragraph("Když jsi přihlášený, aplikace občas na pozadí obnoví rozvrh a zkontroluje nově vypsané termíny. Připomínky a oznámení plánuje přímo v zařízení – neposílají se přes žádný server.")
            paragraph("Událost do Kalendáře se přidá, jen když o to sám požádáš. Aplikace tvůj kalendář nečte.")
        } header: {
            Text("K čemu data slouží")
        }
    }

    // MARK: - Kde

    private var storageSection: some View {
        Section {
            item(icon: "key.fill", title: "Klíčenka iOS",
                 text: "Přístupový klíč. Zůstává jen v tomto zařízení, nesynchronizuje se přes iCloud a nepřenese se na jiné zařízení.")
            item(icon: "internaldrive", title: "Úložiště aplikace",
                 text: "Údaje o účtu, předměty, deadliny, rozvrh a termíny.")
            item(icon: "rectangle.3.group", title: "Sdílené úložiště pro widget (App Group)",
                 text: "Rozvrh, termíny a nejbližší deadliny, aby je mohly zobrazit widgety.")
        } header: {
            Text("Kde jsou data uložena")
        } footer: {
            Text("Data jsou uložena jen v tomto zařízení. Mohou být součástí zálohy zařízení (iCloud nebo počítač), kterou spravuješ ty.")
        }
    }

    // MARK: - Komu

    private var sharingSection: some View {
        Section {
            paragraph("Nikomu dalšímu. Aplikace nemá vlastní server a neobsahuje analytiku, reklamu, sledování ani knihovny (SDK) třetích stran. Vývojář k tvým datům nemá přístup.")
            paragraph("Jediná komunikace mimo zařízení je s webovými službami IS/STAG školy, kterou si zvolíš, vždy šifrovaně přes HTTPS. Aplikace jim posílá přístupový klíč a údaje potřebné k dotazu (osobní číslo, semestr, předmět). Server provozuje tvoje škola podle svých pravidel.")
        } header: {
            Text("Komu se data předávají")
        }
    }

    // MARK: - Jak dlouho

    private var retentionSection: some View {
        Section {
            paragraph("Data zůstávají v zařízení, dokud se neodhlásíš, data nesmažeš nebo aplikaci neodinstaluješ. Přístupový klíč platí nejvýše 90 dní; když vyprší, aplikace ho smaže a požádá tě o nové přihlášení.")
        } header: {
            Text("Jak dlouho data uchováváme")
        }
    }

    // MARK: - Smazání

    private var deletionSection: some View {
        Section {
            item(icon: "rectangle.portrait.and.arrow.right", title: "Nastavení → Odhlásit ze STAGu",
                 text: "Smaže přístupový klíč, údaje o účtu, uložený rozvrh a termíny. Předměty a deadliny zůstanou.")
            item(icon: "trash", title: "Nastavení → Smazat všechna data",
                 text: "Smaže předměty, deadliny, připomínky, uložený rozvrh i termíny. Volitelně tě zároveň odhlásí ze STAGu.")
            item(icon: "xmark.app", title: "Odinstalace aplikace",
                 text: "Smaže všechna data aplikace v zařízení.")
        } header: {
            Text("Jak data smazat")
        } footer: {
            Text("Údaje přímo v IS/STAG spravuje tvoje škola. Žádosti o jejich opravu, výmaz nebo odvolání souhlasu směřuj na ni.")
        }
    }

    // MARK: - Práva

    private var rightsSection: some View {
        Section {
            paragraph("Podle GDPR máš právo na přístup ke svým údajům, jejich opravu a výmaz, omezení zpracování a přenositelnost a právo podat stížnost u Úřadu pro ochranu osobních údajů (uoou.gov.cz).")
            paragraph("Protože data zůstávají jen v tvém zařízení, většinu práv uplatníš přímo v aplikaci – údaje si zobrazíš, upravíš i smažeš. S dotazy se obrať na autora.")
        } header: {
            Text("Tvoje práva")
        }
    }

    // MARK: - Kontakt

    private var contactSection: some View {
        Section {
            LabeledContent("Autor", value: AppInfo.developerName)

            if let email = AppInfo.supportEmail, let mailURL = AppInfo.supportMailURL {
                Link(destination: mailURL) {
                    LabeledContent("E-mail", value: email)
                }
            }
            if let supportURL = AppInfo.supportURL {
                Link(destination: supportURL) {
                    Label("Podpora a kontakt", systemImage: "questionmark.circle")
                }
            }
            if let policyURL = AppInfo.privacyPolicyURL {
                Link(destination: policyURL) {
                    Label("Zásady na webu", systemImage: "safari")
                }
            }
            if AppInfo.supportMailURL == nil, AppInfo.supportURL == nil {
                paragraph("Kontakt na autora najdeš na stránce aplikace v App Store.")
            }
        } header: {
            Text("Autor a kontakt")
        } footer: {
            Text("Termínovník je neoficiální aplikace. Není produktem IS/STAG ani žádné univerzity. Při změně zásad najdeš aktuální znění vždy tady v aplikaci.")
        }
    }

    // MARK: - Pomocné

    private func item(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
