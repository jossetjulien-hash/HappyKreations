import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "birthday.cake")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(AppConfig.appName)
                    .font(.largeTitle).bold()
                Text("Chocolats & meringues — gestion")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                SecureField("Mot de passe", text: $password)
                    .textFieldStyle(.roundedBorder)
                if let err = auth.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await auth.signIn(email: email, password: password) }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Text("Se connecter").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(email.isEmpty || password.isEmpty || auth.isLoading)
            }
            .frame(maxWidth: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
