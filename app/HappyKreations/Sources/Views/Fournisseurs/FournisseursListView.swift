import SwiftUI

struct FournisseursListView: View {
    @EnvironmentObject var store: AppStore
    @State private var nouveau: Fournisseur?

    var body: some View {
        List {
            Section("Alertes réapprovisionnement") {
                let alertes = store.matieresDisponibles.filter(\.sous_seuil)
                if alertes.isEmpty {
                    Text("Aucune matière sous seuil.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alertes) { d in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(d.nom)
                            Spacer()
                            Text("\(d.disponible.formatted(.number.precision(.fractionLength(0...2)))) \(d.unite) ≤ \(d.stock_actuel.formatted())").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        BonReapproSuggereView()
                    } label: {
                        Label("Préparer des bons de réappro", systemImage: "wand.and.rays")
                    }
                }
            }
            Section("Fournisseurs") {
                ForEach(store.fournisseurs) { f in
                    NavigationLink(destination: FournisseurEditView(fournisseurId: f.id)) {
                        VStack(alignment: .leading) {
                            Text(f.nom).font(.headline)
                            if let c = f.contact, !c.isEmpty {
                                Text(c).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Bons de réappro récents") {
                if store.bonsReappro.isEmpty {
                    Text("Aucun bon").foregroundStyle(.secondary)
                }
                ForEach(store.bonsReappro) { b in
                    NavigationLink(destination: BonReapproEditView(bonId: b.id)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(store.fournisseurs.first(where: { $0.id == b.fournisseur_id })?.nom ?? "—")
                                Text(b.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(b.statut.libelle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fournisseurs & Réappro")
        .toolbar {
            ToolbarItem {
                Button { nouveau = Fournisseur.new() } label: {
                    Label("Nouveau fournisseur", systemImage: "plus")
                }
            }
        }
        .sheet(item: $nouveau) { f in
            NavigationStack {
                FournisseurEditView(fournisseurId: f.id, draft: f, isNew: true)
            }
        }
    }
}

struct FournisseurEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let fournisseurId: UUID
    @State var draft: Fournisseur
    var isNew: Bool = false
    @State private var errorText: String?

    init(fournisseurId: UUID, draft: Fournisseur? = nil, isNew: Bool = false) {
        self.fournisseurId = fournisseurId
        self._draft = State(initialValue: draft ?? Fournisseur.new())
        self.isNew = isNew
    }

    var body: some View {
        Form {
            TextField("Nom", text: $draft.nom)
            TextField("Contact (email, téléphone…)", text: Binding(
                get: { draft.contact ?? "" },
                set: { draft.contact = $0.isEmpty ? nil : $0 }))
            TextField("Notes", text: Binding(
                get: { draft.notes ?? "" },
                set: { draft.notes = $0.isEmpty ? nil : $0 }),
                axis: .vertical
            ).lineLimit(2...6)
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau fournisseur" : draft.nom)
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
        .task {
            if !isNew, let f = store.fournisseurs.first(where: { $0.id == fournisseurId }) {
                draft = f
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func save() async {
        do {
            if isNew { _ = try await store.repo.insert("fournisseur", draft) }
            else { _ = try await store.repo.update("fournisseur", draft, id: draft.id) }
            await store.loadFournisseurs()
            if isNew { dismiss() }
        } catch { errorText = error.localizedDescription }
    }
}

/// Propose un bon de réappro pré-rempli, groupé par fournisseur, à partir des matières sous seuil.
struct BonReapproSuggereView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var liens: [MatiereFournisseur] = []
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        List {
            ForEach(groupes, id: \.fournisseur.id) { groupe in
                Section(groupe.fournisseur.nom) {
                    ForEach(groupe.matieres) { d in
                        HStack {
                            Text(d.nom)
                            Spacer()
                            Text("dispo \(d.disponible.formatted())").font(.caption)
                        }
                    }
                    Button {
                        Task { await creer(groupe: groupe) }
                    } label: {
                        Label("Créer le bon", systemImage: "plus.square.on.square")
                    }
                }
            }
        }
        .navigationTitle("Suggestions de réappro")
        .task { await load() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    struct Groupe {
        var fournisseur: Fournisseur
        var matieres: [MatiereDisponible]
    }

    private var groupes: [Groupe] {
        let sousSeuil = store.matieresDisponibles.filter(\.sous_seuil)
        let parMat = Dictionary(grouping: liens, by: { $0.matiere_id })
        var resultat: [UUID: [MatiereDisponible]] = [:]
        for d in sousSeuil {
            guard let lien = parMat[d.matiere_id]?.first,
                  store.fournisseurs.contains(where: { $0.id == lien.fournisseur_id }) else { continue }
            resultat[lien.fournisseur_id, default: []].append(d)
        }
        return resultat.compactMap { fid, mats in
            guard let f = store.fournisseurs.first(where: { $0.id == fid }) else { return nil }
            return Groupe(fournisseur: f, matieres: mats)
        }
    }

    private func load() async {
        do {
            liens = try await store.repo.selectAll(MatiereFournisseur.self, from: "matiere_fournisseur")
        } catch { errorText = error.localizedDescription }
    }

    private func creer(groupe: Groupe) async {
        loading = true
        defer { loading = false }
        let bon = BonReappro(id: UUID(), fournisseur_id: groupe.fournisseur.id,
                             date: Date(), statut: .brouillon, created_at: nil)
        do {
            let inserted: BonReappro = try await store.repo.insert("bon_reappro", bon)
            for m in groupe.matieres {
                let qte = max(0, (m.stock_actuel * 0) + (m.disponible < 0 ? -m.disponible : 0) + m.stock_actuel * 0 + 1)
                // quantité simple : remettre à un seuil suggéré = 2× seuil_alerte (approx via stock_actuel)
                let suggestion = max(qte, 1)
                let l = ReapproLigne(id: UUID(), bon_reappro_id: inserted.id,
                                     matiere_id: m.matiere_id, quantite: suggestion)
                _ = try await store.repo.insert("reappro_ligne", l)
            }
            await store.loadBons()
        } catch { errorText = error.localizedDescription }
    }
}

struct BonReapproEditView: View {
    @EnvironmentObject var store: AppStore
    let bonId: UUID
    @State private var bon: BonReappro?
    @State private var lignes: [ReapproLigne] = []
    @State private var errorText: String?

    var body: some View {
        Form {
            if let b = bon {
                Section("Bon") {
                    LabeledContent("Fournisseur",
                                   value: store.fournisseurs.first(where: { $0.id == b.fournisseur_id })?.nom ?? "—")
                    LabeledContent("Date", value: b.date.formatted(date: .abbreviated, time: .omitted))
                    Picker("Statut", selection: Binding(
                        get: { b.statut },
                        set: { newVal in
                            var copie = b
                            copie.statut = newVal
                            bon = copie
                            Task { await majStatut() }
                        }
                    )) {
                        ForEach(StatutReappro.allCases) { Text($0.libelle).tag($0) }
                    }
                }
                Section("Lignes") {
                    ForEach(lignes) { l in
                        HStack {
                            Text(store.matieres.first(where: { $0.id == l.matiere_id })?.nom ?? "?")
                            Spacer()
                            Text("\(l.quantite.formatted(.number.precision(.fractionLength(0...2))))")
                        }
                    }
                }
                if b.statut == .recu {
                    Section {
                        Button {
                            Task { await receptionner() }
                        } label: {
                            Label("Encaisser en stock", systemImage: "tray.and.arrow.down")
                        }
                    } footer: {
                        Text("Met à jour le stock_actuel + crée un mouvement \"entrée\" par ligne.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Bon de réappro")
        .task { await load() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func load() async {
        do {
            let all = try await store.repo.selectAll(BonReappro.self, from: "bon_reappro")
            bon = all.first { $0.id == bonId }
            let allLignes: [ReapproLigne] = try await store.repo.selectAll(ReapproLigne.self, from: "reappro_ligne")
            lignes = allLignes.filter { $0.bon_reappro_id == bonId }
        } catch { errorText = error.localizedDescription }
    }

    private func majStatut() async {
        guard let b = bon else { return }
        do {
            _ = try await store.repo.update("bon_reappro", b, id: b.id)
            await store.loadBons()
        } catch { errorText = error.localizedDescription }
    }

    private func receptionner() async {
        for l in lignes {
            let mvt = MouvementStock(id: UUID(), matiere_id: l.matiere_id,
                                     date: Date(), type: .entree, quantite: l.quantite,
                                     origine: "reappro", commande_id: nil)
            do {
                _ = try await store.repo.insert("mouvement_stock", mvt)
                if var m = store.matieres.first(where: { $0.id == l.matiere_id }) {
                    m.stock_actuel += l.quantite
                    _ = try await store.repo.update("matiere", m, id: m.id)
                }
            } catch { errorText = error.localizedDescription }
        }
        await store.loadMatieres()
    }
}
