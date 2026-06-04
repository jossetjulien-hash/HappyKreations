import SwiftUI
import AppIntents

// MARK: - Intents disponibles dans Shortcuts iOS / macOS et Siri.
//
// Ces intents permettent d'invoquer l'app via :
// - L'app Raccourcis (Shortcuts) sur iPhone/iPad/Mac
// - Siri : « Hey Siri, combien de commandes aujourd'hui ? »
// - Apple Watch (si l'app y est)
// - Raccourcis de l'écran de verrouillage
//
// Aucune extension target supplémentaire requise : tout vit dans l'app
// principale. La data est lue depuis Supabase avec la clé anon publique.

@available(iOS 17.0, macOS 14.0, *)
struct HappyKreationsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CommandesAujourdhuiIntent(),
            phrases: [
                "Combien de commandes aujourd'hui dans \(.applicationName)",
                "Mes retraits du jour dans \(.applicationName)",
                "\(.applicationName) commandes aujourd'hui",
            ],
            shortTitle: "Retraits du jour",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: ChiffreDAffairesMoisIntent(),
            phrases: [
                "CA du mois dans \(.applicationName)",
                "Chiffre d'affaires de \(.applicationName) ce mois",
            ],
            shortTitle: "CA ce mois",
            systemImageName: "eurosign.circle.fill"
        )
        AppShortcut(
            intent: AlertesStockIntent(),
            phrases: [
                "Alertes de stock dans \(.applicationName)",
                "Matières manquantes dans \(.applicationName)",
            ],
            shortTitle: "Alertes stock",
            systemImageName: "exclamationmark.triangle.fill"
        )
    }
}

// MARK: - Intent : combien de commandes à retirer aujourd'hui

@available(iOS 17.0, macOS 14.0, *)
struct CommandesAujourdhuiIntent: AppIntent {
    static var title: LocalizedStringResource = "Retraits du jour"
    static var description = IntentDescription(
        "Nombre de commandes à retirer aujourd'hui dans l'atelier HappyKreations."
    )
    /// Pour que Siri lise le résultat sans ouvrir l'app.
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = Repository()
        let commandes = try await repo.commandesAVenir(limit: 200)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let aujourdhui = commandes.filter {
            guard let d = $0.date_retrait else { return false }
            return cal.isDate(d, inSameDayAs: today) && $0.statut != .annulee
        }
        let count = aujourdhui.count
        let msg: String
        switch count {
        case 0:  msg = "Aucun retrait prévu aujourd'hui."
        case 1:  msg = "1 commande à retirer aujourd'hui."
        default: msg = "\(count) commandes à retirer aujourd'hui."
        }
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - Intent : CA du mois

@available(iOS 17.0, macOS 14.0, *)
struct ChiffreDAffairesMoisIntent: AppIntent {
    static var title: LocalizedStringResource = "Chiffre d'affaires du mois"
    static var description = IntentDescription(
        "Total facturé sur les commandes du mois en cours (hors annulations)."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = Repository()
        let cal = Calendar.current
        let comp = cal.dateComponents([.year, .month], from: Date())
        let debut = cal.date(from: comp) ?? Date()
        let commandes = try await repo.selectAll(Commande.self, from: "commande",
                                                 orderBy: "date_retrait")
        let ca = commandes
            .filter {
                ($0.date_retrait ?? $0.created_at ?? .distantPast) >= debut
                && $0.statut != .annulee
            }
            .reduce(0.0) { $0 + $1.total }
        let txt = ca.formatted(.currency(code: "EUR").precision(.fractionLength(0...2)))
        let msg = "Chiffre d'affaires du mois : \(txt)."
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - Intent : alertes stock

@available(iOS 17.0, macOS 14.0, *)
struct AlertesStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Alertes de stock"
    static var description = IntentDescription(
        "Matières premières sous leur seuil d'alerte."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = Repository()
        let dispos = try await repo.matieresDisponibles()
        let sous = dispos.filter(\.sous_seuil)
        let msg: String
        switch sous.count {
        case 0:  msg = "Aucune alerte de stock — tout est en ordre."
        case 1:  msg = "1 matière sous seuil : \(sous[0].nom)."
        default:
            let noms = sous.prefix(3).map(\.nom).joined(separator: ", ")
            let suite = sous.count > 3 ? " et \(sous.count - 3) autres" : ""
            msg = "\(sous.count) matières sous seuil : \(noms)\(suite)."
        }
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}
