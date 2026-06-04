import SwiftUI

/// Sheet de saisie d'un nouveau message reçu (ou édition d'un message
/// existant). Permet de coller en quelques tapotements le texte d'un DM
/// Marketplace / Instagram / WhatsApp / SMS / email.
struct InboxEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var entrante: CommandeEntrante
    @State private var expediteurNom: String
    @State private var expediteurContact: String
    @State private var errorText: String?

    init(entrante: CommandeEntrante) {
        self._entrante = State(initialValue: entrante)
        let info = entrante.donnee_extraite?.client
        self._expediteurNom = State(initialValue: info?.nom ?? "")
        self._expediteurContact = State(initialValue: info?.contact ?? "")
    }

    private var isNew: Bool {
        !store.commandesEntrantes.contains(where: { $0.id == entrante.id })
    }

    var body: some View {
        Form {
            Section("Canal") {
                Picker("Source", selection: $entrante.canal) {
                    ForEach(canauxMessagerie) { c in
                        Label(c.libelle, systemImage: c.icone).tag(c)
                    }
                }
                DatePicker("Reçu le", selection: $entrante.recu_le)
            }
            Section("Expéditeur") {
                TextField("Nom (Camille L., @sophie_paris…)", text: $expediteurNom)
                TextField("Téléphone / email / handle", text: $expediteurContact)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
            Section("Message brut") {
                TextField("Colle ici le message reçu…", text: $entrante.message_brut,
                          axis: .vertical)
                    .lineLimit(6...20)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau message" : "Modifier")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Enregistrer" : "Mettre à jour") {
                    Task { await sauver() }
                }
                .disabled(entrante.message_brut.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    /// Canaux pertinents pour la saisie d'un message reçu (on cache .formulaire
    /// et .manuel qui sont des canaux internes).
    private var canauxMessagerie: [CanalCommande] {
        [.marketplace, .instagram, .whatsapp, .sms, .messenger, .email, .manuel]
    }

    private func sauver() async {
        // Inject les infos expéditeur dans donnee_extraite pour qu'elles
        // soient visibles dans la liste sans coder un nouveau champ BDD.
        var payload = entrante.donnee_extraite ?? ExtractionPayload()
        var client = payload.client ?? ExtractionPayload.ClientInfo()
        client.nom = expediteurNom.isEmpty ? nil : expediteurNom
        client.contact = expediteurContact.isEmpty ? nil : expediteurContact
        payload.client = (client.nom == nil && client.contact == nil) ? nil : client
        entrante.donnee_extraite = (payload.client == nil) ? nil : payload

        do {
            _ = try await store.repo.upsert("commande_entrante", entrante)
            await store.loadEntrantes()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
