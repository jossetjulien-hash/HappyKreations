import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Notifications push distantes (APNs).
///
/// Complète `LocalNotificationService` : les notifications locales ne partent
/// que si l'app tourne (ou est en arrière-plan avec une session Realtime
/// vivante). Les push distantes arrivent même app fermée et appareil en veille.
///
/// Cycle de vie :
///   1. `demanderAutorisation()` — demande l'accord de l'utilisateur.
///   2. Le système renvoie un jeton APNs à `AppDelegate`.
///   3. `enregistrer(token:)` le range dans la table `appareil` de Supabase.
///   4. L'Edge Function `envoyer-push` lit cette table pour diffuser.
@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    /// Vrai une fois le jeton APNs reçu et enregistré côté serveur.
    @Published private(set) var enregistre = false
    @Published private(set) var derniereErreur: String?

    private override init() { super.init() }

    /// `development` en build Xcode local, `production` en TestFlight/App Store.
    /// Détermine le serveur APNs que l'Edge Function doit contacter — les deux
    /// environnements ont des jetons incompatibles entre eux.
    private var environnement: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private var plateforme: String {
        #if os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }

    /// Demande l'autorisation puis, si accordée, s'inscrit auprès d'APNs.
    /// Sans accord, on ne s'inscrit pas : inutile de générer un jeton qui ne
    /// servira à rien.
    func demanderAutorisationEtEnregistrer() async {
        let centre = UNUserNotificationCenter.current()
        do {
            let accorde = try await centre.requestAuthorization(options: [.alert, .badge, .sound])
            guard accorde else { return }
        } catch {
            derniereErreur = error.localizedDescription
            return
        }
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Appelée par l'AppDelegate quand APNs renvoie le jeton de l'appareil.
    func enregistrer(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        do {
            try await SupabaseService.shared.client
                .from("appareil")
                .upsert([
                    "user_id": SupabaseService.shared.client.auth.currentUser?.id.uuidString ?? "",
                    "device_token": token,
                    "plateforme": plateforme,
                    "environnement": environnement,
                    "modele": modeleAppareil,
                    "actif": "true",
                    "derniere_maj": ISO8601DateFormatter().string(from: Date()),
                ], onConflict: "device_token")
                .execute()
            enregistre = true
            derniereErreur = nil
        } catch {
            derniereErreur = "Enregistrement du jeton push : \(error.localizedDescription)"
        }
    }

    func echecEnregistrement(_ error: Error) {
        derniereErreur = "APNs : \(error.localizedDescription)"
    }

    private var modeleAppareil: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

/// Reçoit les rappels APNs du système. Branché via `@UIApplicationDelegateAdaptor`
/// (iOS) / `@NSApplicationDelegateAdaptor` (macOS) dans HappyKreationsApp.
#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushNotificationService.shared.enregistrer(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotificationService.shared.echecEnregistrement(error) }
    }
}
#elseif os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushNotificationService.shared.enregistrer(deviceToken: deviceToken) }
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotificationService.shared.echecEnregistrement(error) }
    }
}
#endif
