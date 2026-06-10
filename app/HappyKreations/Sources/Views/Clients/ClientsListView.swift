import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ClientsListView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var nouveau: Client?

    var body: some View {
        List {
            ForEach(filtered) { c in
                NavigationLink(destination: ClientEditView(clientId: c.id)) {
                    ClientRow(client: c)
                }
            }
        }
        .navigationTitle("Clients")
        .searchable(text: $search, prompt: "Rechercher")
        .toolbar {
            ToolbarItem {
                Button { nouveau = Client.new() } label: {
                    Label("Nouveau client", systemImage: "plus")
                }
            }
        }
        .sheet(item: $nouveau) { c in
            NavigationStack {
                ClientEditView(clientId: c.id, draft: c, isNew: true)
            }
        }
    }

    private var filtered: [Client] {
        if search.isEmpty { return store.clients }
        let s = search.lowercased()
        return store.clients.filter {
            $0.nom.lowercased().contains(s) ||
            ($0.email ?? "").lowercased().contains(s) ||
            ($0.telephone ?? "").contains(s)
        }
    }
}

private struct ClientRow: View {
    @EnvironmentObject var store: AppStore
    let client: Client

    var body: some View {
        let commandes = store.commandes.filter { $0.client_id == client.id }
        VStack(alignment: .leading, spacing: 2) {
            Text(client.nom).font(.headline)
            HStack(spacing: 8) {
                if let t = client.telephone, !t.isEmpty { Text(t) }
                if let e = client.email, !e.isEmpty { Text(e) }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("\(commandes.count) commande\(commandes.count > 1 ? "s" : "")")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ClientEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let clientId: UUID
    @State var draft: Client
    var isNew: Bool = false
    /// Appelé après la création d'un nouveau client (si isNew = true). Permet
    /// par exemple à la fiche commande de sélectionner automatiquement le
    /// client qui vient d'être créé.
    var onCreated: ((Client) -> Void)? = nil
    @State private var errorText: String?
    @State private var partageFormulaire = false
    @State private var choixCanal = false

    init(clientId: UUID, draft: Client? = nil, isNew: Bool = false,
         onCreated: ((Client) -> Void)? = nil) {
        self.clientId = clientId
        self._draft = State(initialValue: draft ?? Client.new())
        self.isNew = isNew
        self.onCreated = onCreated
    }

    var body: some View {
        Form {
            Section("Coordonnées") {
                TextField("Nom", text: $draft.nom)
                TextField("Téléphone", text: Binding(
                    get: { draft.telephone ?? "" },
                    set: { draft.telephone = $0.isEmpty ? nil : $0 }))
                TextField("Email", text: Binding(
                    get: { draft.email ?? "" },
                    set: { draft.email = $0.isEmpty ? nil : $0 }))
                TextField("Messenger", text: Binding(
                    get: { draft.messenger ?? "" },
                    set: { draft.messenger = $0.isEmpty ? nil : $0 }))
                TextField("Notes", text: Binding(
                    get: { draft.notes ?? "" },
                    set: { draft.notes = $0.isEmpty ? nil : $0 }),
                    axis: .vertical
                ).lineLimit(2...8)
            }
            if !isNew {
                Section {
                    Button {
                        choixCanal = true
                    } label: {
                        Label("Envoyer le formulaire de commande", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Formulaire de commande")
                } footer: {
                    Text("Choisis le canal (e-mail, SMS, WhatsApp…). Les coordonnées du client sont pré-remplies automatiquement.")
                }

                let cmds = store.commandes.filter { $0.client_id == clientId }
                Section("Historique") {
                    if cmds.isEmpty { Text("Aucune commande").foregroundStyle(.secondary) }
                    ForEach(cmds) { c in
                        NavigationLink(destination: CommandeEditView(commandeId: c.id)) {
                            CommandeRow(commande: c)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau client" : draft.nom)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Créer" : "Enregistrer") { Task { await save() } }
            }
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .confirmationDialog("Envoyer le formulaire",
                            isPresented: $choixCanal, titleVisibility: .visible) {
            let email = draft.email?.trimmingCharacters(in: .whitespaces) ?? ""
            let tel = telephoneNettoye
            Button(email.isEmpty ? "E-mail…" : "E-mail (\(email))") {
                ouvrirMail(email: email)
            }
            Button(tel == nil ? "SMS…" : "SMS (\(draft.telephone ?? ""))") {
                ouvrirSMS(tel: tel ?? "")
            }
            Button("WhatsApp") { ouvrirWhatsApp(tel: tel ?? "") }
            Button("Autre application…") { partageFormulaire = true }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(draft.nom.isEmpty
                 ? "Choisis comment envoyer le lien."
                 : "Choisis comment envoyer le lien à \(draft.nom).")
        }
        .sheet(isPresented: $partageFormulaire) {
            ShareSheet(items: [messageFormulaire, AppConfig.formulaireURL])
                .presentationDetents([.medium])
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    // MARK: - Partage formulaire (multi-canal)

    private var prenom: String {
        draft.nom.split(separator: " ").first.map(String.init) ?? ""
    }
    private var salutation: String {
        prenom.isEmpty ? "Bonjour," : "Bonjour \(prenom),"
    }
    /// Message texte (SMS / WhatsApp / share sheet).
    private var messageFormulaire: String {
        "\(salutation) passez votre commande HappyKreations ici 🍫 : \(AppConfig.formulaireURL.absoluteString)"
    }
    /// Téléphone normalisé au format international sans symboles (ex.
    /// 0692401797 → 262692401797). nil si pas de téléphone.
    private var telephoneNettoye: String? {
        guard let raw = draft.telephone?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        var digits = raw.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("+") { digits.removeFirst() }
        // Numéro local Réunion (07.. / 06.. / 026...) → préfixe pays 262.
        if digits.hasPrefix("0") { digits = "262" + digits.dropFirst() }
        return digits.isEmpty ? nil : digits
    }

    private func ouvrirMail(email: String) {
        let subject = "Votre commande HappyKreations 🍫"
        let body = """
        \(salutation)

        Pour passer votre commande et régler l'acompte en ligne, c'est par ici :
        \(AppConfig.formulaireURL.absoluteString)

        À très vite,
        HappyKreations
        """
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = email   // peut être vide → Mail ouvre avec destinataire vide
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = comps.url { ouvrir(url) }
    }

    private func ouvrirSMS(tel: String) {
        let texte = messageFormulaire.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Si pas de numéro, on ouvre l'app Messages vide (l'utilisateur choisit).
        let urlStr = tel.isEmpty ? "sms:&body=\(texte)" : "sms:\(tel)&body=\(texte)"
        if let url = URL(string: urlStr) { ouvrir(url) }
    }

    private func ouvrirWhatsApp(tel: String) {
        let texte = messageFormulaire.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Sans numéro : wa.me/?text= ouvre l'écran « choisir un contact ».
        let urlStr = tel.isEmpty ? "https://wa.me/?text=\(texte)"
                                 : "https://wa.me/\(tel)?text=\(texte)"
        if let url = URL(string: urlStr) { ouvrir(url) }
    }

    private func ouvrir(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private func save() async {
        do {
            if isNew {
                let inserted: Client = try await store.repo.insert("client", draft)
                await store.loadClients()
                onCreated?(inserted)
                dismiss()
            } else {
                _ = try await store.repo.update("client", draft, id: draft.id)
                await store.loadClients()
            }
        } catch { errorText = error.localizedDescription }
    }
}
