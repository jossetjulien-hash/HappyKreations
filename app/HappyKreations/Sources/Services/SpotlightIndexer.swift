import Foundation
#if canImport(CoreSpotlight)
import CoreSpotlight
import CoreServices
#endif

/// Indexe commandes et clients dans Spotlight pour qu'ils soient cherchables
/// depuis le centre de recherche système (Cmd+Espace sur macOS, search sur
/// iOS). Tapping un résultat ouvre l'app sur la fiche correspondante.
///
/// L'indexation est privée (per-utilisateur), gratuite, sans Developer Program.
/// Format `CSSearchableItem` — la recherche se déclenche sans configuration
/// côté utilisateur.
@MainActor
enum SpotlightIndexer {

    /// Identifiants des domaines Spotlight (utilisés pour purger plus tard).
    static let domainCommandes = "com.happykreations.app.commandes"
    static let domainClients   = "com.happykreations.app.clients"

    /// Préfixe d'identifiant utilisé par les `CSSearchableItem` — permet de
    /// distinguer un tap sur une commande d'un tap sur un client lors du
    /// retour `userActivity`.
    static let kindCommande = "commande"
    static let kindClient   = "client"

    /// Reconstruit l'index complet à partir des données actuelles du store.
    /// Appelé après chaque `loadAll()`.
    static func reindex(store: AppStore) async {
        #if canImport(CoreSpotlight)
        let index = CSSearchableIndex.default()
        // On ne purge pas pour rester rapide ; on remplace par identifiant.
        let items = commandeItems(store: store) + clientItems(store: store)
        do {
            try await index.indexSearchableItems(items)
        } catch {
            // Spotlight peut être indisponible (machine offline, sandbox…).
            // L'app fonctionne sans, on log et on tolère.
            print("Spotlight reindex failed: \(error.localizedDescription)")
        }
        #endif
    }

    #if canImport(CoreSpotlight)

    private static func commandeItems(store: AppStore) -> [CSSearchableItem] {
        store.commandes.compactMap { c -> CSSearchableItem? in
            let attr = CSSearchableItemAttributeSet(contentType: .text)
            let nomClient = store.client(id: c.client_id)?.nom ?? "Client"
            attr.title = "\(c.refCourte) · \(nomClient)"
            var subtitle: [String] = []
            if let d = c.date_retrait {
                subtitle.append("Retrait \(d.formatted(date: .abbreviated, time: .omitted))")
            }
            subtitle.append(c.statut.libelle)
            subtitle.append(c.total.formatted(.currency(code: "EUR")))
            attr.contentDescription = subtitle.joined(separator: " · ")

            // Keywords : tout ce qui aide à la recherche
            var kw: [String] = [c.refCourte, nomClient]
            if let n = c.numero_facture { kw.append(n) }
            if let e = c.type_evenement { kw.append(e) }
            if let g = c.message_gravure { kw.append(g) }
            attr.keywords = kw

            return CSSearchableItem(
                uniqueIdentifier: "\(kindCommande):\(c.id.uuidString)",
                domainIdentifier: domainCommandes,
                attributeSet: attr
            )
        }
    }

    private static func clientItems(store: AppStore) -> [CSSearchableItem] {
        store.clients.map { client in
            let attr = CSSearchableItemAttributeSet(contentType: .contact)
            attr.title = client.nom
            var subtitle: [String] = []
            if let e = client.email { subtitle.append(e) }
            if let t = client.telephone { subtitle.append(t) }
            attr.contentDescription = subtitle.joined(separator: " · ")
            attr.keywords = [client.nom, client.email, client.telephone].compactMap { $0 }
            attr.supportsPhoneCall = NSNumber(value: client.telephone != nil)
            return CSSearchableItem(
                uniqueIdentifier: "\(kindClient):\(client.id.uuidString)",
                domainIdentifier: domainClients,
                attributeSet: attr
            )
        }
    }

    #endif
}
