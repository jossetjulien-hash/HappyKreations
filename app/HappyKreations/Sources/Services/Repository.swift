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
        let path = "\(id.uuidString.lowercased()).\(ext.lowercased())"
        let bucket = client.storage.from("produits")
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
}
