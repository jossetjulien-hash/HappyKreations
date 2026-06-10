import SwiftUI
import EventKit
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ReglagesView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthStore

    @State private var acomptePourcent: String = "30"
    @State private var delaiMini: String = "7"
    @State private var nomAtelier: String = "HappyKreations"
    @State private var adresseAtelier: String = ""
    @State private var siretAtelier: String = ""
    @State private var emailAtelier: String = ""
    @State private var telephoneAtelier: String = ""
    @State private var errorText: String?
    @State private var dateCapacite = Date()
    @State private var plafond: Int = 10
    @State private var bloque = false
    @State private var calendarChoices: [EKCalendar] = []
    @State private var selectedCalendarId: String = ""
    @State private var reminderSources: [RemindersService.SourceOption] = []
    @AppStorage(RemindersService.preferredSourceKey) private var preferredReminderSource: String = ""
    @State private var anneeExport: Int = Calendar.current.component(.year, from: Date())
    @AppStorage(LocalNotificationService.enabledKey) private var notificationsEnabled = true
    @State private var notifAuthStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Compte") {
                LabeledContent("Email", value: auth.userEmail ?? "—")
                Button("Se déconnecter", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }

            if auth.biometricKind != .none {
                Section {
                    Toggle(isOn: Binding(
                        get: { auth.biometricEnabled },
                        set: { wanted in
                            Task { await auth.setBiometric(enabled: wanted) }
                        }
                    )) {
                        Label("Verrouiller avec \(auth.biometricKind.libelle)",
                              systemImage: auth.biometricKind.icon)
                    }
                } footer: {
                    Text("L'app demandera \(auth.biometricKind.libelle) au démarrage et après chaque mise en arrière-plan.")
                }
            }

            Section {
                if !store.calendarSyncEnabled {
                    if !calendarChoices.isEmpty {
                        Picker("Calendrier", selection: $selectedCalendarId) {
                            ForEach(calendarChoices, id: \.calendarIdentifier) { c in
                                Text(c.title).tag(c.calendarIdentifier)
                            }
                        }
                    }
                    Button {
                        Task { await activerSync() }
                    } label: {
                        Label("Activer la synchro Calendrier", systemImage: "calendar.badge.plus")
                    }
                } else {
                    LabeledContent("Calendrier",
                                   value: calendarChoices.first { $0.calendarIdentifier == store.calendarSyncId }?.title
                                          ?? "—")
                    Button {
                        Task { await store.syncCommandesToCalendar() }
                    } label: {
                        Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        store.disableCalendarSync()
                    } label: {
                        Label("Désactiver la synchro", systemImage: "calendar.badge.minus")
                    }
                }
            } header: {
                Text("Calendrier Apple")
            } footer: {
                Text("Les commandes apparaîtront comme événements toute la journée à la date de retrait. Via iCloud, elles seront visibles sur tous tes appareils Apple sans configuration supplémentaire.")
            }

            Section {
                if reminderSources.isEmpty {
                    Text("Aucun compte de rappels disponible.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Compte", selection: $preferredReminderSource) {
                        Text("Automatique (préfère iCloud)").tag("")
                        ForEach(reminderSources) { s in
                            Text(s.title).tag(s.id)
                        }
                    }
                }
            } header: {
                Text("Rappels")
            } footer: {
                Text("Les rappels créés par l'app (ex. \"Commander chez le fournisseur X\") iront dans le compte choisi. « Automatique » sélectionne ton compte iCloud personnel quand il est disponible.")
            }

            Section {
                Toggle("Activer les notifications", isOn: $notificationsEnabled)
                    .disabled(notifAuthStatus == .denied)
                if notifAuthStatus == .denied {
                    Text("Autorisation refusée. Active-les dans Réglages système → Notifications → HappyKreations.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Tu seras notifié(e) à chaque nouvelle commande arrivée du formulaire web et à chaque acompte Stripe reçu. Notifications locales — pas de service tiers, pas de compte Apple Developer requis.")
            }

            Section("Paramètres globaux") {
                HStack {
                    Text("% d'acompte")
                    Spacer()
                    TextField("", text: $acomptePourcent).multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text("%")
                }
                HStack {
                    Text("Délai mini formulaire")
                    Spacer()
                    TextField("", text: $delaiMini).multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text("jours")
                }
                TextField("Nom de l'atelier", text: $nomAtelier)
                Button("Enregistrer les paramètres") { Task { await sauverConfig() } }
            }

            Section {
                TextField("Adresse postale", text: $adresseAtelier, axis: .vertical)
                    .lineLimit(2...4)
                TextField("SIRET", text: $siretAtelier)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("Email", text: $emailAtelier)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                TextField("Téléphone", text: $telephoneAtelier)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
                Button("Enregistrer l'identité") { Task { await sauverConfig() } }
            } header: {
                Text("Identité entreprise")
            } footer: {
                Text("Ces informations apparaissent sur les factures PDF. Le SIRET et la mention micro-entreprise sont obligatoires sur les documents commerciaux.")
            }

            Section("Capacité / jours bloqués") {
                DatePicker("Date", selection: $dateCapacite, displayedComponents: .date)
                Stepper("Plafond unités : \(plafond)", value: $plafond, in: 0...500)
                Toggle("Bloquer ce jour", isOn: $bloque)
                Button("Enregistrer la règle de ce jour") { Task { await sauverCapacite() } }
                if !store.capacites.isEmpty {
                    DisclosureGroup("Règles actuelles (\(store.capacites.count))") {
                        ForEach(store.capacites) { c in
                            HStack {
                                Text(c.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                if c.bloque { Label("Bloqué", systemImage: "lock.fill").foregroundStyle(.red) }
                                if let p = c.plafond_unites { Text("\(p) max") }
                            }
                        }
                    }
                }
            }

            Section {
                Picker("Année", selection: $anneeExport) {
                    ForEach(anneesDisponibles, id: \.self) { y in
                        Text("\(String(format: "%d", y))").tag(y)
                    }
                }
                Button {
                    exportComptableCSV()
                } label: {
                    Label("Registre des recettes (CSV)", systemImage: "tablecells")
                }
                Button {
                    exportComptablePDF()
                } label: {
                    Label("Récap annuel (PDF)", systemImage: "doc.richtext")
                }
            } header: {
                Text("Export comptable")
            } footer: {
                Text("CSV au format livre des recettes (date, référence, client, montant, règlement) à transmettre à votre comptable. Le PDF est un récap mensuel imprimable.")
            }

            Section("Autres exports") {
                Button {
                    exportCSV()
                } label: { Label("Toutes les commandes (CSV)", systemImage: "square.and.arrow.up") }
            }

            Section("Livraison") {
                NavigationLink(destination: ZonesLivraisonView()) {
                    Label("Zones et tarifs de livraison", systemImage: "shippingbox")
                }
            }

            Section("Projet Supabase") {
                LabeledContent("URL", value: AppConfig.supabaseURL.absoluteString)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Réglages")
        .task {
            restaurer()
            await chargerCalendriers()
            await chargerSourcesRappels()
            notifAuthStatus = await LocalNotificationService.shared.currentStatus()
        }
        .onChange(of: store.config) { _, _ in restaurer() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func restaurer() {
        acomptePourcent = store.config["acompte_pourcent"] ?? "30"
        delaiMini = store.config["delai_mini_jours"] ?? "7"
        nomAtelier = store.config["nom_atelier"] ?? "HappyKreations"
        adresseAtelier = store.config["adresse_atelier"] ?? ""
        siretAtelier = store.config["siret_atelier"] ?? ""
        emailAtelier = store.config["email_atelier"] ?? ""
        telephoneAtelier = store.config["telephone_atelier"] ?? ""
    }

    private func chargerCalendriers() async {
        // Lecture des calendriers : nécessite l'autorisation. On ne demande
        // pas l'accès tant que l'utilisateur n'a pas activé la synchro, sauf
        // si on doit afficher la liste pour qu'il choisisse.
        if !CalendarService.shared.hasAccess {
            _ = await CalendarService.shared.requestAccess()
        }
        calendarChoices = CalendarService.shared.writableCalendars
        if selectedCalendarId.isEmpty {
            selectedCalendarId = store.calendarSyncId
                ?? CalendarService.shared.defaultCalendar?.calendarIdentifier
                ?? calendarChoices.first?.calendarIdentifier ?? ""
        }
    }

    private func chargerSourcesRappels() async {
        if !RemindersService.shared.hasAccess {
            _ = await RemindersService.shared.requestAccess()
        }
        reminderSources = RemindersService.shared.availableSources()
    }

    private func activerSync() async {
        guard !selectedCalendarId.isEmpty else { return }
        await store.enableCalendarSync(calendarId: selectedCalendarId)
    }

    private func sauverConfig() async {
        do {
            try await store.repo.setConfig(cle: "acompte_pourcent", valeur: acomptePourcent)
            try await store.repo.setConfig(cle: "delai_mini_jours", valeur: delaiMini)
            try await store.repo.setConfig(cle: "nom_atelier", valeur: nomAtelier)
            try await store.repo.setConfig(cle: "adresse_atelier", valeur: adresseAtelier)
            try await store.repo.setConfig(cle: "siret_atelier", valeur: siretAtelier)
            try await store.repo.setConfig(cle: "email_atelier", valeur: emailAtelier)
            try await store.repo.setConfig(cle: "telephone_atelier", valeur: telephoneAtelier)
            await store.loadConfig()
        } catch { errorText = error.localizedDescription }
    }

    private func sauverCapacite() async {
        let cap = CapaciteJour(date: Calendar.current.startOfDay(for: dateCapacite),
                               plafond_unites: plafond, bloque: bloque)
        do {
            _ = try await store.repo.upsert("capacite_jour", cap, onConflict: "date")
            await store.loadCapacites()
        } catch { errorText = error.localizedDescription }
    }

    private func exportCSV() {
        var csv = "id;client;date_retrait;statut;total;acompte;canal\n"
        for c in store.commandes {
            let client = store.client(id: c.client_id)?.nom ?? ""
            let date = c.date_retrait.map { DateFormat.iso($0) } ?? ""
            csv += "\(c.id);\(client);\(date);\(c.statut.rawValue);\(c.total);\(c.acompte);\(c.canal.rawValue)\n"
        }
        partager(contenu: csv, nomFichier: "commandes-\(DateFormat.iso(Date())).csv")
    }

    // MARK: - Export comptable

    /// Années pour lesquelles on a au moins un paiement, par ordre décroissant.
    /// Inclut toujours l'année en cours, même sans paiement.
    private var anneesDisponibles: [Int] {
        let cal = Calendar.current
        let cetteAnnee = cal.component(.year, from: Date())
        var set = Set<Int>([cetteAnnee])
        for p in store.paiements where p.statut == .reussi {
            set.insert(cal.component(.year, from: p.date))
        }
        return set.sorted(by: >)
    }

    private func exportComptableCSV() {
        let recap = AccountingExport.build(annee: anneeExport, store: store)
        let csv = AccountingExport.csv(recap)
        partager(contenu: csv,
                 nomFichier: "registre-recettes-\(anneeExport).csv")
    }

    private func exportComptablePDF() {
        let recap = AccountingExport.build(annee: anneeExport, store: store)
        guard let url = AccountingExport.generatePDF(
            recap, nomAtelier: store.config["nom_atelier"] ?? "HappyKreations")
        else {
            errorText = "Génération du PDF impossible."
            return
        }
        partagerFichier(url: url)
    }

    // MARK: - Partage cross-platform

    private func partager(contenu: String, nomFichier: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(nomFichier)
        try? contenu.write(to: tmp, atomically: true, encoding: .utf8)
        partagerFichier(url: tmp)
    }

    private func partagerFichier(url: URL) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        #else
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let rootVC = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        rootVC?.present(av, animated: true)
        #endif
    }
}
