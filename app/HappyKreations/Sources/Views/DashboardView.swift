import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthStore
    @State private var lignesDuMois: [CommandeLigne] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                aujourdHui
                grid
                prochainsRetraits
                topProduitsView
                alertesView
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Tableau de bord")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await rafraichir() }
                } label: { Label("Rafraîchir", systemImage: "arrow.clockwise") }
            }
        }
        .task { await chargerLignesMois() }
        .onChange(of: store.commandes) { _, _ in
            Task { await chargerLignesMois() }
        }
        .refreshable { await rafraichir() }
    }

    private func rafraichir() async {
        await store.loadAll()
        await chargerLignesMois()
    }

    private func chargerLignesMois() async {
        let ids = commandesDuMois.map(\.id)
        guard !ids.isEmpty else { lignesDuMois = []; return }
        do {
            let chunks = await withTaskGroup(of: [CommandeLigne].self) { group in
                for id in ids {
                    group.addTask { (try? await store.repo.lignes(forCommande: id)) ?? [] }
                }
                var all: [CommandeLigne] = []
                for await c in group { all.append(contentsOf: c) }
                return all
            }
            lignesDuMois = chunks
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(salutation).font(.title2).bold()
            Text(dateHumaine).foregroundStyle(.secondary).font(.subheadline)
        }
    }

    private var salutation: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base: String
        if h < 6 { base = "Bonne nuit" }
        else if h < 12 { base = "Bonjour" }
        else if h < 18 { base = "Bon après-midi" }
        else { base = "Bonsoir" }
        return base + " 👋"
    }

    private var dateHumaine: String {
        Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
    }

    // MARK: - Aujourd'hui

    private var aujourdHui: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let retraitsAujourdhui = store.commandes.filter {
            guard let d = $0.date_retrait else { return false }
            return cal.isDate(d, inSameDayAs: today)
                && $0.statut != .annulee
        }
        return SectionCard(titre: "Aujourd'hui", icone: "sun.max.fill", tint: .orange) {
            if retraitsAujourdhui.isEmpty {
                Text("Aucun retrait prévu aujourd'hui.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(spacing: 8) {
                    ForEach(retraitsAujourdhui) { c in
                        ligneCommande(c, montrerDate: false)
                    }
                }
            }
        }
    }

    // MARK: - KPIs

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            stat("Commandes à venir", value: "\(commandesAVenir.count)",
                 icon: "calendar.badge.clock", tint: .blue)
            stat("Cmd ce mois", value: "\(commandesDuMois.count)",
                 icon: "doc.text.fill", tint: .purple)
            stat("Panier moyen", value: euros(panierMoyenMois),
                 icon: "cart.fill", tint: .teal)
            stat("CA ce mois", value: euros(caMois),
                 icon: "chart.line.uptrend.xyaxis", tint: .indigo)
            stat("Encaissé ce mois", value: euros(encaisseMois),
                 icon: "eurosign.circle", tint: .green)
            stat("Reste dû global", value: euros(resteDuGlobal),
                 icon: "creditcard", tint: .red)
            stat("Alertes stock", value: "\(alertesStock)",
                 icon: "exclamationmark.triangle", tint: .orange)
            stat("En production", value: "\(enProductionCount)",
                 icon: "flame.fill", tint: .pink)
        }
    }

    private func stat(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value).font(.title3).bold().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }

    // MARK: - Prochains retraits

    private var prochainsRetraits: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cmds = store.commandes
            .filter {
                guard let d = $0.date_retrait else { return false }
                return d > today
                    && $0.statut != .annulee && $0.statut != .soldee
            }
            .sorted { ($0.date_retrait ?? .distantFuture) < ($1.date_retrait ?? .distantFuture) }
            .prefix(5)

        return SectionCard(titre: "Prochains retraits", icone: "calendar", tint: .blue) {
            if cmds.isEmpty {
                Text("Rien de programmé.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(cmds)) { c in
                        ligneCommande(c, montrerDate: true)
                    }
                }
            }
        }
    }

    private func ligneCommande(_ c: Commande, montrerDate: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.client(id: c.client_id)?.nom ?? "Sans client").font(.subheadline).bold()
                HStack(spacing: 6) {
                    Text(c.statut.libelle)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(statutTint(c.statut).opacity(0.15)))
                        .foregroundStyle(statutTint(c.statut))
                    if montrerDate, let d = c.date_retrait {
                        Text(d.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(c.total, format: .currency(code: "EUR"))
                .font(.subheadline).bold()
        }
        .padding(.vertical, 4)
    }

    private func statutTint(_ s: StatutCommande) -> Color {
        switch s {
        case .brouillon: return .gray
        case .a_confirmer: return .yellow
        case .confirmee: return .blue
        case .en_production: return .pink
        case .prete: return .green
        case .livree: return .indigo
        case .soldee: return .gray
        case .annulee: return .red
        }
    }

    // MARK: - Top produits

    private var topProduitsView: some View {
        let top = topProduitsMois.prefix(3)
        return SectionCard(titre: "Top produits du mois", icone: "star.fill", tint: .yellow) {
            if top.isEmpty {
                Text("Pas encore de ventes ce mois.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { idx, t in
                        HStack(spacing: 12) {
                            Text("#\(idx + 1)")
                                .font(.headline).foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            Text(t.nom).font(.subheadline)
                            Spacer()
                            Text("\(t.quantite) vendus").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private struct TopProduit: Identifiable {
        let id: UUID
        let nom: String
        let quantite: Int
    }

    private var topProduitsMois: [TopProduit] {
        var compteur: [UUID: Int] = [:]
        for l in lignesDuMois {
            compteur[l.produit_id, default: 0] += l.quantite
        }
        return store.produits.compactMap { p in
            let q = compteur[p.id] ?? 0
            return q > 0 ? TopProduit(id: p.id, nom: p.nom, quantite: q) : nil
        }
        .sorted { $0.quantite > $1.quantite }
    }

    // MARK: - Alertes

    private var alertesView: some View {
        let alertes = store.matieresDisponibles.filter(\.sous_seuil)
        return SectionCard(titre: "Alertes stock", icone: "exclamationmark.triangle.fill", tint: .orange) {
            if alertes.isEmpty {
                Text("Tout est en ordre.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                VStack(spacing: 8) {
                    ForEach(alertes.prefix(5)) { a in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(a.nom).font(.subheadline)
                            Spacer()
                            Text("\(a.disponible.formatted(.number.precision(.fractionLength(0...2)))) \(a.unite)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Calculs

    private var commandesAVenir: [Commande] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.commandes.filter {
            ($0.date_retrait ?? .distantFuture) >= today
            && $0.statut != .annulee && $0.statut != .soldee
        }
    }

    private var commandesDuMois: [Commande] {
        let cal = Calendar.current
        let comp = cal.dateComponents([.year, .month], from: Date())
        guard let monthStart = cal.date(from: comp) else { return [] }
        return store.commandes.filter {
            guard let d = $0.created_at ?? $0.date_retrait else { return false }
            return d >= monthStart && $0.statut != .annulee
        }
    }

    private var caMois: Double {
        commandesDuMois.reduce(0) { $0 + $1.total }
    }

    private var panierMoyenMois: Double {
        let cmds = commandesDuMois
        guard !cmds.isEmpty else { return 0 }
        return cmds.reduce(0) { $0 + $1.total } / Double(cmds.count)
    }

    private var enProductionCount: Int {
        store.commandes.filter { $0.statut == .en_production }.count
    }

    private var alertesStock: Int {
        store.matieresDisponibles.filter(\.sous_seuil).count
    }

    private var encaisseMois: Double {
        let cal = Calendar.current
        let comp = cal.dateComponents([.year, .month], from: Date())
        let monthStart = cal.date(from: comp) ?? Date()
        return store.paiements
            .filter { $0.statut == .reussi && $0.date >= monthStart }
            .reduce(0) { $0 + $1.montant }
    }

    private var resteDuGlobal: Double {
        store.commandes.reduce(0.0) { acc, c in
            if c.statut == .annulee || c.statut == .soldee { return acc }
            let paye = store.paiementsTotal(commande: c.id)
            return acc + max(0, c.total - paye)
        }
    }

    private func euros(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: v as NSNumber) ?? "\(v) €"
    }
}

// MARK: - Composant générique : carte titrée

private struct SectionCard<Content: View>: View {
    let titre: String
    let icone: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icone).foregroundStyle(tint)
                Text(titre).font(.headline)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }
}
