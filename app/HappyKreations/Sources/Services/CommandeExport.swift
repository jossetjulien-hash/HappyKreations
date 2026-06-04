import Foundation
import SwiftUI

/// Génération des PDF par commande :
/// - Facture (numérotée, conforme micro-entreprise).
/// - Étiquettes à coller sur chaque coffret (nom client + date + allergies +
///   message à graver), une étiquette par unité.
@MainActor
enum CommandeExport {

    struct Atelier {
        let nom: String
        let adresse: String
        let siret: String
        let email: String
        let telephone: String

        static func from(config: [String: String]) -> Atelier {
            Atelier(
                nom: config["nom_atelier"] ?? "HappyKreations",
                adresse: config["adresse_atelier"] ?? "",
                siret: config["siret_atelier"] ?? "",
                email: config["email_atelier"] ?? "",
                telephone: config["telephone_atelier"] ?? ""
            )
        }
    }

    // MARK: - Facture

    static func generateFacturePDF(
        commande: Commande,
        client: Client?,
        lignes: [CommandeLigne],
        produit: (UUID) -> Produit?,
        atelier: Atelier,
        encaisse: Double
    ) -> URL? {
        let lignesFmt = lignes.map { l in
            FactureLigne(
                produit: produit(l.produit_id)?.nom ?? "Produit",
                declinaison: l.declinaison,
                quantite: l.quantite,
                prixUnitaire: l.prix_unitaire
            )
        }
        let view = FactureSheet(
            commande: commande,
            client: client,
            lignes: lignesFmt,
            atelier: atelier,
            encaisse: encaisse
        ).frame(width: 595) // A4 portrait approx

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let nom = commande.numero_facture ?? "facture-\(commande.id.uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nom).pdf")
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

    // MARK: - Étiquettes coffret

    /// Une étiquette par UNITÉ commandée. Layout A4 portrait 2×5 = 10 étiquettes
    /// par page, dimensions ~90×50 mm (Avery J8159 / L7165).
    static func generateEtiquettesPDF(
        commande: Commande,
        client: Client?,
        lignes: [CommandeLigne],
        produit: (UUID) -> Produit?,
        atelier: Atelier
    ) -> URL? {
        // Une entrée par UNITÉ
        var unites: [EtiquetteUnite] = []
        for l in lignes {
            let nomProd = produit(l.produit_id)?.nom ?? "Produit"
            for _ in 0..<max(1, l.quantite) {
                unites.append(EtiquetteUnite(
                    produit: nomProd,
                    declinaison: l.declinaison
                ))
            }
        }
        guard !unites.isEmpty else { return nil }

        let view = EtiquettesSheet(
            commande: commande,
            client: client,
            atelier: atelier,
            unites: unites
        ).frame(width: 595)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let nom = commande.numero_facture
            ?? "etiquettes-\(commande.id.uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("etiquettes-\(nom).pdf")
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

// MARK: - Modèles internes

struct FactureLigne {
    let produit: String
    let declinaison: String?
    let quantite: Int
    let prixUnitaire: Double
    var total: Double { Double(quantite) * prixUnitaire }
}

struct EtiquetteUnite: Identifiable {
    let id = UUID()
    let produit: String
    let declinaison: String?
}

// MARK: - Feuille FACTURE

struct FactureSheet: View {
    let commande: Commande
    let client: Client?
    let lignes: [FactureLigne]
    let atelier: CommandeExport.Atelier
    let encaisse: Double

    private var total: Double { lignes.reduce(0) { $0 + $1.total } }
    private var resteDu: Double { max(0, total - encaisse) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête atelier + facture
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(atelier.nom)
                        .font(.system(size: 22, weight: .light, design: .serif))
                    if !atelier.adresse.isEmpty {
                        Text(atelier.adresse).font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if !atelier.email.isEmpty || !atelier.telephone.isEmpty {
                        Text([atelier.email, atelier.telephone].filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if !atelier.siret.isEmpty {
                        Text("SIRET \(atelier.siret)")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("FACTURE").font(.system(size: 11, weight: .heavy)).tracking(2)
                        .foregroundStyle(.secondary)
                    Text(commande.numero_facture ?? "(en attente)")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                    Text("Date : \(dateCourte(Date()))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if let d = commande.date_retrait {
                        Text("Retrait : \(dateCourte(d))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()

            // Client
            if let c = client {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FACTURÉ À").font(.system(size: 9, weight: .heavy)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(c.nom).font(.system(size: 13, weight: .semibold))
                    if let e = c.email, !e.isEmpty {
                        Text(e).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let t = c.telephone, !t.isEmpty {
                        Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            // Lignes
            VStack(spacing: 4) {
                HStack {
                    Text("Désignation").bold().frame(maxWidth: .infinity, alignment: .leading)
                    Text("Qté").bold().frame(width: 40, alignment: .trailing)
                    Text("Prix unit.").bold().frame(width: 70, alignment: .trailing)
                    Text("Total").bold().frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .border(width: 0.5, edges: [.bottom], color: .secondary.opacity(0.4))

                ForEach(Array(lignes.enumerated()), id: \.offset) { _, l in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.produit).font(.system(size: 12))
                            if let d = l.declinaison, !d.isEmpty {
                                Text(d).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(l.quantite)").font(.system(size: 12))
                            .frame(width: 40, alignment: .trailing)
                        Text(euros(l.prixUnitaire)).font(.system(size: 12))
                            .frame(width: 70, alignment: .trailing)
                        Text(euros(l.total)).font(.system(size: 12, weight: .medium))
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }

            // Totaux
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Total TTC").foregroundStyle(.secondary)
                        Text(euros(total)).font(.system(size: 14, weight: .semibold))
                            .frame(width: 100, alignment: .trailing)
                    }
                    HStack {
                        Text("Acompte versé").foregroundStyle(.secondary)
                        Text("− \(euros(encaisse))").foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    HStack {
                        Text("Reste à régler").bold()
                        Text(euros(resteDu)).font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.788, green: 0.514, blue: 0.533))
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 12))
                .padding(12)
                .background(Color(red: 0.984, green: 0.965, blue: 0.937)) // crème
                .cornerRadius(8)
            }

            Spacer(minLength: 0)

            // Mentions légales
            VStack(alignment: .leading, spacing: 4) {
                Text("TVA non applicable, article 293 B du CGI.")
                    .font(.system(size: 9)).italic()
                Text("Document tenant lieu de facture — Régime micro-entreprise.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 595, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func euros(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.locale = Locale(identifier: "fr_FR")
        return f.string(from: v as NSNumber) ?? "\(v) €"
    }

    private func dateCourte(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"; f.locale = Locale(identifier: "fr_FR")
        return f.string(from: d)
    }
}

// MARK: - Feuille ÉTIQUETTES

struct EtiquettesSheet: View {
    let commande: Commande
    let client: Client?
    let atelier: CommandeExport.Atelier
    let unites: [EtiquetteUnite]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<lignesGrille, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { col in
                        let idx = row * 2 + col
                        if idx < unites.count {
                            etiquette(unites[idx])
                        } else {
                            Color.clear.frame(width: 260, height: 130)
                        }
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .padding(20)
        .frame(width: 595, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var lignesGrille: Int {
        (unites.count + 1) / 2
    }

    private func etiquette(_ u: EtiquetteUnite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(atelier.nom)
                .font(.system(size: 9, weight: .heavy)).tracking(1.5)
                .foregroundStyle(.secondary)
            Text(client?.nom ?? "Client")
                .font(.system(size: 14, weight: .semibold, design: .serif))
            Text(u.produit + (u.declinaison.map { " · \($0)" } ?? ""))
                .font(.system(size: 11))
                .lineLimit(2)
            if let d = commande.date_retrait {
                Text("Retrait : \(dateCourte(d))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if !commande.allergies.isEmpty {
                Text("⚠︎ \(commande.allergies.joined(separator: ", "))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
            }
            if let g = commande.message_gravure, !g.isEmpty {
                Text("✎ « \(g) »").font(.system(size: 9)).italic()
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(width: 260, height: 130, alignment: .topLeading)
        .background(Color(red: 0.984, green: 0.965, blue: 0.937)) // crème
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                Color(red: 0.788, green: 0.514, blue: 0.533).opacity(0.4),
                style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func dateCourte(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"; f.locale = Locale(identifier: "fr_FR")
        return f.string(from: d)
    }
}

// MARK: - Helper bordure partielle (utilisée par la facture)

private extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorders(width: width, edges: edges).foregroundStyle(color))
    }
}

private struct EdgeBorders: View {
    let width: CGFloat
    let edges: [Edge]
    var body: some View {
        ZStack {
            ForEach(edges, id: \.self) { e in
                EdgeShape(edge: e).stroke(lineWidth: width)
            }
        }
    }
}

private struct EdgeShape: Shape {
    let edge: Edge
    func path(in r: CGRect) -> Path {
        var p = Path()
        switch edge {
        case .top:    p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        case .bottom: p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case .leading: p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case .trailing: p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        return p
    }
}
