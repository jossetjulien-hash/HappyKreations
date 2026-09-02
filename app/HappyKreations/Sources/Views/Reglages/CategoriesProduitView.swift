import SwiftUI

/// Gestion des catégories de produits (Chocolats, Meringues, Mariage…).
/// Chaque catégorie porte un emoji (repli visuel sur le formulaire web),
/// une icône SF Symbol (app) et une unité utilisée dans les messages de
/// quantité (« minimum 30 pièces », « minimum 10 cornets »…).
struct CategoriesProduitView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft: CategorieProduit?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(store.categoriesProduit) { c in
                    Button { draft = c } label: { CategorieRow(categorie: c, store: store) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: supprimer)
                if store.categoriesProduit.isEmpty {
                    Text("Aucune catégorie. Ajoutes-en une pour classer tes produits.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Supprimer une catégorie ne supprime pas ses produits : ils se retrouvent simplement « sans catégorie ».")
            }
        }
        .navigationTitle("Catégories de produits")
        .toolbar {
            ToolbarItem {
                Button { draft = CategorieProduit.new() } label: {
                    Label("Nouvelle catégorie", systemImage: "plus")
                }
            }
        }
        .sheet(item: $draft) { c in
            NavigationStack { CategorieEditView(initial: c) }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func supprimer(at offsets: IndexSet) {
        let ids = offsets.map { store.categoriesProduit[$0].id }
        Task {
            do {
                for id in ids { try await store.repo.delete("categorie_produit", id: id) }
                await store.loadCategoriesProduit()
                await store.loadProduits()
            } catch { errorText = error.localizedDescription }
        }
    }
}

private struct CategorieRow: View {
    let categorie: CategorieProduit
    let store: AppStore

    var body: some View {
        let nb = store.produits.filter { $0.categorie_id == categorie.id }.count
        HStack(spacing: 10) {
            Image(systemName: categorie.icone)
                .foregroundStyle(categorie.actif ? Color.hkRoseDeep : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let e = categorie.emoji, !e.isEmpty { Text(e) }
                    Text(categorie.nom.isEmpty ? "(Sans nom)" : categorie.nom).font(.headline)
                }
                Text("\(nb) produit\(nb > 1 ? "s" : "") · unité : \(categorie.unite)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !categorie.actif {
                Text("Masquée")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CategorieEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CategorieProduit
    @State private var errorText: String?
    private let isNew: Bool

    /// Quelques SF Symbols courants pour ne pas avoir à les taper à la main.
    private static let iconesSuggerees = [
        "shippingbox", "cone.fill", "square.grid.3x3.fill", "heart.fill",
        "gift.fill", "birthday.cake.fill", "cup.and.saucer.fill",
        "leaf.fill", "sparkles", "star.fill",
    ]

    init(initial: CategorieProduit) {
        self._draft = State(initialValue: initial)
        self.isNew = initial.nom.isEmpty
    }

    var body: some View {
        Form {
            Section("Catégorie") {
                TextField("Nom (ex. Meringues)", text: $draft.nom)
                TextField("Emoji (ex. 🌀)", text: Binding(
                    get: { draft.emoji ?? "" },
                    set: { draft.emoji = $0.isEmpty ? nil : $0 }))
            }
            Section {
                Picker("Icône", selection: $draft.icone) {
                    ForEach(Self.iconesSuggerees, id: \.self) { nom in
                        Label(nom, systemImage: nom).tag(nom)
                    }
                }
            } header: {
                Text("Icône dans l'app")
            } footer: {
                Text("Affichée quand un produit de cette catégorie n'a pas de photo.")
            }
            Section {
                TextField("Unité (pièces, cornets, coffrets…)", text: $draft.unite)
            } header: {
                Text("Unité")
            } footer: {
                Text("Utilisée dans les messages du formulaire : « Minimum 10 \(draft.unite.isEmpty ? "pièces" : draft.unite) ».")
            }
            Section("Affichage") {
                Toggle("Catégorie active", isOn: $draft.actif)
                Stepper("Ordre : \(draft.ordre) (plus petit = en premier)",
                        value: $draft.ordre, in: 0...100)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouvelle catégorie" : draft.nom)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { Task { await save() } }
                    .disabled(draft.nom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func save() async {
        do {
            _ = try await store.repo.upsert("categorie_produit", draft)
            await store.loadCategoriesProduit()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
