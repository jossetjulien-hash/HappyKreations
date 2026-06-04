import SwiftUI

/// Détail d'un message reçu + 3 actions (convertir / lier / ignorer) + un
/// bouton « Suggérer (IA) » qui apparaît uniquement si Foundation Models est
/// disponible sur l'appareil.
struct InboxDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var entrante: CommandeEntrante
    @State private var commandeEnPreparation: Commande?
    @State private var lienExistant: Commande?
    @State private var pickerLierVisible = false
    @State private var suggestion: AppleIntelligenceExtraction.Suggestion?
    @State private var iaEnCours = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.hkSageDeep.opacity(0.15))
                        Image(systemName: entrante.canal.icone)
                            .foregroundStyle(Color.hkSageDeep)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entrante.canal.libelle).font(.subheadline).bold()
                        Text(entrante.recu_le, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let nom = entrante.expediteur {
                    LabeledContent("Expéditeur", value: nom)
                }
                if let contact = entrante.donnee_extraite?.client?.contact {
                    LabeledContent("Contact", value: contact)
                }
            }

            Section("Message reçu") {
                Text(entrante.message_brut.isEmpty ? "(message vide)" : entrante.message_brut)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if AppleIntelligenceExtraction.isAvailable {
                Section {
                    Button {
                        Task { await suggererAvecIA() }
                    } label: {
                        if iaEnCours {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Extraction en cours…")
                            }
                        } else {
                            Label("Suggérer une commande (IA)", systemImage: "sparkles")
                                .foregroundStyle(Color.hkRoseDeep)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(iaEnCours || entrante.message_brut.isEmpty)
                } footer: {
                    Text("Apple Intelligence analyse le message localement sur ton appareil et propose un brouillon de commande.")
                }
            }

            Section("Actions") {
                Button {
                    convertirEnCommande(prerempliAvecSuggestion: nil)
                } label: {
                    Label("Convertir en commande", systemImage: "arrow.right.circle.fill")
                }
                .disabled(entrante.statut == .importee)
                Button {
                    pickerLierVisible = true
                } label: {
                    Label("Lier à une commande existante", systemImage: "link")
                }
                Button(role: .destructive) {
                    Task { await marquer(.ignoree) }
                } label: {
                    Label("Ignorer", systemImage: "tray.full")
                }
                .disabled(entrante.statut == .ignoree)
            }

            if entrante.statut == .importee, let commandeId = entrante.commande_id,
               let cmd = store.commandes.first(where: { $0.id == commandeId }) {
                Section("Commande créée") {
                    NavigationLink {
                        CommandeEditView(commandeId: cmd.id)
                    } label: {
                        Text(cmd.refCourte + " · " + (store.client(id: cmd.client_id)?.nom ?? "Sans client"))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Message reçu")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { dismiss() }
            }
        }
        .sheet(item: $commandeEnPreparation) { c in
            NavigationStack {
                CommandeEditView(commandeId: c.id, draft: c, isNew: true) { creee in
                    Task { await lier(creee) }
                }
            }
        }
        .sheet(isPresented: $pickerLierVisible) {
            NavigationStack {
                PickerCommandeExistante { c in
                    Task { await lier(c) }
                    pickerLierVisible = false
                } cancel: {
                    pickerLierVisible = false
                }
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func convertirEnCommande(prerempliAvecSuggestion s: AppleIntelligenceExtraction.Suggestion?) {
        var brouillon = Commande.new()
        brouillon.canal = entrante.canal
        // On glisse le message brut au début des notes pour qu'il reste visible
        // une fois la commande créée.
        brouillon.notes = "— Message reçu via \(entrante.canal.libelle) —\n\n\(entrante.message_brut)"

        if let s {
            if let t = s.typeEvenement { brouillon.type_evenement = t }
            brouillon.date_evenement = parseDate(s.dateEvenement) ?? brouillon.date_evenement
            brouillon.date_retrait = parseDate(s.dateRetrait) ?? brouillon.date_retrait
        }
        commandeEnPreparation = brouillon
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    private func suggererAvecIA() async {
        iaEnCours = true
        defer { iaEnCours = false }
        do {
            let s = try await AppleIntelligenceExtraction.suggerer(
                messageBrut: entrante.message_brut,
                produits: store.produits.filter(\.actif)
            )
            suggestion = s
            // On déclenche directement la conversion en pré-remplissant —
            // l'utilisateur ajustera dans CommandeEditView.
            convertirEnCommande(prerempliAvecSuggestion: s)
        } catch { errorText = error.localizedDescription }
    }

    private func marquer(_ statut: StatutEntrante) async {
        entrante.statut = statut
        do {
            _ = try await store.repo.update("commande_entrante", entrante, id: entrante.id)
            await store.loadEntrantes()
            if statut == .ignoree { dismiss() }
        } catch { errorText = error.localizedDescription }
    }

    private func lier(_ commande: Commande) async {
        entrante.commande_id = commande.id
        entrante.statut = .importee
        do {
            _ = try await store.repo.update("commande_entrante", entrante, id: entrante.id)
            await store.loadEntrantes()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}

/// Petit picker des commandes récentes pour l'action « Lier à une commande
/// existante ».
private struct PickerCommandeExistante: View {
    @EnvironmentObject var store: AppStore
    let onPick: (Commande) -> Void
    let cancel: () -> Void

    var body: some View {
        List(store.commandes.prefix(50)) { c in
            Button {
                onPick(c)
            } label: {
                CommandeRow(commande: c)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Lier à…")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", action: cancel)
            }
        }
    }
}
