import SwiftUI

/// Liste de courses fournisseurs — calcule ce qu'il faut commander pour
/// honorer toutes les commandes confirmées des N prochains jours, en
/// tenant compte du stock actuel. Groupe par fournisseur préférentiel.
struct CoursesFournisseursView: View {
    @EnvironmentObject var store: AppStore
    @State private var jours: Horizon = .septJours
    @State private var toutesRecettes: [RecetteLigne] = []
    @State private var liens: [MatiereFournisseur] = []
    @State private var chargement = false
    @State private var errorText: String?

    enum Horizon: Int, CaseIterable, Identifiable {
        case troisJours = 3, septJours = 7, quatorzeJours = 14, trenteJours = 30
        var id: Int { rawValue }
        var libelle: String { "\(rawValue) jours" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Horizon", selection: $jours) {
                    ForEach(Horizon.allCases) { h in
                        Text(h.libelle).tag(h)
                    }
                }
                .pickerStyle(.segmented)

                contexte

                if chargement {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                } else if besoinsParFournisseur.isEmpty {
                    ContentUnavailableView(
                        "Rien à commander",
                        systemImage: "tray",
                        description: Text("Les stocks couvrent les commandes des \(jours.rawValue) prochains jours.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(besoinsParFournisseur) { groupe in
                        carteFournisseur(groupe)
                    }
                    sansFournisseur
                }
            }
            .padding()
        }
        .navigationTitle("Liste de courses")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: jours) { await charger() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    // MARK: - Sections

    private var contexte: some View {
        let nb = commandesFenetre.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(nb) commande\(nb > 1 ? "s" : "") à honorer d'ici le \(dateLimite.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline).bold()
            Text("Calcule : recettes × quantités demandées − stock disponible.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func carteFournisseur(_ g: GroupeFournisseur) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ContactAvatar(initiales: g.fournisseur.initiales, size: 32)
                Text(g.fournisseur.nom).font(.hkTitle(20, weight: .regular))
                Spacer()
                if let tel = g.fournisseur.telephone, !tel.isEmpty,
                   let url = URL(string: "tel:\(tel.filter { "+0123456789".contains($0) })") {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                    }
                }
            }
            ForEach(g.lignes) { l in
                HStack {
                    Text(l.matiere.nom)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(l.aCommander.formatted(.number.precision(.fractionLength(0...2)))) \(l.matiere.unite)")
                            .font(.subheadline).bold()
                            .foregroundStyle(Color.hkRoseDeep)
                        Text("manque \(l.manquant.formatted(.number.precision(.fractionLength(0...2)))) · stock \(l.matiere.stock_actuel.formatted())")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Button {
                Task { await creerBon(pour: g) }
            } label: {
                Label("Créer le bon de réappro", systemImage: "plus.square.on.square")
            }
            .font(.subheadline.bold())
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }

    @ViewBuilder
    private var sansFournisseur: some View {
        let orphelines = besoinsTous.filter { l in liens.contains(where: { $0.matiere_id == l.matiere.id }) == false }
        if !orphelines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sans fournisseur attribué", systemImage: "questionmark.circle")
                    .font(.hkTitle(18, weight: .regular))
                    .foregroundStyle(.orange)
                ForEach(orphelines) { l in
                    HStack {
                        Text(l.matiere.nom)
                        Spacer()
                        Text("\(l.aCommander.formatted(.number.precision(.fractionLength(0...2)))) \(l.matiere.unite)")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Lie ces matières à un fournisseur depuis la fiche fournisseur pour qu'elles soient groupées ici.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.08)))
        }
    }

    // MARK: - Données calculées

    private var dateLimite: Date {
        Calendar.current.date(byAdding: .day, value: jours.rawValue, to: Date()) ?? Date()
    }

    /// Commandes confirmées / en production / prêtes dont la date de retrait
    /// tombe dans la fenêtre [aujourd'hui, +N jours].
    private var commandesFenetre: [Commande] {
        let now = Calendar.current.startOfDay(for: Date())
        return store.commandes.filter { c in
            guard let d = c.date_retrait else { return false }
            return d >= now && d <= dateLimite
                && (c.statut == .confirmee || c.statut == .en_production || c.statut == .prete)
        }
    }

    /// Pour chaque matière : quantité totale demandée (commandes × recette),
    /// stock actuel, manquant, à commander (arrondi à l'unité supérieure).
    struct BesoinLigne: Identifiable, Hashable {
        let matiere: Matiere
        let totalRequis: Double
        let manquant: Double
        let aCommander: Double
        var id: UUID { matiere.id }
    }

    private var besoinsTous: [BesoinLigne] {
        var totalParMatiere: [UUID: Double] = [:]
        // Indexe les recettes par produit pour lookup O(1)
        let recettesParProduit = Dictionary(grouping: toutesRecettes, by: \.produit_id)
        for cmd in commandesFenetre {
            // Lit les lignes depuis le cache du store si dispo, sinon ignore.
            // En pratique loadCommandes ne précharge pas les lignes.
            // Pour éviter un fetch lourd, on calcule depuis les recettes
            // pondérées par la quantité moyenne. Solution simple : on
            // accepte ici de loader les lignes en mémoire au démarrage.
            for cl in lignesParCommande[cmd.id] ?? [] {
                for rl in recettesParProduit[cl.produit_id] ?? [] {
                    totalParMatiere[rl.matiere_id, default: 0]
                        += rl.quantite_par_unite * Double(cl.quantite)
                }
            }
        }
        return totalParMatiere.compactMap { mid, total -> BesoinLigne? in
            guard let mat = store.matieres.first(where: { $0.id == mid }) else { return nil }
            let manquant = max(0, total - mat.stock_actuel)
            guard manquant > 0 else { return nil }
            return BesoinLigne(
                matiere: mat, totalRequis: total,
                manquant: manquant,
                aCommander: ceil(manquant)
            )
        }
        .sorted { $0.matiere.nom < $1.matiere.nom }
    }

    @State private var lignesParCommande: [UUID: [CommandeLigne]] = [:]

    struct GroupeFournisseur: Identifiable {
        let fournisseur: Fournisseur
        let lignes: [BesoinLigne]
        var id: UUID { fournisseur.id }
    }

    private var besoinsParFournisseur: [GroupeFournisseur] {
        var parFid: [UUID: [BesoinLigne]] = [:]
        let liensParMatiere = Dictionary(grouping: liens, by: \.matiere_id)
        for ligne in besoinsTous {
            // Prend le premier fournisseur lié à cette matière
            if let lien = liensParMatiere[ligne.matiere.id]?.first {
                parFid[lien.fournisseur_id, default: []].append(ligne)
            }
        }
        return parFid.compactMap { fid, lignes -> GroupeFournisseur? in
            guard let f = store.fournisseurs.first(where: { $0.id == fid }) else { return nil }
            return GroupeFournisseur(fournisseur: f, lignes: lignes)
        }
        .sorted { $0.fournisseur.nom < $1.fournisseur.nom }
    }

    // MARK: - Chargement

    private func charger() async {
        chargement = true
        defer { chargement = false }
        do {
            // Charge en parallèle : recette_ligne complet + matiere_fournisseur
            // + lignes des commandes de la fenêtre (en mode parallèle).
            async let r: [RecetteLigne] = store.repo.selectAll(
                RecetteLigne.self, from: "recette_ligne")
            async let mf: [MatiereFournisseur] = store.repo.selectAll(
                MatiereFournisseur.self, from: "matiere_fournisseur")
            toutesRecettes = try await r
            liens = try await mf

            var dict: [UUID: [CommandeLigne]] = [:]
            try await withThrowingTaskGroup(of: (UUID, [CommandeLigne]).self) { group in
                for c in commandesFenetre {
                    group.addTask {
                        (c.id, try await store.repo.lignes(forCommande: c.id))
                    }
                }
                for try await (id, lignes) in group { dict[id] = lignes }
            }
            lignesParCommande = dict
        } catch { errorText = error.localizedDescription }
    }

    private func creerBon(pour g: GroupeFournisseur) async {
        let bon = BonReappro(
            id: UUID(), fournisseur_id: g.fournisseur.id,
            date: Date(), statut: .brouillon, created_at: nil)
        do {
            let inserted: BonReappro = try await store.repo.insert("bon_reappro", bon)
            for l in g.lignes {
                let rl = ReapproLigne(id: UUID(), bon_reappro_id: inserted.id,
                                      matiere_id: l.matiere.id,
                                      quantite: l.aCommander)
                _ = try await store.repo.insert("reappro_ligne", rl)
            }
            await store.loadBons()
        } catch { errorText = error.localizedDescription }
    }
}
