import SwiftUI

struct RecettesListView: View {
    @EnvironmentObject var store: AppStore
    @State private var nouveau: Produit?

    var body: some View {
        List {
            ForEach(store.produits) { p in
                NavigationLink(destination: RecetteEditView(produitId: p.id)) {
                    HStack {
                        Image(systemName: p.categorie == .coffret ? "shippingbox" : "cone")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(p.nom).font(.headline)
                            HStack(spacing: 6) {
                                Text(p.categorie.libelle)
                                Text("·")
                                Text(p.prix_vente, format: .currency(code: "EUR"))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.visible_formulaire {
                            Image(systemName: "globe").foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recettes & Produits")
        .toolbar {
            ToolbarItem {
                Button {
                    nouveau = Produit.new()
                } label: { Label("Nouveau produit", systemImage: "plus") }
            }
        }
        .sheet(item: $nouveau) { p in
            NavigationStack {
                RecetteEditView(produitId: p.id, draft: p, isNew: true)
            }
        }
    }
}

struct RecetteEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let produitId: UUID
    @State var draft: Produit
    var isNew: Bool = false
    @State private var lignes: [RecetteLigne] = []
    @State private var declinaisonNew = ""
    @State private var errorText: String?

    init(produitId: UUID, draft: Produit? = nil, isNew: Bool = false) {
        self.produitId = produitId
        self._draft = State(initialValue: draft ?? Produit.new())
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section("Produit") {
                TextField("Nom", text: $draft.nom)
                Picker("Catégorie", selection: $draft.categorie) {
                    ForEach(CategorieProduit.allCases) { Text($0.libelle).tag($0) }
                }
                HStack {
                    Text("Prix de vente")
                    Spacer()
                    TextField("", value: $draft.prix_vente, format: .number)
                        .multilineTextAlignment(.trailing).frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("€")
                }
                Toggle("Visible dans le formulaire", isOn: $draft.visible_formulaire)
                Toggle("Actif", isOn: $draft.actif)
            }
            Section("Déclinaisons") {
                ForEach(draft.declinaisons, id: \.self) { d in Text(d) }
                    .onDelete { idx in
                        draft.declinaisons.remove(atOffsets: idx)
                    }
                HStack {
                    TextField("Nouvelle déclinaison", text: $declinaisonNew)
                    Button("Ajouter") {
                        if !declinaisonNew.isEmpty {
                            draft.declinaisons.append(declinaisonNew)
                            declinaisonNew = ""
                        }
                    }
                }
            }
            Section("Recette (matières par unité produite)") {
                ForEach($lignes) { $l in
                    HStack {
                        Picker("Matière", selection: $l.matiere_id) {
                            ForEach(store.matieres) { m in Text(m.nom).tag(m.id) }
                        }
                        TextField("Qté", value: $l.quantite_par_unite, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        if let m = store.matieres.first(where: { $0.id == l.matiere_id }) {
                            Text(m.unite).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    lignes.remove(atOffsets: idx)
                }
                Button {
                    if let m = store.matieres.first {
                        lignes.append(RecetteLigne(id: UUID(), produit_id: produitId,
                                                   matiere_id: m.id, quantite_par_unite: 1))
                    }
                } label: { Label("Ajouter une matière", systemImage: "plus") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau produit" : draft.nom)
        .task { await load() }
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

    private func load() async {
        if !isNew, let p = store.produits.first(where: { $0.id == produitId }) { draft = p }
        if !isNew {
            do { lignes = try await store.repo.recetteLignes(produit: produitId) }
            catch { errorText = error.localizedDescription }
        }
    }

    private func save() async {
        do {
            if isNew { _ = try await store.repo.insert("produit", draft) }
            else { _ = try await store.repo.update("produit", draft, id: draft.id) }
            if !isNew {
                let serveur = try await store.repo.recetteLignes(produit: produitId)
                for l in serveur where !lignes.contains(where: { $0.id == l.id }) {
                    try await store.repo.delete("recette_ligne", id: l.id)
                }
                for l in lignes { _ = try await store.repo.upsert("recette_ligne", l) }
            }
            await store.loadProduits()
            if isNew { dismiss() }
        } catch { errorText = error.localizedDescription }
    }
}
