import Foundation

enum CategorieProduit: String, Codable, CaseIterable, Identifiable {
    case coffret, cornet
    var id: String { rawValue }
    var libelle: String { self == .coffret ? "Coffret" : "Cornet" }
}

enum CanalCommande: String, Codable, CaseIterable, Identifiable {
    case formulaire, messenger, email, manuel
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .formulaire: return "Formulaire en ligne"
        case .messenger:  return "Messenger"
        case .email:      return "Email"
        case .manuel:     return "Saisie manuelle"
        }
    }
}

enum StatutCommande: String, Codable, CaseIterable, Identifiable {
    case brouillon, a_confirmer, confirmee, en_production, prete, livree, soldee, annulee
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .brouillon:     return "Brouillon"
        case .a_confirmer:   return "À confirmer"
        case .confirmee:     return "Confirmée"
        case .en_production: return "En production"
        case .prete:         return "Prête"
        case .livree:        return "Livrée"
        case .soldee:        return "Soldée"
        case .annulee:       return "Annulée"
        }
    }
    var ordre: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum MoyenPaiement: String, Codable, CaseIterable, Identifiable {
    case stripe, especes, virement, autre
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .stripe:   return "Stripe"
        case .especes:  return "Espèces"
        case .virement: return "Virement"
        case .autre:    return "Autre"
        }
    }
}

enum StatutPaiement: String, Codable, CaseIterable, Identifiable {
    case en_attente, reussi, rembourse, echoue
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .en_attente: return "En attente"
        case .reussi:     return "Réussi"
        case .rembourse:  return "Remboursé"
        case .echoue:     return "Échoué"
        }
    }
}

enum TypeMouvement: String, Codable, CaseIterable, Identifiable {
    case entree, sortie, ajustement
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .entree:     return "Entrée"
        case .sortie:     return "Sortie"
        case .ajustement: return "Ajustement"
        }
    }
}

enum StatutReappro: String, Codable, CaseIterable, Identifiable {
    case brouillon, envoye, recu
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .brouillon: return "Brouillon"
        case .envoye:    return "Envoyé"
        case .recu:      return "Reçu"
        }
    }
}

enum StatutEntrante: String, Codable, CaseIterable, Identifiable {
    case a_valider, importee, ignoree
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .a_valider: return "À valider"
        case .importee:  return "Importée"
        case .ignoree:   return "Ignorée"
        }
    }
}
