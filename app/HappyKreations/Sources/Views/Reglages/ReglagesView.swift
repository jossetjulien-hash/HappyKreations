import SwiftUI
import EventKit
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
    @State private var errorText: String?
    @State private var dateCapacite = Date()
    @State private var plafond: Int = 10
    @State private var bloque = false
    @State private var calendarChoices: [EKCalendar] = []
    @State private var selectedCalendarId: String = ""

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

            Section("Export") {
                Button {
                    exportCSV()
                } label: { Label("Exporter les commandes (CSV)", systemImage: "square.and.arrow.up") }
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

    private func activerSync() async {
        guard !selectedCalendarId.isEmpty else { return }
        await store.enableCalendarSync(calendarId: selectedCalendarId)
    }

    private func sauverConfig() async {
        do {
            try await store.repo.setConfig(cle: "acompte_pourcent", valeur: acomptePourcent)
            try await store.repo.setConfig(cle: "delai_mini_jours", valeur: delaiMini)
            try await store.repo.setConfig(cle: "nom_atelier", valeur: nomAtelier)
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
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "commandes-\(DateFormat.iso(Date())).csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
        #else
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("commandes-\(DateFormat.iso(Date())).csv")
        try? csv.write(to: tmp, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let rootVC = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        rootVC?.present(av, animated: true)
        #endif
    }
}
