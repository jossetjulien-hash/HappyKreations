import SwiftUI

struct CommandeEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let commandeId: UUID
    @State var draft: Commande
    var isNew: Bool = false

    @State private var lignes: [CommandeLigne] = []
    @State private var paiements: [Paiement] = []
    @State private var isLoading = false
    @State private var errorText: String?

    init(commandeId: UUID, draft: Commande? = nil, isNew: Bool = false) {
        self.commandeId = commandeId
        self._draft = State(initialValue: draft ?? Commande.new())
        self.isNew = isNew
    }

    /// Allergènes courants pour les chocolats & meringues (cases à cocher).
    private static let allergenesCourants = [
        "Gluten", "Lait", "Œuf", "Fruits à coque", "Arachide", "Soja", "Sésame",
    ]

    var body: some View {
        Form {
            sectionInfos
            sectionPersonnalisation
            sectionLignes
            sectionTotaux
            sectionPaiements
            sectionStatut
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouvelle commande" : "Commande")
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Créer" : "Enregistrer") { Task { await save() } }
                    .disabled(isLoading)
            }
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .overlay { if isLoading { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) } }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private var sectionInfos: some View {
        Section("Informations") {
            Picker("Client", selection: $draft.client_id) {
                Text("— Aucun —").tag(UUID?.none)
                ForEach(store.clients) { c in
                    Text(c.nom).tag(Optional(c.id))
                }
            }
            TextField("Type d'événement", text: optional($draft.type_evenement))
            DatePicker("Date événement",
                       selection: bindingDate($draft.date_evenement),
                       displayedComponents: .date)
            DatePicker("Date de retrait",
                       selection: bindingDate($draft.date_retrait),
                       displayedComponents: .date)
            Picker("Canal", selection: $draft.canal) {
                ForEach(CanalCommande.allCases) { Text($0.libelle).tag($0) }
            }
        }
    }

    private var sectionPersonnalisation: some View {
        Section("Personnalisation") {
            DisclosureGroup("Allergies\(draft.allergies.isEmpty ? "" : " (\(draft.allergies.count))")") {
                ForEach(Self.allergenesCourants, id: \.self) { a in
                    Toggle(a, isOn: Binding(
                        get: { draft.allergies.contains(a) },
                        set: { on in
                            if on { if !draft.allergies.contains(a) { draft.allergies.append(a) } }
                            else { draft.allergies.removeAll { $0 == a } }
                        }))
                }
            }
            TextField("Message à graver", text: optional($draft.message_gravure))
            TextField("Couleur souhaitée", text: optional($draft.couleur))
            TextField("Notes libres", text: optional($draft.notes), axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var sectionLignes: some View {
        Section("Lignes") {
            ForEach($lignes) { $ligne in
                LigneRow(ligne: $ligne)
            }
            .onDelete { idx in
                lignes.remove(atOffsets: idx)
            }
            Button {
                if let first = store.produits.first {
                    lignes.append(CommandeLigne(id: UUID(), commande_id: commandeId,
                                                produit_id: first.id, quantite: 1,
                                                prix_unitaire: first.prix_vente, declinaison: nil))
                }
            } label: {
                Label("Ajouter une ligne", systemImage: "plus")
            }
        }
    }

    private var sectionTotaux: some View {
        Section("Totaux") {
            HStack { Text("Total"); Spacer()
                Text(totalCalcule, format: .currency(code: "EUR")).bold()
            }
            HStack { Text("Acompte"); Spacer()
                Text(acompte, format: .currency(code: "EUR")).foregroundStyle(.secondary)
            }
            HStack { Text("Encaissé"); Spacer()
                Text(encaisse, format: .currency(code: "EUR")).foregroundStyle(.green)
            }
            HStack { Text("Reste dû"); Spacer()
                Text(resteDu, format: .currency(code: "EUR")).foregroundStyle(.red)
            }
        }
    }

    private var sectionPaiements: some View {
        Section("Paiements") {
            if paiements.isEmpty {
                Text("Aucun paiement").foregroundStyle(.secondary)
            }
            ForEach(paiements) { p in
                HStack {
                    VStack(alignment: .leading) {
                        Text(p.moyen.libelle).font(.subheadline)
                        Text(p.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(p.montant, format: .currency(code: "EUR"))
                }
            }
            Button {
                Task { await ajouterPaiementSolde() }
            } label: {
                Label("Encaisser le solde", systemImage: "creditcard")
            }
            .disabled(resteDu <= 0 || isNew)
        }
    }

    private var sectionStatut: some View {
        Section("Statut") {
            Picker("Statut", selection: $draft.statut) {
                ForEach(StatutCommande.allCases) { Text($0.libelle).tag($0) }
            }
            if !isNew {
                Button(role: .destructive) {
                    Task { await supprimer() }
                } label: {
                    Label("Supprimer la commande", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Calculs

    private var totalCalcule: Double {
        lignes.reduce(0) { $0 + Double($1.quantite) * $1.prix_unitaire }
    }
    private var acompte: Double {
        totalCalcule * store.acomptePourcent / 100
    }
    private var encaisse: Double {
        paiements.filter { $0.statut == .reussi }.reduce(0) { $0 + $1.montant }
    }
    private var resteDu: Double { max(0, totalCalcule - encaisse) }

    // MARK: - Persistance

    private func load() async {
        guard !isNew else { return }
        if let c = store.commandes.first(where: { $0.id == commandeId }) {
            draft = c
        }
        do {
            lignes = try await store.repo.lignes(forCommande: commandeId)
            paiements = try await store.repo.paiements(forCommande: commandeId)
        } catch { errorText = error.localizedDescription }
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        var d = draft
        d.acompte = acompte
        d.total = totalCalcule
        d.updated_at = Date()
        do {
            if isNew {
                let inserted: Commande = try await store.repo.insert("commande", d)
                for var l in lignes {
                    l.commande_id = inserted.id
                    _ = try await store.repo.insert("commande_ligne", l)
                }
            } else {
                _ = try await store.repo.update("commande", d, id: d.id)
                let serverLignes = try await store.repo.lignes(forCommande: d.id)
                for l in serverLignes where !lignes.contains(where: { $0.id == l.id }) {
                    try await store.repo.delete("commande_ligne", id: l.id)
                }
                for l in lignes {
                    _ = try await store.repo.upsert("commande_ligne", l)
                }
            }
            await store.loadCommandes()
            if isNew { dismiss() }
        } catch { errorText = error.localizedDescription }
    }

    private func ajouterPaiementSolde() async {
        let p = Paiement(id: UUID(), commande_id: commandeId, date: Date(),
                         montant: resteDu, moyen: .especes,
                         stripe_session_id: nil, stripe_payment_intent: nil,
                         statut: .reussi)
        do {
            _ = try await store.repo.insert("paiement", p)
            paiements = try await store.repo.paiements(forCommande: commandeId)
        } catch { errorText = error.localizedDescription }
    }

    private func supprimer() async {
        do {
            try await store.repo.delete("commande", id: commandeId)
            await store.loadCommandes()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }

    // MARK: - Helpers liaison optionnel

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" },
                set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
    private func bindingDate(_ binding: Binding<Date?>) -> Binding<Date> {
        Binding(get: { binding.wrappedValue ?? Date() },
                set: { binding.wrappedValue = $0 })
    }
}

private struct LigneRow: View {
    @EnvironmentObject var store: AppStore
    @Binding var ligne: CommandeLigne

    var body: some View {
        VStack(spacing: 6) {
            Picker("Produit", selection: $ligne.produit_id) {
                ForEach(store.produits) { p in
                    Text(p.nom).tag(p.id)
                }
            }
            .onChange(of: ligne.produit_id) { _, new in
                if let p = store.produit(id: new) { ligne.prix_unitaire = p.prix_vente }
            }
            HStack {
                Stepper("Quantité : \(ligne.quantite)", value: $ligne.quantite, in: 1...999)
            }
            HStack {
                Text("Prix unit.")
                Spacer()
                TextField("", value: $ligne.prix_unitaire, format: .number)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(width: 100)
                Text("€")
            }
            if let p = store.produit(id: ligne.produit_id), !p.declinaisons.isEmpty {
                Picker("Déclinaison", selection: Binding(
                    get: { ligne.declinaison ?? "" },
                    set: { ligne.declinaison = $0.isEmpty ? nil : $0 }
                )) {
                    Text("—").tag("")
                    ForEach(p.declinaisons, id: \.self) { d in Text(d).tag(d) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
