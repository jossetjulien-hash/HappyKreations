import SwiftUI

@main
struct HappyKreationsApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var store = AppStore()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .hkTheme()
                .task {
                    await auth.restoreSession()
                    await LocalNotificationService.shared.requestAuthorizationIfNeeded()
                    // Push distantes : le jeton APNs n'est utile qu'une fois la
                    // session ouverte, puisqu'on le rattache à l'utilisateur.
                    if auth.isAuthenticated {
                        await PushNotificationService.shared.demanderAutorisationEtEnregistrer()
                    }
                }
                // Couvre le cas d'une connexion après le lancement : sans ça,
                // le jeton ne serait enregistré qu'au prochain démarrage.
                .onChange(of: auth.isAuthenticated) { _, connecte in
                    guard connecte else { return }
                    Task { await PushNotificationService.shared.demanderAutorisationEtEnregistrer() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
