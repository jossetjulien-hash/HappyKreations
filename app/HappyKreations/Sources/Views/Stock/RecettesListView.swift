import SwiftUI
import PhotosUI

struct RecettesListView: View {
    @EnvironmentObject var store: AppStore
    @State private var nouveau: Produit?

    var body: some View {
        List {
            ForEach(store.produits) { p in
                NavigationLink(destination: RecetteEditView(produitId: p.id)) {
                    HStack {
                        ProduitThumb(url: p.photo_url, categorie: p.categorie)
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
    @State private var photoItem: PhotosPickerItem?
    @State private var photoUploading = false

    init(produitId: UUID, draft: Produit? = nil, isNew: Bool = false) {
        self.produitId = produitId
        self._draft = State(initialValue: draft ?? Produit.new())
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section("Photo") {
                HStack(spacing: 12) {
                    ProduitThumb(url: draft.photo_url, categorie: draft.categorie, size: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label(draft.photo_url == nil ? "Ajouter une photo" : "Remplacer",
                                  systemImage: "photo.on.rectangle")
                        }
                        .disabled(photoUploading || isNew)
                        if isNew {
                            Text("Enregistrez d'abord le produit pour ajouter une photo.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if photoUploading {
                            ProgressView().controlSize(.small)
                        }
                        if draft.photo_url != nil && !photoUploading {
                            Button(role: .destructive) {
                                draft.photo_url = nil
                                Task { await save(silent: true) }
                            } label: { Label("Supprimer", systemImage: "trash") }
                                .font(.caption)
                        }
                    }
                }
            }
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
            margeSection
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau produit" : draft.nom)
        .task { await load() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
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

    @ViewBuilder
    private var margeSection: some View {
        if !isNew, let marge = store.produitsMarges.first(where: { $0.produit_id == produitId }) {
            Section("Marge") {
                LabeledContent("Prix de vente") {
                    Text(marge.prix_vente, format: .currency(code: "EUR"))
                }
                LabeledContent("Coût matière") {
                    Text(marge.cout_matiere, format: .currency(code: "EUR"))
                        .foregroundStyle(marge.cout_complet == true
                                         ? Color.secondary : Color.orange)
                }
                LabeledContent("Marge brute") {
                    HStack(spacing: 8) {
                        Text(marge.marge, format: .currency(code: "EUR"))
                            .foregroundStyle(margeColor(marge))
                            .fontWeight(.semibold)
                        if let p = marge.marge_pourcent {
                            Text("(\(p, format: .number.precision(.fractionLength(0...1))) %)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if marge.cout_complet != true && !lignes.isEmpty {
                    Text("Certaines matières n'ont pas de coût renseigné — la marge est sous-estimée.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if lignes.isEmpty {
                    Text("Renseigne la recette pour calculer la marge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func margeColor(_ m: ProduitMarge) -> Color {
        guard let p = m.marge_pourcent else { return .primary }
        if p >= 60 { return .green }
        if p >= 40 { return .blue }
        if p >= 20 { return .orange }
        return .red
    }

    private func load() async {
        if !isNew, let p = store.produits.first(where: { $0.id == produitId }) { draft = p }
        if !isNew {
            do { lignes = try await store.repo.recetteLignes(produit: produitId) }
            catch { errorText = error.localizedDescription }
        }
    }

    private func save(silent: Bool = false) async {
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
            // Recharge la vue marges (les coûts dépendent des recettes modifiées).
            await store.loadMatieres()
            if isNew && !silent { dismiss() }
        } catch { errorText = error.localizedDescription }
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        photoUploading = true
        defer { photoUploading = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            // Compresse en JPEG si possible pour limiter la taille.
            let (payload, ext) = compressedJPEG(data) ?? (data, "jpg")
            let url = try await store.repo.uploadPhotoProduit(
                produit: produitId, data: payload, ext: ext)
            draft.photo_url = url
            _ = try await store.repo.update("produit", draft, id: draft.id)
            await store.loadProduits()
        } catch { errorText = error.localizedDescription }
    }

    private func compressedJPEG(_ data: Data) -> (Data, String)? {
        #if canImport(UIKit)
        if let img = UIImage(data: data),
           let jpeg = img.jpegData(compressionQuality: 0.8) {
            return (jpeg, "jpg")
        }
        #endif
        return nil
    }
}

// MARK: - Vignette produit

struct ProduitThumb: View {
    let url: String?
    let categorie: CategorieProduit
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Image(systemName: categorie == .coffret ? "shippingbox" : "cone")
                .foregroundStyle(.tint)
        }
    }
}
