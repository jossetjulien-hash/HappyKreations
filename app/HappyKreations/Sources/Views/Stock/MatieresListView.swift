import SwiftUI

struct MatieresListView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var nouvelle: Matiere?

    var body: some View {
        List {
            ForEach(filtered) { dispo in
                NavigationLink(destination: MatiereEditView(matiereId: dispo.matiere_id)) {
                    MatiereRow(dispo: dispo)
                }
            }
        }
        .navigationTitle("Stock")
        .searchable(text: $search, prompt: "Rechercher")
        .toolbar {
            ToolbarItem {
                Button {
                    nouvelle = Matiere.new()
                } label: { Label("Nouvelle matière", systemImage: "plus") }
            }
        }
        .sheet(item: $nouvelle) { m in
            NavigationStack {
                MatiereEditView(matiereId: m.id, draft: m, isNew: true)
            }
        }
    }

    private var filtered: [MatiereDisponible] {
        if search.isEmpty { return store.matieresDisponibles }
        return store.matieresDisponibles.filter { $0.nom.lowercased().contains(search.lowercased()) }
    }
}

private struct MatiereRow: View {
    let dispo: MatiereDisponible
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dispo.sous_seuil ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                .foregroundStyle(dispo.sous_seuil ? .orange : .secondary)
            VStack(alignment: .leading) {
                Text(dispo.nom).font(.headline)
                Text("\(format(dispo.disponible)) \(dispo.unite) disponibles · réservé \(format(dispo.reserve))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(format(dispo.stock_actuel)) \(dispo.unite)").font(.subheadline)
        }
    }
    private func format(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct MatiereEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let matiereId: UUID
    @State var draft: Matiere
    var isNew: Bool = false
    @State private var mouvements: [MouvementStock] = []
    @State private var ajustement: Double = 0
    @State private var errorText: String?

    init(matiereId: UUID, draft: Matiere? = nil, isNew: Bool = false) {
        self.matiereId = matiereId
        self._draft = State(initialValue: draft ?? Matiere.new())
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section("Matière") {
                TextField("Nom", text: $draft.nom)
                TextField("Unité (g, kg, ml, pièce…)", text: $draft.unite)
                HStack {
                    Text("Stock actuel")
                    Spacer()
                    TextField("", value: $draft.stock_actuel, format: .number)
                        .multilineTextAlignment(.trailing).frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(draft.unite)
                }
                HStack {
                    Text("Seuil d'alerte")
                    Spacer()
                    TextField("", value: $draft.seuil_alerte, format: .number)
                        .multilineTextAlignment(.trailing).frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(draft.unite)
                }
                HStack {
                    Text("Coût d'achat")
                    Spacer()
                    TextField("", value: Binding(
                        get: { draft.cout_unitaire ?? 0 },
                        set: { draft.cout_unitaire = $0 > 0 ? $0 : nil }),
                        format: .number.precision(.fractionLength(0...4)))
                        .multilineTextAlignment(.trailing).frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("€/\(draft.unite)")
                        .foregroundStyle(.secondary)
                }
            }
            if !isNew {
                Section("Ajustement") {
                    HStack {
                        TextField("Quantité (+/−)", value: $ajustement, format: .number)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                        Button("Appliquer") { Task { await appliquer() } }
                            .disabled(ajustement == 0)
                    }
                }
                Section("Derniers mouvements") {
                    if mouvements.isEmpty {
                        Text("Aucun mouvement").foregroundStyle(.secondary)
                    }
                    ForEach(mouvements) { m in
                        HStack {
                            Image(systemName: m.type == .entree ? "arrow.down" :
                                  (m.type == .sortie ? "arrow.up" : "slider.horizontal.3"))
                                .foregroundStyle(m.type == .entree ? .green :
                                                 (m.type == .sortie ? .red : .blue))
                            VStack(alignment: .leading) {
                                Text(m.type.libelle)
                                Text(m.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(m.quantite.formatted(.number.precision(.fractionLength(0...2)))) \(draft.unite)")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouvelle matière" : draft.nom)
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Créer" : "Enregistrer") { Task { await save() } }
            }
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func load() async {
        if !isNew, let m = store.matieres.first(where: { $0.id == matiereId }) { draft = m }
        if !isNew {
            do { mouvements = try await store.repo.mouvements(matiere: matiereId) }
            catch { errorText = error.localizedDescription }
        }
    }

    private func save() async {
        do {
            if isNew { _ = try await store.repo.insert("matiere", draft) }
            else { _ = try await store.repo.update("matiere", draft, id: draft.id) }
            await store.loadMatieres()
            if isNew { dismiss() }
        } catch { errorText = error.localizedDescription }
    }

    private func appliquer() async {
        let mvt = MouvementStock(id: UUID(), matiere_id: matiereId, date: Date(),
                                 type: ajustement > 0 ? .entree : .sortie,
                                 quantite: abs(ajustement),
                                 origine: "ajustement", commande_id: nil)
        do {
            _ = try await store.repo.insert("mouvement_stock", mvt)
            draft.stock_actuel += ajustement
            _ = try await store.repo.update("matiere", draft, id: draft.id)
            ajustement = 0
            await store.loadMatieres()
            mouvements = try await store.repo.mouvements(matiere: matiereId)
        } catch { errorText = error.localizedDescription }
    }
}
