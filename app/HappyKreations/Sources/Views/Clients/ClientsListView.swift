import SwiftUI

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
    @State private var errorText: String?

    init(clientId: UUID, draft: Client? = nil, isNew: Bool = false) {
        self.clientId = clientId
        self._draft = State(initialValue: draft ?? Client.new())
        self.isNew = isNew
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
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func save() async {
        do {
            if isNew { _ = try await store.repo.insert("client", draft) }
            else { _ = try await store.repo.update("client", draft, id: draft.id) }
            await store.loadClients()
            if isNew { dismiss() }
        } catch { errorText = error.localizedDescription }
    }
}
