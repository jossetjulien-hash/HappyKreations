import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extraction LOCALE des informations de commande depuis un message brut,
/// via Apple Intelligence (Foundation Models, iOS 26 / macOS 26+).
///
/// Tout est exécuté sur l'appareil — gratuit, privé, instantané — mais ne
/// fonctionne que sur Apple Silicon récent + iOS 26+ / macOS 26+. Sur les
/// appareils non compatibles, `isAvailable` renvoie `false` et le bouton
/// « Suggérer (IA) » est masqué côté UI.
enum AppleIntelligenceExtraction {

    /// `true` si Foundation Models est compilable ET que le modèle système est
    /// utilisable sur cet appareil. Vérifié à chaque appel — pas de cache.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        }
        return false
        #else
        return false
        #endif
    }

    /// Erreur exposée à l'UI quand l'IA n'est pas dispo ou échoue.
    enum Erreur: LocalizedError {
        case nonDisponible
        case generationEchouee(String)
        var errorDescription: String? {
            switch self {
            case .nonDisponible: return "Apple Intelligence n'est pas disponible sur cet appareil."
            case .generationEchouee(let m): return "L'IA n'a pas pu extraire la commande : \(m)"
            }
        }
    }

    /// Suggestion plate, indépendante de Foundation Models, exposée à l'UI.
    /// On ne renvoie pas le `@Generable` directement pour ne pas contaminer le
    /// reste du code avec la contrainte `@available(iOS 26)`.
    struct Suggestion: Hashable {
        var clientNom: String?
        var clientTelephone: String?
        var clientEmail: String?
        var dateEvenement: String?     // AAAA-MM-JJ
        var dateRetrait: String?       // AAAA-MM-JJ
        var typeEvenement: String?
        var lignes: [Ligne]
        var confiance: Double

        struct Ligne: Hashable, Identifiable {
            let id = UUID()
            var produitId: UUID?       // mappé après coup vers le catalogue
            var produitTexte: String   // tel qu'écrit dans le message
            var quantite: Int
            var declinaison: String?
        }
    }

    /// Génère une suggestion de commande à partir d'un message brut, en
    /// donnant au modèle le catalogue des produits visibles pour qu'il puisse
    /// mapper « 12 chocolats noirs » → un produit_id réel.
    static func suggerer(messageBrut: String, produits: [Produit]) async throws -> Suggestion {
        guard isAvailable else { throw Erreur.nonDisponible }
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            return try await GenerationImpl.run(message: messageBrut, produits: produits)
        }
        throw Erreur.nonDisponible
        #else
        throw Erreur.nonDisponible
        #endif
    }
}

// MARK: - Implémentation @available cloisonnée

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
private enum GenerationImpl {

    @Generable
    struct SuggestionCommandeGen {
        @Guide(description: "Nom du client (prénom, surnom, @handle…)")
        var clientNom: String?
        @Guide(description: "Téléphone du client si mentionné")
        var clientTelephone: String?
        @Guide(description: "Email du client si mentionné")
        var clientEmail: String?
        @Guide(description: "Date de l'événement au format AAAA-MM-JJ")
        var dateEvenement: String?
        @Guide(description: "Date de retrait souhaitée au format AAAA-MM-JJ")
        var dateRetrait: String?
        @Guide(description: "Type d'événement : mariage / baptême / anniversaire / communion / autre")
        var typeEvenement: String?
        @Guide(description: "Lignes produit demandées dans le message")
        var lignes: [LigneGen]
        @Guide(description: "Niveau de confiance globale entre 0 et 1")
        var confiance: Double
    }

    @Generable
    struct LigneGen {
        @Guide(description: "UUID du produit du catalogue (recopie depuis la liste fournie), ou null si non identifié")
        var produitId: String?
        @Guide(description: "Le nom du produit tel qu'écrit dans le message")
        var produitTexte: String
        @Guide(description: "Quantité demandée (nombre entier ≥ 1)")
        var quantite: Int
        @Guide(description: "Déclinaison demandée (ex. chocolat noir, lait, blanc), ou null")
        var declinaison: String?
    }

    static func run(message: String, produits: [Produit]) async throws
        -> AppleIntelligenceExtraction.Suggestion
    {
        let catalogue = produits.map { p -> String in
            let decli = p.declinaisons.joined(separator: ", ")
            let suffix = decli.isEmpty ? "" : " (déclinaisons : \(decli))"
            return "- \(p.id.uuidString) | \(p.nom)\(suffix)"
        }.joined(separator: "\n")

        let instructions = """
        Tu es l'assistante de l'artisane HappyKreations (coffrets de chocolats et \
        cornets de meringues sur mesure pour des événements). On te donne un \
        message brut d'un·e client·e potentiel·le et le catalogue des produits \
        disponibles. Extrais une suggestion de commande structurée.

        Règles importantes :
        - Les dates doivent être au format AAAA-MM-JJ. Si seule la date \
        d'événement est connue, propose une date de retrait 2 jours avant.
        - Mappe chaque ligne demandée au produit du catalogue le plus proche \
        (renvoie l'UUID), ou laisse produitId à null si rien ne correspond.
        - Indique un niveau de confiance honnête entre 0 et 1.
        - Tout doit être en français.

        Catalogue disponible :
        \(catalogue)
        """

        let session = LanguageModelSession(instructions: instructions)
        let response: LanguageModelSession.Response<SuggestionCommandeGen>
        do {
            response = try await session.respond(
                to: "Message reçu :\n\n\(message)",
                generating: SuggestionCommandeGen.self
            )
        } catch {
            throw AppleIntelligenceExtraction.Erreur.generationEchouee(
                error.localizedDescription)
        }

        let gen = response.content
        return AppleIntelligenceExtraction.Suggestion(
            clientNom: gen.clientNom,
            clientTelephone: gen.clientTelephone,
            clientEmail: gen.clientEmail,
            dateEvenement: gen.dateEvenement,
            dateRetrait: gen.dateRetrait,
            typeEvenement: gen.typeEvenement,
            lignes: gen.lignes.map { l in
                AppleIntelligenceExtraction.Suggestion.Ligne(
                    produitId: l.produitId.flatMap(UUID.init(uuidString:)),
                    produitTexte: l.produitTexte,
                    quantite: max(1, l.quantite),
                    declinaison: l.declinaison
                )
            },
            confiance: gen.confiance
        )
    }
}
#endif
