import SwiftUI

@main
struct HappyKreationsApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .hkTheme()
                .task {
                    await auth.restoreSession()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
