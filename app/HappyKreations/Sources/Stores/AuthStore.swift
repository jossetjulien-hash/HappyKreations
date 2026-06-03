import Foundation
import SwiftUI
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published var session: Session?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isAuthenticated: Bool { session != nil }
    var userId: UUID? { session?.user.id }
    var userEmail: String? { session?.user.email }

    private let client = SupabaseService.shared.client
    private var authTask: Task<Void, Never>?

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
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
}
