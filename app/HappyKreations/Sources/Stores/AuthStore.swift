import Foundation
import SwiftUI
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published var session: Session?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Vrai après une authentification biométrique réussie. Remis à faux quand
    /// l'app passe en background (pour exiger un déverrouillage au retour).
    @Published var isUnlocked: Bool = false

    /// L'utilisateur a activé le verrouillage biométrique dans les Réglages.
    /// Persisté dans UserDefaults.
    @Published var biometricEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricEnabled, forKey: Self.biometricKey) }
    }

    private static let biometricKey = "happykreations.biometricEnabled"

    var isAuthenticated: Bool { session != nil }
    var userId: UUID? { session?.user.id }
    var userEmail: String? { session?.user.email }

    /// La biométrie est requise pour accéder à l'app maintenant.
    var requiresBiometric: Bool {
        isAuthenticated && biometricEnabled && !isUnlocked
    }

    /// Type de biométrie disponible sur l'appareil.
    let biometricKind: BiometricService.Kind = BiometricService.available

    private let client = SupabaseService.shared.client
    private var authTask: Task<Void, Never>?

    init() {
        self.biometricEnabled = UserDefaults.standard.bool(forKey: Self.biometricKey)
        // Si la biométrie n'est pas active, considère l'app déjà déverrouillée.
        self.isUnlocked = !self.biometricEnabled
    }

    func restoreSession() async {
        do {
            let current = try await client.auth.session
            self.session = current
        } catch {
            self.session = nil
        }
        listenToAuthChanges()
    }

    private func listenToAuthChanges() {
        authTask?.cancel()
        authTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.client.auth.authStateChanges {
                await MainActor.run {
                    self.session = change.session
                    // Nouveau login (email+mdp) → on déverrouille immédiatement
                    if change.session != nil { self.isUnlocked = true }
                }
            }
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.auth.signIn(email: email, password: password)
            isUnlocked = true
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
            isUnlocked = !biometricEnabled
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    // MARK: - Biométrie

    func authenticateBiometric() async {
        let reason = "Déverrouiller \(AppConfig.appName)"
        let ok = await BiometricService.authenticate(reason: reason)
        if ok {
            isUnlocked = true
        } else {
            errorMessage = "Authentification refusée."
        }
    }

    /// Active ou désactive le verrouillage. L'activation demande une 1ʳᵉ
    /// validation biométrique (sinon on accepterait un toggle sans preuve).
    func setBiometric(enabled: Bool) async {
        if enabled {
            let ok = await BiometricService.authenticate(
                reason: "Activer le verrouillage de \(AppConfig.appName)"
            )
            if ok {
                biometricEnabled = true
                isUnlocked = true
            } else {
                errorMessage = "Activation annulée."
            }
        } else {
            biometricEnabled = false
            isUnlocked = true
        }
    }

    /// Verrouille l'app (à appeler quand on passe en background).
    func lock() {
        if biometricEnabled { isUnlocked = false }
    }
}
