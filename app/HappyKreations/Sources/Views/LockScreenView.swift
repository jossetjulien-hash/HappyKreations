import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: auth.biometricKind.icon)
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(AppConfig.appName).font(.title).bold()
                if let email = auth.userEmail {
                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Application verrouillée")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task { await auth.authenticateBiometric() }
                } label: {
                    Label("Déverrouiller avec \(auth.biometricKind.libelle)",
                          systemImage: auth.biometricKind.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Text("Se déconnecter").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 360)
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Propose la biométrie automatiquement à l'apparition
            await auth.authenticateBiometric()
        }
    }
}
