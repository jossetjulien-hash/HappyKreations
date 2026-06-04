import SwiftUI

/// Gestion des codes promo limités dans le temps.
/// Pattern calqué sur TemoignagesListView (upsert simple, sheet d'édition).
struct CodesPromoView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft: CodePromo?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(store.codesPromo) { c in
                    Button { draft = c } label: {
                        CodePromoRow(code: c)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: supprimer)
                if store.codesPromo.isEmpty {
                    Text("Aucun code promo. Ajoute-en un pour lancer une opération promotionnelle.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Les codes valides apparaissent automatiquement dans le formulaire de commande. Le compteur d'utilisations s'incrémente à chaque application réussie.")
            }
        }
        .navigationTitle("Codes promo")
        .toolbar {
            ToolbarItem {
                Button { draft = CodePromo.new() } label: {
                    Label("Nouveau code", systemImage: "plus")
                }
            }
        }
        .sheet(item: $draft) { c in
            NavigationStack {
                CodePromoEditView(initial: c)
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func supprimer(at offsets: IndexSet) {
        let ids = offsets.map { store.codesPromo[$0].id }
        Task {
            do {
                for id in ids { try await store.repo.delete("code_promo", id: id) }
                await store.loadCodesPromo()
            } catch { errorText = error.localizedDescription }
        }
    }
}

private struct CodePromoRow: View {
    let code: CodePromo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: code.estValideMaintenant ? "tag.fill" : "tag.slash.fill")
                .font(.title3)
                .foregroundStyle(code.estValideMaintenant ? Color.hkSageDeep : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(code.code).font(.headline).monospaced()
                    Text("−" + code.libelleReduction)
                        .font(.subheadline).bold()
                        .foregroundStyle(Color.hkRoseDeep)
                }
                Text("Du \(code.date_debut.formatted(date: .abbreviated, time: .omitted)) au \(code.date_fin.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                if let max = code.max_utilisations {
                    Text("\(code.utilisations) / \(max) utilisations")
                        .font(.caption2)
                        .foregroundStyle(code.utilisations >= max ? .orange : .secondary)
                } else if code.utilisations > 0 {
                    Text("\(code.utilisations) utilisation\(code.utilisations > 1 ? "s" : "")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CodePromoEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CodePromo
    @State private var sansLimite: Bool
    @State private var errorText: String?
    private let isNew: Bool

    init(initial: CodePromo) {
        self._draft = State(initialValue: initial)
        self.isNew = initial.code.isEmpty
        self._sansLimite = State(initialValue: initial.max_utilisations == nil)
    }

    var body: some View {
        Form {
            Section("Code") {
                TextField("FETEMERES2026", text: $draft.code)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    #endif
                TextField("Description (interne)", text: Binding(
                    get: { draft.description ?? "" },
                    set: { draft.description = $0.isEmpty ? nil : $0 }))
            }
            Section("Réduction") {
                Picker("Type", selection: $draft.type) {
                    Text("Pourcentage (%)").tag("pourcent")
                    Text("Montant fixe (€)").tag("fixe")
                }
                HStack {
                    Text("Valeur")
                    Spacer()
                    TextField("", value: $draft.valeur, format: .number)
                        .multilineTextAlignment(.trailing).frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(draft.type == "pourcent" ? "%" : "€")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Validité") {
                DatePicker("Du", selection: $draft.date_debut, displayedComponents: .date)
                DatePicker("Au", selection: $draft.date_fin,
                           in: draft.date_debut..., displayedComponents: .date)
                Toggle("Utilisations illimitées", isOn: $sansLimite)
                if !sansLimite {
                    Stepper("Max : \(draft.max_utilisations ?? 50) utilisations",
                            value: Binding(
                                get: { draft.max_utilisations ?? 50 },
                                set: { draft.max_utilisations = $0 }),
                            in: 1...10000)
                }
                Toggle("Actif", isOn: $draft.actif)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau code promo" : draft.code)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Créer" : "Enregistrer") {
                    Task { await save() }
                }
                .disabled(draft.code.trimmingCharacters(in: .whitespaces).isEmpty || draft.valeur <= 0)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func save() async {
        // Normalise : majuscules + trim + plafonne au cas où le sans-limite
        if sansLimite { draft.max_utilisations = nil }
        draft.code = draft.code.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            _ = try await store.repo.upsert("code_promo", draft)
            await store.loadCodesPromo()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
