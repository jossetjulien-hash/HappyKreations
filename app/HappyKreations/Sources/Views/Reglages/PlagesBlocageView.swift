import SwiftUI

/// Plages pendant lesquelles aucun retrait n'est possible (vacances, fermetures
/// exceptionnelles). Affichées au client sur le formulaire avec un message
/// personnalisable.
struct PlagesBlocageView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft: PlageBlocage?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(store.plagesBlocage) { p in
                    Button { draft = p } label: { PlageRow(plage: p) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: supprimer)
                if store.plagesBlocage.isEmpty {
                    Text("Aucune plage. Ajoute une période pour bloquer les commandes (congés, fermeture…).")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Les plages actives empêchent les clients de choisir un retrait sur ces jours. Le message renseigné s'affiche en bannière sur le formulaire pendant la période.")
            }
        }
        .navigationTitle("Plages bloquées")
        .toolbar {
            ToolbarItem {
                Button { draft = PlageBlocage.new() } label: {
                    Label("Nouvelle plage", systemImage: "plus")
                }
            }
        }
        .sheet(item: $draft) { p in
            NavigationStack { PlageEditView(initial: p) }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func supprimer(at offsets: IndexSet) {
        let ids = offsets.map { store.plagesBlocage[$0].id }
        Task {
            do {
                for id in ids { try await store.repo.delete("plage_blocage", id: id) }
                await store.loadPlagesBlocage()
            } catch { errorText = error.localizedDescription }
        }
    }
}

private struct PlageRow: View {
    let plage: PlageBlocage
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: plage.actif ? "calendar.badge.exclamationmark" : "calendar")
                .foregroundStyle(plage.actif ? Color.hkRoseDeep : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(plage.libelle.isEmpty ? "(Sans libellé)" : plage.libelle).font(.headline)
                Text("Du \(plage.date_debut.formatted(date: .abbreviated, time: .omitted))") +
                Text(" au ") +
                Text(plage.date_fin.formatted(date: .abbreviated, time: .omitted))
                if let m = plage.message_client, !m.isEmpty {
                    Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct PlageEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: PlageBlocage
    @State private var errorText: String?
    /// Dernier message auto-généré : sert à détecter si le user a customisé le
    /// message (auquel cas on arrête de le réécrire automatiquement).
    @State private var messageAutoPrecedent: String = ""
    private let isNew: Bool

    init(initial: PlageBlocage) {
        self._draft = State(initialValue: initial)
        self.isNew = initial.libelle.isEmpty
    }

    var body: some View {
        Form {
            Section("Libellé") {
                TextField("Ex. Congés d'été", text: $draft.libelle)
            }
            Section("Période") {
                DatePicker("Du", selection: $draft.date_debut, displayedComponents: .date)
                DatePicker("Au", selection: $draft.date_fin,
                           in: draft.date_debut...,
                           displayedComponents: .date)
            }
            Section {
                TextField("Message client",
                          text: Binding(
                            get: { draft.message_client ?? "" },
                            set: { draft.message_client = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
                    .lineLimit(3...6)
                Button {
                    let msg = messageAuto(debut: draft.date_debut, fin: draft.date_fin)
                    draft.message_client = msg
                    messageAutoPrecedent = msg
                } label: {
                    Label("Régénérer depuis les dates", systemImage: "wand.and.stars")
                        .font(.caption)
                }
            } header: {
                Text("Message au client")
            } footer: {
                Text("Pré-rempli automatiquement à partir des dates. Tu peux le personnaliser ; il restera ta version. Laisser vide = pas de bannière (seules les dates sont grisées).")
            }
            Section {
                Toggle("Plage active", isOn: $draft.actif)
            } footer: {
                Text("Désactive temporairement la plage sans la supprimer.")
            }
        }
        .onAppear {
            let msg = messageAuto(debut: draft.date_debut, fin: draft.date_fin)
            if (draft.message_client ?? "").isEmpty {
                draft.message_client = msg
            }
            messageAutoPrecedent = msg
        }
        .onChange(of: draft.date_debut) { _, _ in regenererSiAuto() }
        .onChange(of: draft.date_fin) { _, _ in regenererSiAuto() }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouvelle plage" : draft.libelle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { Task { await save() } }
                    .disabled(draft.libelle.trimmingCharacters(in: .whitespaces).isEmpty)
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
        do {
            _ = try await store.repo.upsert("plage_blocage", draft)
            await store.loadPlagesBlocage()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }

    /// Génère un message naturel en français à partir des dates de la plage.
    /// Ex. « Je suis en congé du 10 au 17 juin, reprise des commandes le
    /// 18 juin ✿ ». Si le mois change, on précise le mois de chaque date.
    private func messageAuto(debut: Date, fin: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let fmtLong = DateFormatter()
        fmtLong.locale = Locale(identifier: "fr_FR")
        fmtLong.dateFormat = "d MMMM"
        let fmtJour = DateFormatter()
        fmtJour.locale = Locale(identifier: "fr_FR")
        fmtJour.dateFormat = "d"

        let reprise = cal.date(byAdding: .day, value: 1, to: fin) ?? fin
        let memeMois = cal.component(.month, from: debut) == cal.component(.month, from: fin)
                    && cal.component(.year, from: debut) == cal.component(.year, from: fin)
        let periode = memeMois
            ? "du \(fmtJour.string(from: debut)) au \(fmtLong.string(from: fin))"
            : "du \(fmtLong.string(from: debut)) au \(fmtLong.string(from: fin))"
        let dateReprise = fmtLong.string(from: reprise)
        return "Je suis en congé \(periode), reprise des commandes le \(dateReprise) ✿"
    }

    /// Régénère le message si le user ne l'a pas customisé (= il est resté
    /// identique au dernier auto-généré).
    private func regenererSiAuto() {
        let nouveau = messageAuto(debut: draft.date_debut, fin: draft.date_fin)
        let actuel = draft.message_client ?? ""
        if actuel.isEmpty || actuel == messageAutoPrecedent {
            draft.message_client = nouveau
        }
        messageAutoPrecedent = nouveau
    }
}
