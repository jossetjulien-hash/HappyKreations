import SwiftUI

struct CommandesListView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var filtreStatut: StatutCommande? = nil
    @State private var newCommande: Commande?

    var body: some View {
        List {
            ForEach(filtered) { c in
                NavigationLink(destination: CommandeEditView(commandeId: c.id)) {
                    CommandeRow(commande: c)
                }
            }
        }
        .navigationTitle("Commandes")
        .searchable(text: $search, prompt: "Rechercher")
        .toolbar { toolbar }
        .sheet(item: $newCommande) { c in
            NavigationStack {
                CommandeEditView(commandeId: c.id, draft: c, isNew: true)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("Tous les statuts") { filtreStatut = nil }
                Divider()
                ForEach(StatutCommande.allCases) { s in
                    Button(s.libelle) { filtreStatut = s }
                }
            } label: {
                Label(filtreStatut?.libelle ?? "Filtrer", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        ToolbarItem {
            Button {
                newCommande = Commande.new()
            } label: {
                Label("Nouvelle commande", systemImage: "plus")
            }
        }
    }

    private var filtered: [Commande] {
        store.commandes.filter { c in
            if let f = filtreStatut, c.statut != f { return false }
            if search.isEmpty { return true }
            let s = search.lowercased()
            let nomClient = store.client(id: c.client_id)?.nom.lowercased() ?? ""
            return nomClient.contains(s) || (c.notes ?? "").lowercased().contains(s)
                || (c.type_evenement ?? "").lowercased().contains(s)
        }
    }
}

struct CommandeRow: View {
    @EnvironmentObject var store: AppStore
    let commande: Commande

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if commande.photo_ref_url != nil {
                CommandePhotoThumb(url: commande.photo_ref_url, size: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(store.client(id: commande.client_id)?.nom ?? "Client inconnu")
                    .font(.headline)
                if let d = commande.date_retrait {
                    Label(d.formatted(date: .abbreviated, time: .omitted),
                          systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let e = commande.type_evenement, !e.isEmpty {
                    Text(e).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(commande.total, format: .currency(code: "EUR"))
                    .font(.subheadline).bold()
                StatutBadge(statut: commande.statut)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatutBadge: View {
    let statut: StatutCommande
    var body: some View {
        Text(statut.libelle)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch statut {
        case .brouillon, .a_confirmer: return .gray
        case .confirmee:               return .blue
        case .en_production:           return .orange
        case .prete:                   return .purple
        case .livree:                  return .teal
        case .soldee:                  return .green
        case .annulee:                 return .red
        }
    }
}
