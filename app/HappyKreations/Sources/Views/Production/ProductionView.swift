import SwiftUI

/// Liste de production du jour, pensée pour la cuisine : ce qu'il faut fabriquer
/// (synthèse + détail par commande), les matières à sortir, et un export PDF
/// imprimable / partageable.
struct ProductionView: View {
    @EnvironmentObject var store: AppStore
    @State private var date: Date
    @State private var lignesParCommande: [UUID: [CommandeLigne]] = [:]
    @State private var recettes: [UUID: [RecetteLigne]] = [:]
    @State private var loading = false
    @State private var pdfURL: URL?
    @State private var errorText: String?

    init(date: Date = Date()) {
        self._date = State(initialValue: date)
    }

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DatePicker("Jour de production", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if commandesDuJour.isEmpty {
                    ContentUnavailableView("Rien à préparer ce jour-là",
                                           systemImage: "tray",
                                           description: Text("Aucune commande à retirer le \(dateLabel)."))
                        .padding(.top, 40)
                } else {
                    syntheseSection
                    matieresSection
                    detailSection
                }
            }
            .padding()
        }
        .navigationTitle("Production")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label("Imprimer / Partager", systemImage: "printer") }
                }
            }
        }
        .task(id: date) { await load() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    // MARK: - Sections à l'écran

    private var syntheseSection: some View {
        ProdCard(titre: "À fabriquer", icone: "hammer.fill", tint: Color.hkRoseDeep) {
            ForEach(synthese) { s in
                SyntheseRow(item: s)
            }
        }
    }

    private var matieresSection: some View {
        ProdCard(titre: "Matières à sortir", icone: "shippingbox.fill", tint: Color.hkSageDeep) {
            if matieres.isEmpty {
                Text("Aucune recette renseignée pour ces produits.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(matieres) { m in
                    MatiereRow(item: m)
                }
            }
        }
    }

    private var detailSection: some View {
        ProdCard(titre: "Détail par commande", icone: "list.bullet.rectangle.fill", tint: Color.hkLavender) {
            ForEach(commandesDuJour) { c in
                CommandeBloc(
                    commande: c,
                    clientNom: store.client(id: c.client_id)?.nom ?? "Sans client",
                    lignes: lignesParCommande[c.id] ?? [],
                    produitNom: { store.produit(id: $0)?.nom ?? "Produit" }
                )
                Divider()
            }
        }
    }

    // MARK: - Données calculées

    private var commandesDuJour: [Commande] {
        store.commandes
            .filter { c in
                guard let d = c.date_retrait else { return false }
                return cal.isDate(d, inSameDayAs: date) && c.statut != .annulee
            }
            .sorted { ($0.date_retrait ?? .distantPast) < ($1.date_retrait ?? .distantPast) }
    }

    private var toutesLignes: [CommandeLigne] {
        commandesDuJour.flatMap { lignesParCommande[$0.id] ?? [] }
    }

    struct DecliCount: Identifiable, Hashable {
        var id: String { nom }
        let nom: String
        let quantite: Int
    }

    struct SyntheseProduit: Identifiable, Hashable {
        let id: UUID
        let nom: String
        let total: Int
        let declinaisons: [DecliCount]
    }

    private var synthese: [SyntheseProduit] {
        var totals: [UUID: Int] = [:]
        var declis: [UUID: [String: Int]] = [:]
        for l in toutesLignes {
            totals[l.produit_id, default: 0] += l.quantite
            let key = (l.declinaison?.isEmpty == false) ? l.declinaison! : "—"
            declis[l.produit_id, default: [:]][key, default: 0] += l.quantite
        }
        return totals.compactMap { pid, total -> SyntheseProduit? in
            guard let p = store.produit(id: pid) else { return nil }
            let d = (declis[pid] ?? [:])
                .sorted { $0.key < $1.key }
                .map { DecliCount(nom: $0.key, quantite: $0.value) }
            return SyntheseProduit(id: pid, nom: p.nom, total: total, declinaisons: d)
        }
        .sorted { $0.nom < $1.nom }
    }

    struct MatiereASortir: Identifiable {
        let id: UUID
        let nom: String
        let quantite: Double
        let unite: String
    }

    private var matieres: [MatiereASortir] {
        var qtyProduit: [UUID: Int] = [:]
        for l in toutesLignes { qtyProduit[l.produit_id, default: 0] += l.quantite }
        var besoins: [UUID: Double] = [:]
        for (pid, qty) in qtyProduit {
            for rl in recettes[pid] ?? [] {
                besoins[rl.matiere_id, default: 0] += rl.quantite_par_unite * Double(qty)
            }
        }
        return besoins.compactMap { mid, q in
            guard let m = store.matieres.first(where: { $0.id == mid }) else { return nil }
            return MatiereASortir(id: mid, nom: m.nom, quantite: q, unite: m.unite)
        }
        .sorted { $0.nom < $1.nom }
    }

    private var dateLabel: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
            .locale(Locale(identifier: "fr_FR")))
    }

    private var isoDate: String { DateFormat.iso(date) }

    // MARK: - Chargement

    private func load() async {
        loading = true
        defer { loading = false }
        let cmds = commandesDuJour
        guard !cmds.isEmpty else { lignesParCommande = [:]; recettes = [:]; pdfURL = nil; return }
        do {
            // Lignes par commande (en parallèle)
            var parCmd: [UUID: [CommandeLigne]] = [:]
            try await withThrowingTaskGroup(of: (UUID, [CommandeLigne]).self) { group in
                for c in cmds {
                    group.addTask { (c.id, try await store.repo.lignes(forCommande: c.id)) }
                }
                for try await (id, lignes) in group { parCmd[id] = lignes }
            }
            lignesParCommande = parCmd

            // Recettes par produit concerné
            let produitIds = Set(parCmd.values.flatMap { $0 }.map(\.produit_id))
            var rec: [UUID: [RecetteLigne]] = [:]
            try await withThrowingTaskGroup(of: (UUID, [RecetteLigne]).self) { group in
                for pid in produitIds {
                    group.addTask { (pid, try await store.repo.recetteLignes(produit: pid)) }
                }
                for try await (pid, lignes) in group { rec[pid] = lignes }
            }
            recettes = rec

            generatePDF()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Export PDF

    @MainActor
    private func generatePDF() {
        let model = PrintModel(
            dateLabel: dateLabel,
            atelier: store.config["nom_atelier"] ?? "HappyKreations",
            synthese: synthese,
            matieres: matieres,
            commandes: commandesDuJour.map { c in
                PrintCommande(
                    id: c.id,
                    client: store.client(id: c.client_id)?.nom ?? "Sans client",
                    lignes: (lignesParCommande[c.id] ?? []).map { l in
                        PrintLigne(nom: store.produit(id: l.produit_id)?.nom ?? "Produit",
                                   quantite: l.quantite,
                                   declinaison: l.declinaison)
                    },
                    allergies: c.allergies,
                    gravure: c.message_gravure,
                    couleur: c.couleur,
                    notes: c.notes)
            })

        let renderer = ImageRenderer(content: ProductionSheet(model: model).frame(width: 595))
        renderer.scale = 2
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("production-\(isoDate).pdf")
        renderer.render { size, ctx in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            ctx(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        pdfURL = url
    }
}

// MARK: - Lignes (sub-Views) pour soulager le type-checker

private struct SyntheseRow: View {
    let item: ProductionView.SyntheseProduit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.nom).font(.headline)
                Spacer()
                Text("× \(item.total)")
                    .font(.headline)
                    .foregroundStyle(Color.hkRoseDeep)
            }
            if showDeclinaisons {
                Text(declinaisonsLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var showDeclinaisons: Bool {
        if item.declinaisons.count > 1 { return true }
        return (item.declinaisons.first?.nom ?? "—") != "—"
    }

    private var declinaisonsLabel: String {
        item.declinaisons
            .map { "\($0.nom) ×\($0.quantite)" }
            .joined(separator: "  ·  ")
    }
}

private struct MatiereRow: View {
    let item: ProductionView.MatiereASortir

    var body: some View {
        HStack {
            Text(item.nom)
            Spacer()
            Text(quantiteLabel).foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }

    private var quantiteLabel: String {
        let q = item.quantite.formatted(.number.precision(.fractionLength(0...2)))
        return "\(q) \(item.unite)"
    }
}

private struct CommandeBloc: View {
    let commande: Commande
    let clientNom: String
    let lignes: [CommandeLigne]
    let produitNom: (UUID) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(clientNom).font(.headline)
            ForEach(lignes) { l in
                LigneRow(ligne: l, produitNom: produitNom(l.produit_id))
            }
            if !commande.allergies.isEmpty {
                etiquette("Allergies : \(commande.allergies.joined(separator: ", "))",
                          color: .orange)
            }
            if let g = commande.message_gravure, !g.isEmpty {
                etiquette("Gravure : « \(g) »", color: Color.hkRoseDeep)
            }
            if let col = commande.couleur, !col.isEmpty {
                etiquette("Couleur : \(col)", color: Color.hkSageDeep)
            }
            if let n = commande.notes, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.secondary).italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func etiquette(_ texte: String, color: Color) -> some View {
        Text(texte)
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

private struct LigneRow: View {
    let ligne: CommandeLigne
    let produitNom: String

    var body: some View {
        HStack {
            Text("• \(produitNom)")
            if let d = ligne.declinaison, !d.isEmpty {
                Text("(\(d))").foregroundStyle(.secondary)
            }
            Spacer()
            Text("× \(ligne.quantite)").foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

// MARK: - Carte de section

private struct ProdCard<Content: View>: View {
    let titre: String
    let icone: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icone).foregroundStyle(tint)
                Text(titre).font(.hkTitle(20, weight: .regular))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }
}

// MARK: - Modèle d'impression (résolu, sans dépendance au store)

struct PrintLigne: Identifiable {
    let id = UUID()
    let nom: String
    let quantite: Int
    let declinaison: String?
}
struct PrintCommande: Identifiable {
    let id: UUID
    let client: String
    let lignes: [PrintLigne]
    let allergies: [String]
    let gravure: String?
    let couleur: String?
    let notes: String?
}
struct PrintModel {
    let dateLabel: String
    let atelier: String
    let synthese: [ProductionView.SyntheseProduit]
    let matieres: [ProductionView.MatiereASortir]
    let commandes: [PrintCommande]
}

/// Feuille imprimable (fond blanc, sobre) rendue en PDF.
struct ProductionSheet: View {
    let model: PrintModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.atelier).font(.system(size: 22, weight: .semibold, design: .serif))
                Text("Feuille de production — \(model.dateLabel)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Divider()

            bloc("À FABRIQUER") {
                ForEach(model.synthese) { s in
                    HStack(alignment: .top) {
                        Text("\(s.total) ×").font(.system(size: 13, weight: .bold)).frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.nom).font(.system(size: 13, weight: .semibold))
                            if s.declinaisons.count > 1 || (s.declinaisons.first?.nom ?? "—") != "—" {
                                Text(s.declinaisons.map { "\($0.nom) ×\($0.quantite)" }
                                    .joined(separator: "  ·  "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }

            if !model.matieres.isEmpty {
                bloc("MATIÈRES À SORTIR") {
                    ForEach(model.matieres) { m in
                        HStack {
                            Text(m.nom).font(.system(size: 12))
                            Spacer()
                            Text("\(m.quantite.formatted(.number.precision(.fractionLength(0...2)))) \(m.unite)")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
            }

            bloc("DÉTAIL PAR COMMANDE") {
                ForEach(model.commandes) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.client).font(.system(size: 13, weight: .bold))
                        ForEach(c.lignes) { l in
                            Text("• \(l.nom)\(l.declinaison.map { " (\($0))" } ?? "")  × \(l.quantite)")
                                .font(.system(size: 12))
                        }
                        if !c.allergies.isEmpty {
                            Text("⚠︎ Allergies : \(c.allergies.joined(separator: ", "))")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                        }
                        if let g = c.gravure, !g.isEmpty {
                            Text("✎ Gravure : « \(g) »").font(.system(size: 11))
                        }
                        if let col = c.couleur, !col.isEmpty {
                            Text("● Couleur : \(col)").font(.system(size: 11))
                        }
                        if let n = c.notes, !n.isEmpty {
                            Text(n).font(.system(size: 11)).foregroundStyle(.secondary).italic()
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(28)
        .frame(width: 595, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func bloc<C: View>(_ titre: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).font(.system(size: 11, weight: .heavy)).tracking(1.5)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
