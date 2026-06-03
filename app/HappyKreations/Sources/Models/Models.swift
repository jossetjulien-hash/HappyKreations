import Foundation

// MARK: - Utilisateur

struct AppUser: Codable, Identifiable, Hashable {
    let id: UUID
    var nom: String
    var role: String
    var created_at: Date?
}

// MARK: - Client

struct Client: Codable, Identifiable, Hashable {
    var id: UUID
    var nom: String
    var telephone: String?
    var email: String?
    var messenger: String?
    var notes: String?
    var created_at: Date?

    static func new(nom: String = "") -> Client {
        Client(id: UUID(), nom: nom)
    }
}

// MARK: - Produit

struct Produit: Codable, Identifiable, Hashable {
    var id: UUID
    var nom: String
    var categorie: CategorieProduit
    var prix_vente: Double
    var declinaisons: [String]
    var visible_formulaire: Bool
    var actif: Bool
    var created_at: Date?

    static func new() -> Produit {
        Produit(id: UUID(), nom: "", categorie: .coffret, prix_vente: 0,
                declinaisons: [], visible_formulaire: false, actif: true)
    }

    init(id: UUID, nom: String, categorie: CategorieProduit, prix_vente: Double,
         declinaisons: [String], visible_formulaire: Bool, actif: Bool,
         created_at: Date? = nil) {
        self.id = id; self.nom = nom; self.categorie = categorie
        self.prix_vente = prix_vente; self.declinaisons = declinaisons
        self.visible_formulaire = visible_formulaire; self.actif = actif
        self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, categorie, prix_vente, declinaisons, visible_formulaire, actif, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        categorie = try c.decode(CategorieProduit.self, forKey: .categorie)
        prix_vente = try c.decodeDouble(.prix_vente)
        declinaisons = try c.decodeIfPresent([String].self, forKey: .declinaisons) ?? []
        visible_formulaire = try c.decode(Bool.self, forKey: .visible_formulaire)
        actif = try c.decode(Bool.self, forKey: .actif)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

// MARK: - Matière + Recette + Stock

struct Matiere: Codable, Identifiable, Hashable {
    var id: UUID
    var nom: String
    var unite: String
    var stock_actuel: Double
    var seuil_alerte: Double
    var created_at: Date?

    static func new() -> Matiere {
        Matiere(id: UUID(), nom: "", unite: "g", stock_actuel: 0, seuil_alerte: 0)
    }

    init(id: UUID, nom: String, unite: String, stock_actuel: Double,
         seuil_alerte: Double, created_at: Date? = nil) {
        self.id = id; self.nom = nom; self.unite = unite
        self.stock_actuel = stock_actuel; self.seuil_alerte = seuil_alerte
        self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, unite, stock_actuel, seuil_alerte, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        unite = try c.decode(String.self, forKey: .unite)
        stock_actuel = try c.decodeDouble(.stock_actuel)
        seuil_alerte = try c.decodeDouble(.seuil_alerte)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

struct MatiereDisponible: Codable, Identifiable, Hashable {
    var matiere_id: UUID
    var nom: String
    var unite: String
    var stock_actuel: Double
    var reserve: Double
    var disponible: Double
    var sous_seuil: Bool

    var id: UUID { matiere_id }

    enum CodingKeys: String, CodingKey {
        case matiere_id, nom, unite, stock_actuel, reserve, disponible, sous_seuil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matiere_id = try c.decode(UUID.self, forKey: .matiere_id)
        nom = try c.decode(String.self, forKey: .nom)
        unite = try c.decode(String.self, forKey: .unite)
        stock_actuel = try c.decodeDouble(.stock_actuel)
        reserve = try c.decodeDouble(.reserve)
        disponible = try c.decodeDouble(.disponible)
        sous_seuil = try c.decode(Bool.self, forKey: .sous_seuil)
    }
}

struct RecetteLigne: Codable, Identifiable, Hashable {
    var id: UUID
    var produit_id: UUID
    var matiere_id: UUID
    var quantite_par_unite: Double

    init(id: UUID, produit_id: UUID, matiere_id: UUID, quantite_par_unite: Double) {
        self.id = id; self.produit_id = produit_id
        self.matiere_id = matiere_id; self.quantite_par_unite = quantite_par_unite
    }

    enum CodingKeys: String, CodingKey {
        case id, produit_id, matiere_id, quantite_par_unite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        produit_id = try c.decode(UUID.self, forKey: .produit_id)
        matiere_id = try c.decode(UUID.self, forKey: .matiere_id)
        quantite_par_unite = try c.decodeDouble(.quantite_par_unite)
    }
}

struct MouvementStock: Codable, Identifiable, Hashable {
    var id: UUID
    var matiere_id: UUID
    var date: Date
    var type: TypeMouvement
    var quantite: Double
    var origine: String?
    var commande_id: UUID?
    var created_at: Date?

    init(id: UUID, matiere_id: UUID, date: Date, type: TypeMouvement,
         quantite: Double, origine: String?, commande_id: UUID?, created_at: Date? = nil) {
        self.id = id; self.matiere_id = matiere_id; self.date = date
        self.type = type; self.quantite = quantite; self.origine = origine
        self.commande_id = commande_id; self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, matiere_id, date, type, quantite, origine, commande_id, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        matiere_id = try c.decode(UUID.self, forKey: .matiere_id)
        date = try c.decode(Date.self, forKey: .date)
        type = try c.decode(TypeMouvement.self, forKey: .type)
        quantite = try c.decodeDouble(.quantite)
        origine = try c.decodeIfPresent(String.self, forKey: .origine)
        commande_id = try c.decodeIfPresent(UUID.self, forKey: .commande_id)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

// MARK: - Commande

struct Commande: Codable, Identifiable, Hashable {
    var id: UUID
    var client_id: UUID?
    var canal: CanalCommande
    var type_evenement: String?
    var date_evenement: Date?
    var date_retrait: Date?
    var statut: StatutCommande
    var total: Double
    var acompte: Double
    var notes: String?
    var created_by: UUID?
    var created_at: Date?
    var updated_at: Date?

    static func new() -> Commande {
        Commande(id: UUID(), client_id: nil, canal: .manuel, type_evenement: nil,
                 date_evenement: nil, date_retrait: nil, statut: .brouillon,
                 total: 0, acompte: 0, notes: nil)
    }

    init(id: UUID, client_id: UUID?, canal: CanalCommande, type_evenement: String?,
         date_evenement: Date?, date_retrait: Date?, statut: StatutCommande,
         total: Double, acompte: Double, notes: String?,
         created_by: UUID? = nil, created_at: Date? = nil, updated_at: Date? = nil) {
        self.id = id; self.client_id = client_id; self.canal = canal
        self.type_evenement = type_evenement; self.date_evenement = date_evenement
        self.date_retrait = date_retrait; self.statut = statut
        self.total = total; self.acompte = acompte; self.notes = notes
        self.created_by = created_by; self.created_at = created_at; self.updated_at = updated_at
    }

    enum CodingKeys: String, CodingKey {
        case id, client_id, canal, type_evenement, date_evenement, date_retrait,
             statut, total, acompte, notes, created_by, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        client_id = try c.decodeIfPresent(UUID.self, forKey: .client_id)
        canal = try c.decode(CanalCommande.self, forKey: .canal)
        type_evenement = try c.decodeIfPresent(String.self, forKey: .type_evenement)
        date_evenement = try c.decodeIfPresent(Date.self, forKey: .date_evenement)
        date_retrait = try c.decodeIfPresent(Date.self, forKey: .date_retrait)
        statut = try c.decode(StatutCommande.self, forKey: .statut)
        total = try c.decodeDouble(.total)
        acompte = try c.decodeDouble(.acompte)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        created_by = try c.decodeIfPresent(UUID.self, forKey: .created_by)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
        updated_at = try c.decodeIfPresent(Date.self, forKey: .updated_at)
    }
}

struct CommandeLigne: Codable, Identifiable, Hashable {
    var id: UUID
    var commande_id: UUID
    var produit_id: UUID
    var quantite: Int
    var prix_unitaire: Double
    var declinaison: String?

    init(id: UUID, commande_id: UUID, produit_id: UUID, quantite: Int,
         prix_unitaire: Double, declinaison: String?) {
        self.id = id; self.commande_id = commande_id; self.produit_id = produit_id
        self.quantite = quantite; self.prix_unitaire = prix_unitaire
        self.declinaison = declinaison
    }

    enum CodingKeys: String, CodingKey {
        case id, commande_id, produit_id, quantite, prix_unitaire, declinaison
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        commande_id = try c.decode(UUID.self, forKey: .commande_id)
        produit_id = try c.decode(UUID.self, forKey: .produit_id)
        quantite = try c.decode(Int.self, forKey: .quantite)
        prix_unitaire = try c.decodeDouble(.prix_unitaire)
        declinaison = try c.decodeIfPresent(String.self, forKey: .declinaison)
    }
}

struct Paiement: Codable, Identifiable, Hashable {
    var id: UUID
    var commande_id: UUID
    var date: Date
    var montant: Double
    var moyen: MoyenPaiement
    var stripe_session_id: String?
    var stripe_payment_intent: String?
    var statut: StatutPaiement
    var created_at: Date?

    init(id: UUID, commande_id: UUID, date: Date, montant: Double,
         moyen: MoyenPaiement, stripe_session_id: String?, stripe_payment_intent: String?,
         statut: StatutPaiement, created_at: Date? = nil) {
        self.id = id; self.commande_id = commande_id; self.date = date
        self.montant = montant; self.moyen = moyen
        self.stripe_session_id = stripe_session_id
        self.stripe_payment_intent = stripe_payment_intent
        self.statut = statut; self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, commande_id, date, montant, moyen,
             stripe_session_id, stripe_payment_intent, statut, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        commande_id = try c.decode(UUID.self, forKey: .commande_id)
        date = try c.decode(Date.self, forKey: .date)
        montant = try c.decodeDouble(.montant)
        moyen = try c.decode(MoyenPaiement.self, forKey: .moyen)
        stripe_session_id = try c.decodeIfPresent(String.self, forKey: .stripe_session_id)
        stripe_payment_intent = try c.decodeIfPresent(String.self, forKey: .stripe_payment_intent)
        statut = try c.decode(StatutPaiement.self, forKey: .statut)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

// MARK: - Fournisseur & réappro

struct Fournisseur: Codable, Identifiable, Hashable {
    var id: UUID
    var nom: String
    var contact: String?
    var notes: String?

    static func new() -> Fournisseur {
        Fournisseur(id: UUID(), nom: "", contact: nil, notes: nil)
    }
}

struct MatiereFournisseur: Codable, Identifiable, Hashable {
    var id: UUID
    var fournisseur_id: UUID
    var matiere_id: UUID
    var reference: String?
    var prix_achat: Double?
    var conditionnement: String?

    init(id: UUID, fournisseur_id: UUID, matiere_id: UUID,
         reference: String?, prix_achat: Double?, conditionnement: String?) {
        self.id = id; self.fournisseur_id = fournisseur_id
        self.matiere_id = matiere_id; self.reference = reference
        self.prix_achat = prix_achat; self.conditionnement = conditionnement
    }

    enum CodingKeys: String, CodingKey {
        case id, fournisseur_id, matiere_id, reference, prix_achat, conditionnement
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fournisseur_id = try c.decode(UUID.self, forKey: .fournisseur_id)
        matiere_id = try c.decode(UUID.self, forKey: .matiere_id)
        reference = try c.decodeIfPresent(String.self, forKey: .reference)
        prix_achat = c.decodeDoubleIfPresent(.prix_achat)
        conditionnement = try c.decodeIfPresent(String.self, forKey: .conditionnement)
    }
}

struct BonReappro: Codable, Identifiable, Hashable {
    var id: UUID
    var fournisseur_id: UUID
    var date: Date
    var statut: StatutReappro
    var created_at: Date?
}

struct ReapproLigne: Codable, Identifiable, Hashable {
    var id: UUID
    var bon_reappro_id: UUID
    var matiere_id: UUID
    var quantite: Double

    init(id: UUID, bon_reappro_id: UUID, matiere_id: UUID, quantite: Double) {
        self.id = id; self.bon_reappro_id = bon_reappro_id
        self.matiere_id = matiere_id; self.quantite = quantite
    }

    enum CodingKeys: String, CodingKey {
        case id, bon_reappro_id, matiere_id, quantite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bon_reappro_id = try c.decode(UUID.self, forKey: .bon_reappro_id)
        matiere_id = try c.decode(UUID.self, forKey: .matiere_id)
        quantite = try c.decodeDouble(.quantite)
    }
}

// MARK: - Auto-import (boîte de réception)

struct CommandeEntrante: Codable, Identifiable, Hashable {
    var id: UUID
    var canal: CanalCommande
    var message_brut: String
    var donnee_extraite: ExtractionPayload?
    var statut: StatutEntrante
    var recu_le: Date
    var commande_id: UUID?
}

/// Payload retourné par l'Edge Function `parse-claude`.
struct ExtractionPayload: Codable, Hashable {
    struct ClientInfo: Codable, Hashable {
        var nom: String?
        var contact: String?
    }
    struct LigneInfo: Codable, Hashable {
        var produit: String?
        var quantite: Int?
        var declinaison: String?
    }
    var client: ClientInfo?
    var canal: String?
    var type_evenement: String?
    var date_evenement: String?
    var date_retrait: String?
    var lignes: [LigneInfo]?
    var notes: String?
}

// MARK: - Capacité & Config

struct CapaciteJour: Codable, Identifiable, Hashable {
    var date: Date
    var plafond_unites: Int?
    var bloque: Bool

    var id: Date { date }
}

struct ConfigItem: Codable, Identifiable, Hashable {
    var cle: String
    var valeur: String
    var id: String { cle }
}

