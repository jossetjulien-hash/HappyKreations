import Foundation
import SwiftUI

/// Export comptable annuel — registre des recettes pour micro-entreprise.
///
/// Format CSV : livre des recettes conforme à l'obligation micro-entreprise
/// (date, référence, client, nature, montant TTC, moyen de règlement).
/// Format PDF : récap visuel imprimable (charte HappyKreations).
@MainActor
enum AccountingExport {

    struct LigneRecette: Identifiable {
        let id = UUID()
        let date: Date
        let reference: String        // 8 premiers caractères de la commande
        let client: String
        let nature: String           // "Vente" pour les chocolats/meringues
        let montantTTC: Double
        let moyenReglement: String   // "Stripe", "Espèces", "CB", "Virement"…
    }

    struct Recap {
        let annee: Int
        let lignes: [LigneRecette]
        var totalAnnuel: Double { lignes.reduce(0) { $0 + $1.montantTTC } }
        var nbOperations: Int { lignes.count }

        /// Totaux par mois (1..12), zéro si pas d'opération.
        var totauxMensuels: [(mois: Int, total: Double, nb: Int)] {
            let cal = Calendar(identifier: .gregorian)
            var buckets = Array(repeating: (total: 0.0, nb: 0), count: 13)
            for l in lignes {
                let m = cal.component(.month, from: l.date)
                buckets[m].total += l.montantTTC
                buckets[m].nb += 1
            }
            return (1...12).map { (mois: $0, total: buckets[$0].total, nb: buckets[$0].nb) }
        }

        /// Totaux par moyen de règlement (ex. Stripe 4500€, Espèces 800€).
        var parMoyen: [(moyen: String, total: Double)] {
            var dict: [String: Double] = [:]
            for l in lignes { dict[l.moyenReglement, default: 0] += l.montantTTC }
            return dict.map { (moyen: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }
        }
    }

    /// Construit le récap pour une année à partir des paiements réussis et des
    /// commandes associées.
    static func build(annee: Int, store: AppStore) -> Recap {
        let cal = Calendar(identifier: .gregorian)
        let lignes: [LigneRecette] = store.paiements
            .filter { $0.statut == .reussi && cal.component(.year, from: $0.date) == annee }
            .sorted { $0.date < $1.date }
            .map { p in
                let cmd = store.commandes.first { $0.id == p.commande_id }
                let client = store.client(id: cmd?.client_id)?.nom ?? "Client"
                let ref = String(p.commande_id.uuidString.prefix(8)).uppercased()
                return LigneRecette(
                    date: p.date,
                    reference: ref,
                    client: client,
                    nature: "Vente — \(store.config["nom_atelier"] ?? "Atelier")",
                    montantTTC: p.montant,
                    moyenReglement: p.moyen.libelle
                )
            }
        return Recap(annee: annee, lignes: lignes)
    }

    // MARK: - CSV (livre des recettes)

    static func csv(_ recap: Recap) -> String {
        let isoDate: (Date) -> String = { d in
            let f = DateFormatter()
            f.dateFormat = "dd/MM/yyyy"; f.locale = Locale(identifier: "fr_FR")
            return f.string(from: d)
        }
        var out = "Date;Référence;Client;Nature;Montant TTC (€);Moyen de règlement\n"
        for l in recap.lignes {
            let montant = String(format: "%.2f", l.montantTTC).replacingOccurrences(of: ".", with: ",")
            out += [
                isoDate(l.date),
                l.reference,
                csvEscape(l.client),
                csvEscape(l.nature),
                montant,
                csvEscape(l.moyenReglement),
            ].joined(separator: ";") + "\n"
        }
        let totalTxt = String(format: "%.2f", recap.totalAnnuel).replacingOccurrences(of: ".", with: ",")
        out += ";;;Total annuel;\(totalTxt);\n"
        return out
    }

    private static func csvEscape(_ s: String) -> String {
        s.contains(";") || s.contains("\"") || s.contains("\n")
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }

    // MARK: - PDF récap

    static func generatePDF(_ recap: Recap, nomAtelier: String) -> URL? {
        let renderer = ImageRenderer(
            content: AccountingSheet(recap: recap, nomAtelier: nomAtelier).frame(width: 595))
        renderer.scale = 2
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("registre-recettes-\(recap.annee).pdf")
        renderer.render { size, ctx in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            ctx(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return url
    }
}

// MARK: - Feuille PDF (charte HappyKreations)

private struct AccountingSheet: View {
    let recap: AccountingExport.Recap
    let nomAtelier: String

    private static let moisFr = [
        "—", "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
        "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nomAtelier)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Text("Registre des recettes — Année \(String(format: "%d", recap.annee))")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text("Document obligatoire — régime micro-entreprise")
                    .font(.system(size: 10)).foregroundStyle(.secondary).italic()
            }
            Divider()

            // Synthèse en haut
            HStack(spacing: 16) {
                kpi("Total annuel TTC", euros(recap.totalAnnuel), main: true)
                kpi("Opérations", "\(recap.nbOperations)")
            }

            sectionTitle("RÉCAPITULATIF MENSUEL")
            VStack(spacing: 2) {
                ForEach(recap.totauxMensuels, id: \.mois) { row in
                    HStack {
                        Text(Self.moisFr[row.mois]).font(.system(size: 11))
                        Spacer()
                        Text("\(row.nb) op.").font(.system(size: 10))
                            .foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                        Text(euros(row.total)).font(.system(size: 11, weight: .medium))
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    Divider().opacity(0.3)
                }
            }

            if !recap.parMoyen.isEmpty {
                sectionTitle("PAR MOYEN DE RÈGLEMENT")
                VStack(spacing: 2) {
                    ForEach(recap.parMoyen, id: \.moyen) { row in
                        HStack {
                            Text(row.moyen).font(.system(size: 11))
                            Spacer()
                            Text(euros(row.total)).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            if !recap.lignes.isEmpty {
                sectionTitle("DÉTAIL DES OPÉRATIONS")
                // Entête
                HStack {
                    Text("Date").bold().frame(width: 60, alignment: .leading)
                    Text("Réf.").bold().frame(width: 56, alignment: .leading)
                    Text("Client").bold().frame(maxWidth: .infinity, alignment: .leading)
                    Text("Règlement").bold().frame(width: 70, alignment: .leading)
                    Text("Montant").bold().frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

                ForEach(recap.lignes) { l in
                    HStack {
                        Text(courtDate(l.date)).frame(width: 60, alignment: .leading)
                        Text(l.reference).frame(width: 56, alignment: .leading)
                            .font(.system(size: 9, design: .monospaced))
                        Text(l.client).frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(l.moyenReglement).frame(width: 70, alignment: .leading)
                            .lineLimit(1)
                        Text(euros(l.montantTTC)).frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 10))
                    .padding(.vertical, 1)
                    Divider().opacity(0.2)
                }
            }

            Spacer(minLength: 10)
            HStack {
                Text("Édité le \(courtDate(Date()))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("happykreations")
                    .font(.system(size: 11, weight: .light, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 595, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func kpi(_ titre: String, _ val: String, main: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                .foregroundStyle(.secondary)
            Text(val).font(.system(size: main ? 20 : 16, weight: .semibold, design: .serif))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.984, green: 0.965, blue: 0.937)) // crème
        .cornerRadius(10)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .heavy)).tracking(1.5)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func courtDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"; f.locale = Locale(identifier: "fr_FR")
        return f.string(from: d)
    }

    private func euros(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.locale = Locale(identifier: "fr_FR")
        return f.string(from: v as NSNumber) ?? "\(v) €"
    }
}
