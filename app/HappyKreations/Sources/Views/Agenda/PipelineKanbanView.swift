import SwiftUI

/// Pipeline visuelle des commandes par statut. Cartes triées par date de retrait.
/// Tap → ouvre l'édition. Long press → menu rapide de changement de statut.
struct PipelineKanbanView: View {
    @EnvironmentObject var store: AppStore

    /// Statuts affichés dans le pipeline (dans l'ordre du flux opérationnel).
    private let colonnes: [StatutCommande] = [
        .a_confirmer, .confirmee, .en_production, .prete, .livree
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pipeline des commandes").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(colonnes) { statut in
                        Colonne(statut: statut, commandes: filtrer(statut))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func filtrer(_ statut: StatutCommande) -> [Commande] {
        store.commandes
            .filter { $0.statut == statut }
            .sorted { ($0.date_retrait ?? .distantFuture) < ($1.date_retrait ?? .distantFuture) }
    }
}

private struct Colonne: View {
    @EnvironmentObject var store: AppStore
    let statut: StatutCommande
    let commandes: [Commande]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(couleur).frame(width: 8, height: 8)
                Text(statut.libelle).font(.subheadline).bold()
                Spacer()
                Text("\(commandes.count)")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.background.secondary, in: Capsule())
            }
            .padding(.horizontal, 10).padding(.top, 8)

            if commandes.isEmpty {
                Text("Aucune commande").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(commandes) { c in
                        Carte(commande: c)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
        }
        .frame(width: 220, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(couleur.opacity(0.4), lineWidth: 1)
        )
    }

    private var couleur: Color {
        switch statut {
        case .a_confirmer:   return .gray
        case .confirmee:     return .blue
        case .en_production: return .orange
        case .prete:         return .purple
        case .livree:        return .teal
        default:             return .gray
        }
    }
}

private struct Carte: View {
    @EnvironmentObject var store: AppStore
    let commande: Commande

    var body: some View {
        NavigationLink(destination: CommandeEditView(commandeId: commande.id)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.client(id: commande.client_id)?.nom ?? "Client")
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    if let d = commande.date_retrait {
                        Text(d, format: .dateTime.day().month(.abbreviated))
                            .font(.caption)
                    } else {
                        Text("sans date").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
                if let e = commande.type_evenement, !e.isEmpty {
                    Text(e).font(.caption2)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                HStack {
                    Spacer()
                    Text(commande.total, format: .currency(code: "EUR"))
                        .font(.caption).bold()
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(StatutCommande.allCases) { s in
                if s != commande.statut && s != .brouillon {
                    Button {
                        Task { await changer(s) }
                    } label: {
                        Label("Déplacer vers \(s.libelle)", systemImage: "arrow.right")
                    }
                }
            }
        }
    }

    private func changer(_ nouveau: StatutCommande) async {
        var maj = commande
        maj.statut = nouveau
        do {
            _ = try await store.repo.update("commande", maj, id: maj.id)
            await store.loadCommandes()
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
