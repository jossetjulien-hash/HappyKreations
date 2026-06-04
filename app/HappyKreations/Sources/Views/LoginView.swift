import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                Text("happykreations")
                    .font(.hkTitle(38, weight: .light))
                    .foregroundStyle(Color.hkInk)
                Text("créations faites main")
                    .font(.hkScript(24))
                    .foregroundStyle(Color.hkSageDeep)
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
