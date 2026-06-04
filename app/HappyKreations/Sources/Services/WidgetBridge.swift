import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Pont entre l'app principale et le widget : sérialise un résumé des
/// retraits du jour dans UserDefaults du App Group partagé, puis demande
/// au système de rafraîchir les widgets.
@MainActor
enum WidgetBridge {

    /// Doit être strictement identique côté widget (`WidgetSharedStore.groupId`).
    static let groupId = "group.com.happykreations.app"
    static let dataKey = "widget.today.payload"

    struct WidgetPayload: Codable {
        let updated: Date
        let nbRetraitsAujourdhui: Int
        let prochaines: [Ligne]

        struct Ligne: Codable {
            let id: String
            let clientNom: String
            let total: Double
            let dateRetrait: Date?
        }
    }

    static func push(store: AppStore) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let aujourdhui = store.commandes
            .filter {
                guard let d = $0.date_retrait else { return false }
                return cal.isDate(d, inSameDayAs: today)
                    && $0.statut != .annulee
                    && $0.statut != .soldee
            }
            .sorted { ($0.date_retrait ?? .distantPast) < ($1.date_retrait ?? .distantPast) }

        let prochaines = aujourdhui.prefix(5).map { c -> WidgetPayload.Ligne in
            WidgetPayload.Ligne(
                id: c.id.uuidString,
                clientNom: store.client(id: c.client_id)?.nom ?? "Client",
                total: c.total,
                dateRetrait: c.date_retrait
            )
        }
        let payload = WidgetPayload(
            updated: Date(),
            nbRetraitsAujourdhui: aujourdhui.count,
            prochaines: Array(prochaines)
        )

        guard let defaults = UserDefaults(suiteName: groupId) else {
            // App Group non disponible (entitlement absent) — on log et on
            // continue ; l'app reste fonctionnelle, le widget affichera ses
            // placeholders.
            print("WidgetBridge: App Group \(groupId) introuvable.")
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(payload) {
            defaults.set(data, forKey: dataKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "HappyKreationsWidget")
        #endif
    }
}
