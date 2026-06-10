import Foundation
import Supabase

/// CRUD typé minimaliste : encapsule les appels Postgrest pour chaque table.
struct Repository {
    let client: SupabaseClient = SupabaseService.shared.client

    // MARK: - Generic helpers

    func selectAll<T: Decodable>(_ type: T.Type, from table: String,
                                 orderBy: String? = nil, ascending: Bool = true) async throws -> [T] {
        let base = client.from(table).select()
        if let orderBy {
            return try await base.order(orderBy, ascending: ascending).execute().value
        }
        return try await base.execute().value
    }

    func insert<T: Encodable & Decodable>(_ table: String, _ row: T) async throws -> T {
        try await client.from(table).insert(row, returning: .representation)
            .select().single().execute().value
    }

    func upsert<T: Encodable & Decodable>(_ table: String, _ row: T,
                                          onConflict: String? = nil) async throws -> T {
        try await client.from(table).upsert(row, onConflict: onConflict, returning: .representation)
            .select().single().execute().value
    }

    func update<T: Encodable & Decodable>(_ table: String, _ row: T, id: UUID) async throws -> T {
        try await client.from(table).update(row, returning: .representation)
            .eq("id", value: id).select().single().execute().value
    }

    func delete(_ table: String, id: UUID) async throws {
        try await client.from(table).delete().eq("id", value: id).execute()
    }

    // MARK: - Spécifiques (vues, filtres métier)

    func matieresDisponibles() async throws -> [MatiereDisponible] {
        try await client.from("v_matiere_disponible").select().execute().value
    }

    func produitsMarges() async throws -> [ProduitMarge] {
        try await client.from("v_produit_marge").select().execute().value
    }

    func commandesAVenir(limit: Int = 50) async throws -> [Commande] {
        try await client.from("commande")
            .select()
            .gte("date_retrait", value: DateFormat.iso(Date()))
            .order("date_retrait", ascending: true)
            .limit(limit)
            .execute().value
    }

    func paiements(forCommande id: UUID) async throws -> [Paiement] {
        try await client.from("paiement").select()
            .eq("commande_id", value: id)
            .order("date", ascending: true)
            .execute().value
    }

    func lignes(forCommande id: UUID) async throws -> [CommandeLigne] {
        try await client.from("commande_ligne").select()
            .eq("commande_id", value: id)
            .execute().value
    }

    func evenements(forCommande id: UUID) async throws -> [CommandeEvenement] {
        try await client.from("commande_evenement").select()
            .eq("commande_id", value: id)
            .order("created_at", ascending: true)
            .execute().value
    }

    /// Tous les paiements d'un client (toutes commandes confondues).
    private struct CommandeId: Decodable { let id: UUID }
    func paiementsParClient(_ clientId: UUID) async throws -> [Paiement] {
        let cmds: [CommandeId] = try await client.from("commande").select("id")
            .eq("client_id", value: clientId).execute().value
        guard !cmds.isEmpty else { return [] }
        return try await client.from("paiement").select()
            .in("commande_id", values: cmds.map(\.id))
            .order("date", ascending: false)
            .execute().value
    }

    func recetteLignes(produit id: UUID) async throws -> [RecetteLigne] {
        try await client.from("recette_ligne").select()
            .eq("produit_id", value: id)
            .execute().value
    }

    func mouvements(matiere id: UUID, limit: Int = 50) async throws -> [MouvementStock] {
        try await client.from("mouvement_stock").select()
            .eq("matiere_id", value: id)
            .order("date", ascending: false)
            .limit(limit)
            .execute().value
    }

    func config() async throws -> [ConfigItem] {
        try await client.from("config").select().execute().value
    }

    func setConfig(cle: String, valeur: String) async throws {
        try await client.from("config")
            .upsert(["cle": cle, "valeur": valeur], onConflict: "cle")
            .execute()
    }

    // MARK: - Storage : photos produits

    /// Upload une photo dans le bucket `produits` et retourne l'URL publique.
    /// `data` doit être du JPEG/PNG. `ext` est l'extension sans le point (jpg, png, heic…).
    func uploadPhotoProduit(produit id: UUID, data: Data, ext: String) async throws -> String {
        try await uploadPhoto(bucket: "produits", id: id, data: data, ext: ext)
    }

    /// Upload une photo de référence pour une commande (« comme ce style »).
    /// Bucket `commandes-refs`, public en lecture.
    func uploadPhotoCommande(commande id: UUID, data: Data, ext: String) async throws -> String {
        try await uploadPhoto(bucket: "commandes-refs", id: id, data: data, ext: ext)
    }

    /// Upload la photo « après production » du résultat fini. Bucket
    /// `commandes-resultats`, public — alimente la galerie Inspirations du site.
    func uploadPhotoResultat(commande id: UUID, data: Data, ext: String) async throws -> String {
        try await uploadPhoto(bucket: "commandes-resultats", id: id, data: data, ext: ext)
    }

    private func uploadPhoto(bucket name: String, id: UUID, data: Data, ext: String) async throws -> String {
        let path = "\(id.uuidString.lowercased()).\(ext.lowercased())"
        let bucket = client.storage.from(name)
        _ = try await bucket.upload(
            path,
            data: data,
            options: FileOptions(contentType: contentType(forExt: ext), upsert: true)
        )
        let publicURL = try bucket.getPublicURL(path: path)
        // Cache-bust pour que l'UI rafraîchisse l'image après remplacement.
        return "\(publicURL.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"
    }

    private func contentType(forExt ext: String) -> String {
        switch ext.lowercased() {
        case "png":  return "image/png"
        case "heic": return "image/heic"
        case "webp": return "image/webp"
        default:     return "image/jpeg"
        }
    }

    // MARK: - Stripe : lien de paiement à partager

    enum MotifPaiement: String { case acompte, solde, libre }

    struct LienPaiement: Decodable {
        let checkout_url: String
        let montant: Double
        let libelle: String
    }

    /// Génère une URL Stripe Checkout pour la commande donnée. Si `montant`
    /// est nil, l'edge function choisit automatiquement (acompte si non versé,
    /// sinon reste dû).
    func creerLienPaiement(commande id: UUID,
                           montant: Double? = nil,
                           motif: MotifPaiement = .libre) async throws -> LienPaiement {
        struct Body: Encodable {
            let commande_id: String
            let montant: Double?
            let motif: String
        }
        let body = Body(
            commande_id: id.uuidString.lowercased(),
            montant: montant,
            motif: motif.rawValue
        )
        let res: LienPaiement = try await client.functions.invoke(
            "creer-lien-paiement",
            options: FunctionInvokeOptions(body: body)
        )
        return res
    }
}
