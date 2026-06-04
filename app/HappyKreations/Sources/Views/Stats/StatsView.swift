import SwiftUI
import Charts

/// Statistiques business sur 12 mois glissants : CA, marge, top produits,
/// panier moyen, conversion du formulaire web.
struct StatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var periode: Periode = .douzeMois
    @State private var lignesPeriode: [CommandeLigne] = []
    @State private var loading = false

    enum Periode: String, CaseIterable, Identifiable {
        case troisMois = "3 mois"
        case sixMois = "6 mois"
        case douzeMois = "12 mois"

        var id: String { rawValue }
        var nbMois: Int {
            switch self {
            case .troisMois: return 3
            case .sixMois: return 6
            case .douzeMois: return 12
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Période", selection: $periode) {
                    ForEach(Periode.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)

                kpiSection
                caChart
                topProduitsSection
                conversionSection
            }
            .padding()
        }
        .navigationTitle("Statistiques")
        .task(id: periode) { await chargeLignes() }
        .overlay(alignment: .top) {
            if loading {
                ProgressView().padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private func chargeLignes() async {
        loading = true
        defer { loading = false }
        var toutes: [CommandeLigne] = []
        await withTaskGroup(of: [CommandeLigne].self) { group in
            for c in commandesPeriode {
                group.addTask {
                    (try? await store.repo.lignes(forCommande: c.id)) ?? []
                }
            }
            for await lignes in group { toutes.append(contentsOf: lignes) }
        }
        lignesPeriode = toutes
    }

    // MARK: - KPIs

    private var kpiSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            statCard("CA cumulé", value: euros(caTotalPeriode),
                     icon: "chart.line.uptrend.xyaxis", tint: .indigo,
                     variation: variationPourcent(caTotalPeriode, caPeriodePrecedente))
            statCard("Marge brute", value: margeLabel,
                     icon: "percent", tint: .mint,
                     variation: nil)
            statCard("Commandes", value: "\(commandesPeriode.count)",
                     icon: "doc.text.fill", tint: .purple,
                     variation: variationPourcent(Double(commandesPeriode.count),
                                                  Double(commandesPeriodePrecedente.count)))
            statCard("Panier moyen", value: euros(panierMoyen),
                     icon: "cart.fill", tint: .teal,
                     variation: variationPourcent(panierMoyen, panierMoyenPrecedent))
        }
    }

    private func statCard(_ title: String, value: String, icon: String,
                          tint: Color, variation: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3).bold().foregroundStyle(tint)
            if let v = variation, abs(v) > 0.1 {
                HStack(spacing: 4) {
                    Image(systemName: v >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(v >= 0 ? "+" : "")\(v, format: .number.precision(.fractionLength(0...1))) %")
                    Text("vs période précédente")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .foregroundStyle(v >= 0 ? .green : .red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }

    // MARK: - Chart CA / marge

    private var caChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill").foregroundStyle(Color.hkRoseDeep)
                Text("CA par mois").font(.hkTitle(20, weight: .regular))
            }
            Chart(serieMensuelle) { point in
                BarMark(
                    x: .value("Mois", point.label),
                    y: .value("CA", point.ca)
                )
                .foregroundStyle(Color.hkRose.gradient)
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    if point.ca > 0 {
                        Text(euros(point.ca))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(euros(d)).font(.caption2)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }

    // MARK: - Top produits

    private var topProduitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text("Top produits").font(.hkTitle(20, weight: .regular))
            }
            if topProduits.isEmpty {
                Text("Aucune vente sur la période.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(topProduits.prefix(5).enumerated()), id: \.element.id) { i, p in
                    TopProduitRow(rang: i + 1, produit: p)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }

    // MARK: - Conversion formulaire

    private var conversionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Color.hkSageDeep)
                Text("Formulaire web").font(.hkTitle(20, weight: .regular))
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formulaireCreees)").font(.title3).bold()
                    Text("commandes créées").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(formulairePayees)").font(.title3).bold().foregroundStyle(.green)
                    Text("payées").font(.caption).foregroundStyle(.secondary)
                }
            }
            if formulaireCreees > 0 {
                let taux = Double(formulairePayees) / Double(formulaireCreees) * 100
                let txt = taux.formatted(.number.precision(.fractionLength(0...1)))
                HStack {
                    Text("Taux de conversion")
                    Spacer()
                    Text("\(txt) %").bold()
                        .foregroundStyle(taux >= 70 ? .green : taux >= 40 ? .blue : .orange)
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.secondary))
    }

    // MARK: - Données calculées

    private var debutPeriode: Date {
        Calendar.current.date(byAdding: .month, value: -periode.nbMois, to: Date())
            ?? .distantPast
    }

    /// Début de la période N-1 (la même fenêtre de nbMois, juste avant la
    /// période actuelle). Permet une comparaison à durée égale.
    private var debutPeriodePrecedente: Date {
        Calendar.current.date(byAdding: .month, value: -periode.nbMois * 2, to: Date())
            ?? .distantPast
    }

    private var commandesPeriode: [Commande] {
        store.commandes.filter {
            let d = $0.date_retrait ?? $0.created_at ?? .distantPast
            return d >= debutPeriode && $0.statut != .annulee
        }
    }

    private var commandesPeriodePrecedente: [Commande] {
        store.commandes.filter {
            let d = $0.date_retrait ?? $0.created_at ?? .distantPast
            return d >= debutPeriodePrecedente && d < debutPeriode && $0.statut != .annulee
        }
    }

    private var caTotalPeriode: Double {
        commandesPeriode.reduce(0) { $0 + $1.total }
    }

    private var caPeriodePrecedente: Double {
        commandesPeriodePrecedente.reduce(0) { $0 + $1.total }
    }

    private var panierMoyen: Double {
        commandesPeriode.isEmpty ? 0 : caTotalPeriode / Double(commandesPeriode.count)
    }

    private var panierMoyenPrecedent: Double {
        commandesPeriodePrecedente.isEmpty
            ? 0
            : caPeriodePrecedente / Double(commandesPeriodePrecedente.count)
    }

    /// Variation N vs N-1 en pourcentage. Retourne nil si N-1 est nul (pas de
    /// référence, on n'affiche rien plutôt que de montrer "+∞ %").
    private func variationPourcent(_ courant: Double, _ precedent: Double) -> Double? {
        guard precedent > 0 else { return nil }
        return ((courant - precedent) / precedent) * 100
    }

    private var margeLabel: String {
        var ca: Double = 0, cout: Double = 0
        var manquant = false
        for l in lignesPeriode {
            ca += Double(l.quantite) * l.prix_unitaire
            if let m = store.produitsMarges.first(where: { $0.produit_id == l.produit_id }),
               m.cout_complet == true {
                cout += m.cout_matiere * Double(l.quantite)
            } else {
                manquant = true
            }
        }
        guard ca > 0 else { return "—" }
        let pct = ((ca - cout) / ca) * 100
        let txt = pct.formatted(.number.precision(.fractionLength(0...1)))
        return manquant ? "≈ \(txt) %" : "\(txt) %"
    }

    private var serieMensuelle: [PointMensuel] {
        let cal = Calendar.current
        var buckets: [(date: Date, ca: Double)] = []
        // Initialise les `nbMois` buckets, du plus ancien au plus récent.
        for i in (0..<periode.nbMois).reversed() {
            if let d = cal.date(byAdding: .month, value: -i, to: Date()) {
                buckets.append((cal.startOfMonth(d), 0))
            }
        }
        for c in commandesPeriode {
            guard let d = c.date_retrait ?? c.created_at else { continue }
            let monthStart = cal.startOfMonth(d)
            if let idx = buckets.firstIndex(where: { cal.isDate($0.date, equalTo: monthStart, toGranularity: .month) }) {
                buckets[idx].ca += c.total
            }
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "LLL"
        return buckets.map { PointMensuel(label: fmt.string(from: $0.date).capitalized, ca: $0.ca) }
    }

    struct PointMensuel: Identifiable {
        var id: String { label }
        let label: String
        let ca: Double
    }

    struct TopProduitStats: Identifiable {
        let id: UUID
        let nom: String
        let quantite: Int
        let ca: Double
        let margePourcent: Double?
    }

    /// Top produits sur la période, calculé depuis les lignes chargées.
    private var topProduits: [TopProduitStats] {
        var qty: [UUID: Int] = [:]
        var ca: [UUID: Double] = [:]
        for l in lignesPeriode {
            qty[l.produit_id, default: 0] += l.quantite
            ca[l.produit_id, default: 0] += Double(l.quantite) * l.prix_unitaire
        }
        return store.produits.compactMap { p in
            guard let q = qty[p.id], q > 0 else { return nil }
            let marge = store.produitsMarges.first(where: { $0.produit_id == p.id })
            return TopProduitStats(
                id: p.id, nom: p.nom, quantite: q,
                ca: ca[p.id] ?? 0,
                margePourcent: marge?.cout_complet == true ? marge?.marge_pourcent : nil
            )
        }
        .sorted { $0.quantite > $1.quantite }
    }

    // MARK: - Conversion

    private var formulaireCreees: Int {
        commandesPeriode.filter { $0.canal == .formulaire }.count
    }

    private var formulairePayees: Int {
        commandesPeriode.filter {
            $0.canal == .formulaire
            && $0.statut != .a_confirmer
            && $0.statut != .annulee
        }.count
    }

    // MARK: - Helpers

    private func euros(_ v: Double) -> String {
        v.formatted(.currency(code: "EUR").precision(.fractionLength(0...2)))
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }
}

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

private struct TopProduitRow: View {
    let rang: Int
    let produit: StatsView.TopProduitStats

    var body: some View {
        HStack {
            Text("#\(rang)").font(.subheadline).bold().foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(produit.nom).font(.subheadline).bold()
                HStack(spacing: 6) {
                    Text("\(produit.quantite) vendu\(produit.quantite > 1 ? "s" : "")")
                    Text("·")
                    Text(produit.ca, format: .currency(code: "EUR"))
                    if let m = produit.margePourcent {
                        Text("·")
                        Text("marge \(m, format: .number.precision(.fractionLength(0...1))) %")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
