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
    var photo_url: String?
    var qte_min: Int?
    var qte_max: Int?
    var created_at: Date?

    static func new() -> Produit {
        Produit(id: UUID(), nom: "", categorie: .coffret, prix_vente: 0,
                declinaisons: [], visible_formulaire: false, actif: true,
                photo_url: nil)
    }

    init(id: UUID, nom: String, categorie: CategorieProduit, prix_vente: Double,
         declinaisons: [String], visible_formulaire: Bool, actif: Bool,
         photo_url: String? = nil, qte_min: Int? = nil, qte_max: Int? = nil,
         created_at: Date? = nil) {
        self.id = id; self.nom = nom; self.categorie = categorie
        self.prix_vente = prix_vente; self.declinaisons = declinaisons
        self.visible_formulaire = visible_formulaire; self.actif = actif
        self.photo_url = photo_url
        self.qte_min = qte_min; self.qte_max = qte_max
        self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, categorie, prix_vente, declinaisons, visible_formulaire,
             actif, photo_url, qte_min, qte_max, created_at
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
        photo_url = try c.decodeIfPresent(String.self, forKey: .photo_url)
        qte_min = try c.decodeIfPresent(Int.self, forKey: .qte_min)
        qte_max = try c.decodeIfPresent(Int.self, forKey: .qte_max)
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
    var cout_unitaire: Double?
    var created_at: Date?

    static func new() -> Matiere {
        Matiere(id: UUID(), nom: "", unite: "g", stock_actuel: 0, seuil_alerte: 0)
    }

    init(id: UUID, nom: String, unite: String, stock_actuel: Double,
         seuil_alerte: Double, cout_unitaire: Double? = nil, created_at: Date? = nil) {
        self.id = id; self.nom = nom; self.unite = unite
        self.stock_actuel = stock_actuel; self.seuil_alerte = seuil_alerte
        self.cout_unitaire = cout_unitaire
        self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, unite, stock_actuel, seuil_alerte, cout_unitaire, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        unite = try c.decode(String.self, forKey: .unite)
        stock_actuel = try c.decodeDouble(.stock_actuel)
        seuil_alerte = try c.decodeDouble(.seuil_alerte)
        cout_unitaire = c.decodeDoubleIfPresent(.cout_unitaire)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

/// Vue agrégée `v_produit_marge` : coût matière et marge d'un produit.
struct ProduitMarge: Codable, Identifiable, Hashable {
    var produit_id: UUID
    var nom: String
    var prix_vente: Double
    var cout_matiere: Double
    var marge: Double
    var marge_pourcent: Double?
    /// `true` si toutes les matières de la recette ont un coût renseigné ;
    /// `nil` si le produit n'a pas de recette du tout.
    var cout_complet: Bool?

    var id: UUID { produit_id }

    enum CodingKeys: String, CodingKey {
        case produit_id, nom, prix_vente, cout_matiere, marge, marge_pourcent, cout_complet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        produit_id = try c.decode(UUID.self, forKey: .produit_id)
        nom = try c.decode(String.self, forKey: .nom)
        prix_vente = try c.decodeDouble(.prix_vente)
        cout_matiere = try c.decodeDouble(.cout_matiere)
        marge = try c.decodeDouble(.marge)
        marge_pourcent = c.decodeDoubleIfPresent(.marge_pourcent)
        cout_complet = try c.decodeIfPresent(Bool.self, forKey: .cout_complet)
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

    /// Référence courte affichable dès la création — les 4 premiers caractères
    /// de l'UUID en majuscule, préfixés `#`. Stable et unique pour cette
    /// commande, complémentaire du numéro de facture (séquentiel mais attribué
    /// uniquement à confirmation).
    var refCourte: String {
        "#" + String(id.uuidString.prefix(4)).uppercased()
    }
    var client_id: UUID?
    var canal: CanalCommande
    var type_evenement: String?
    var date_evenement: Date?
    var date_retrait: Date?
    var statut: StatutCommande
    var total: Double
    var acompte: Double
    var notes: String?
    var allergies: [String]
    var message_gravure: String?
    var couleur: String?
    var photo_ref_url: String?
    var photo_resultat_url: String?
    var numero_facture: String?
    var rappel_envoye_at: Date?
    var email_confirmation_ouvert_at: Date?
    var email_rappel_ouvert_at: Date?
    var mode_remise: ModeRemise
    var zone_livraison_id: UUID?
    var frais_livraison: Double
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
         allergies: [String] = [], message_gravure: String? = nil, couleur: String? = nil,
         photo_ref_url: String? = nil,
         mode_remise: ModeRemise = .retrait, zone_livraison_id: UUID? = nil,
         frais_livraison: Double = 0,
         created_by: UUID? = nil, created_at: Date? = nil, updated_at: Date? = nil) {
        self.id = id; self.client_id = client_id; self.canal = canal
        self.type_evenement = type_evenement; self.date_evenement = date_evenement
        self.date_retrait = date_retrait; self.statut = statut
        self.total = total; self.acompte = acompte; self.notes = notes
        self.allergies = allergies; self.message_gravure = message_gravure; self.couleur = couleur
        self.photo_ref_url = photo_ref_url
        self.mode_remise = mode_remise; self.zone_livraison_id = zone_livraison_id
        self.frais_livraison = frais_livraison
        self.created_by = created_by; self.created_at = created_at; self.updated_at = updated_at
    }

    enum CodingKeys: String, CodingKey {
        case id, client_id, canal, type_evenement, date_evenement, date_retrait,
             statut, total, acompte, notes, allergies, message_gravure, couleur,
             photo_ref_url, photo_resultat_url, numero_facture, rappel_envoye_at,
             email_confirmation_ouvert_at, email_rappel_ouvert_at,
             mode_remise, zone_livraison_id, frais_livraison,
             created_by, created_at, updated_at
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
        allergies = try c.decodeIfPresent([String].self, forKey: .allergies) ?? []
        message_gravure = try c.decodeIfPresent(String.self, forKey: .message_gravure)
        couleur = try c.decodeIfPresent(String.self, forKey: .couleur)
        photo_ref_url = try c.decodeIfPresent(String.self, forKey: .photo_ref_url)
        photo_resultat_url = try c.decodeIfPresent(String.self, forKey: .photo_resultat_url)
        numero_facture = try c.decodeIfPresent(String.self, forKey: .numero_facture)
        rappel_envoye_at = try c.decodeIfPresent(Date.self, forKey: .rappel_envoye_at)
        email_confirmation_ouvert_at = try c.decodeIfPresent(Date.self, forKey: .email_confirmation_ouvert_at)
        email_rappel_ouvert_at = try c.decodeIfPresent(Date.self, forKey: .email_rappel_ouvert_at)
        mode_remise = try c.decodeIfPresent(ModeRemise.self, forKey: .mode_remise) ?? .retrait
        zone_livraison_id = try c.decodeIfPresent(UUID.self, forKey: .zone_livraison_id)
        frais_livraison = c.decodeDoubleIfPresent(.frais_livraison) ?? 0
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
    var telephone: String?
    var email: String?
    var adresse: String?
    var notes: String?

    static func new() -> Fournisseur {
        Fournisseur(id: UUID(), nom: "")
    }

    init(id: UUID, nom: String, contact: String? = nil,
         telephone: String? = nil, email: String? = nil,
         adresse: String? = nil, notes: String? = nil) {
        self.id = id; self.nom = nom; self.contact = contact
        self.telephone = telephone; self.email = email
        self.adresse = adresse; self.notes = notes
    }

    /// Initiales pour l'avatar de la fiche contact (max 2 caractères).
    var initiales: String {
        let parts = nom.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map(String.init)
        return chars.joined().uppercased()
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

    static func new() -> CommandeEntrante {
        CommandeEntrante(id: UUID(), canal: .manuel, message_brut: "",
                         donnee_extraite: nil, statut: .a_valider,
                         recu_le: Date(), commande_id: nil)
    }

    /// Première ligne du message (sert d'aperçu dans la liste).
    var apercu: String {
        message_brut
            .split(separator: "\n").first.map(String.init) ?? message_brut
    }

    /// Nom potentiel de l'expéditeur extrait depuis `donnee_extraite`.
    var expediteur: String? {
        donnee_extraite?.client?.nom
    }
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

// MARK: - Avis post-retrait

struct Avis: Codable, Identifiable, Hashable {
    var id: UUID
    var commande_id: UUID
    var note: Int?
    var texte: String?
    var auteur: String?
    var visible: Bool
    var cree_le: Date
}

// MARK: - Code promo

enum ModeRemise: String, Codable, CaseIterable, Identifiable {
    case retrait
    case livraison
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .retrait:   return "Retrait sur place"
        case .livraison: return "Livraison"
        }
    }
}

struct ZoneLivraison: Codable, Identifiable, Hashable {
    var id: UUID
    var nom: String
    var tarif: Double
    var description: String?
    var ordre: Int
    var actif: Bool
    var created_at: Date?

    static func new() -> ZoneLivraison {
        ZoneLivraison(id: UUID(), nom: "", tarif: 0, description: nil,
                      ordre: 0, actif: true)
    }

    init(id: UUID, nom: String, tarif: Double, description: String?,
         ordre: Int, actif: Bool, created_at: Date? = nil) {
        self.id = id; self.nom = nom; self.tarif = tarif
        self.description = description
        self.ordre = ordre; self.actif = actif
        self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, tarif, description, ordre, actif, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        tarif = try c.decodeDouble(.tarif)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        ordre = try c.decodeIfPresent(Int.self, forKey: .ordre) ?? 0
        actif = try c.decode(Bool.self, forKey: .actif)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }
}

struct CodePromo: Codable, Identifiable, Hashable {
    var id: UUID
    var code: String
    var type: String           // "pourcent" ou "fixe"
    var valeur: Double
    var date_debut: Date
    var date_fin: Date
    var max_utilisations: Int?
    var utilisations: Int
    var actif: Bool
    var description: String?
    var created_at: Date?

    static func new() -> CodePromo {
        let now = Date()
        let demain = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return CodePromo(
            id: UUID(), code: "", type: "pourcent", valeur: 10,
            date_debut: now, date_fin: demain,
            max_utilisations: nil, utilisations: 0, actif: true)
    }

    init(id: UUID, code: String, type: String, valeur: Double,
         date_debut: Date, date_fin: Date,
         max_utilisations: Int? = nil, utilisations: Int = 0,
         actif: Bool = true, description: String? = nil,
         created_at: Date? = nil) {
        self.id = id; self.code = code; self.type = type; self.valeur = valeur
        self.date_debut = date_debut; self.date_fin = date_fin
        self.max_utilisations = max_utilisations
        self.utilisations = utilisations
        self.actif = actif; self.description = description
        self.created_at = created_at
    }

    enum CodingKeys: String, CodingKey {
        case id, code, type, valeur, date_debut, date_fin,
             max_utilisations, utilisations, actif, description, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        type = try c.decode(String.self, forKey: .type)
        valeur = try c.decodeDouble(.valeur)
        date_debut = try c.decode(Date.self, forKey: .date_debut)
        date_fin = try c.decode(Date.self, forKey: .date_fin)
        max_utilisations = try c.decodeIfPresent(Int.self, forKey: .max_utilisations)
        utilisations = try c.decode(Int.self, forKey: .utilisations)
        actif = try c.decode(Bool.self, forKey: .actif)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
    }

    var libelleReduction: String {
        if type == "fixe" {
            return valeur.formatted(.currency(code: "EUR"))
        }
        return "\(Int(valeur)) %"
    }

    var estValideMaintenant: Bool {
        let n = Date()
        return actif && n >= date_debut && n <= date_fin
            && (max_utilisations == nil || utilisations < (max_utilisations ?? Int.max))
    }
}

// MARK: - Témoignage

struct Temoignage: Codable, Identifiable, Hashable {
    var id: UUID
    var auteur: String
    var texte: String
    var evenement: String?
    var visible: Bool
    var ordre: Int
    var created_at: Date?

    static func new() -> Temoignage {
        Temoignage(id: UUID(), auteur: "", texte: "", evenement: nil, visible: true, ordre: 0)
    }
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

