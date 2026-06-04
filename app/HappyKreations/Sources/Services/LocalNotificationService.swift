import Foundation
import UserNotifications

/// Notifications LOCALES (UserNotifications) déclenchées par le Realtime
/// quand une nouvelle commande arrive ou qu'un acompte Stripe est reçu.
///
/// N'utilise PAS APNs : aucune contrainte Apple Developer Program, fonctionne
/// sur Mac et iPhone via iCloud. La notif apparaît dans le Centre de
/// notifications, badge et son du système.
@MainActor
final class LocalNotificationService {
    static let shared = LocalNotificationService()

    static let enabledKey = "happykreations.notificationsEnabled"

    /// Toggle utilisateur (Réglages). Active par défaut.
    var enabled: Bool {
        get { (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    private init() {}

    /// Demande l'autorisation système si elle n'a pas été décidée.
    /// Renvoie l'état effectif (true = autorisé après la demande).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// État actuel de l'autorisation (utile pour la vue Réglages).
    func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Triggers métier

    /// Nouvelle commande qui vient d'arriver (ex. via le formulaire web).
    func notifyNouvelleCommande(_ c: Commande, clientNom: String?) async {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Nouvelle commande ✿"
        content.body = bodyFor(client: clientNom, montant: c.total,
                               detail: c.canal == .formulaire ? "depuis le formulaire web" : nil)
        content.sound = .default
        await deliver(content, id: "cmd-new-\(c.id)")
    }

    /// Le statut d'une commande est passé à `confirmee` (acompte Stripe reçu).
    func notifyAcompteRecu(_ c: Commande, clientNom: String?) async {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Acompte reçu 🎉"
        content.body = bodyFor(client: clientNom, montant: c.acompte,
                               detail: "commande confirmée")
        content.sound = .default
        await deliver(content, id: "cmd-paid-\(c.id)")
    }

    private func bodyFor(client: String?, montant: Double, detail: String?) -> String {
        let euros = montant.formatted(.currency(code: "EUR").precision(.fractionLength(0...2)))
        var parts: [String] = []
        if let n = client, !n.isEmpty { parts.append(n) }
        parts.append("\(euros)")
        if let d = detail, !d.isEmpty { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    private func deliver(_ content: UNMutableNotificationContent, id: String) async {
        // trigger nil = immédiat
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Silencieux — pas d'autorisation, on n'embête pas l'utilisateur.
        }
    }
}
