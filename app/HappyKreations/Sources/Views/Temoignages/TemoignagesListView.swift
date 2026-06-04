import SwiftUI

/// Gestion des témoignages clients affichés sur la page d'accueil du site.
struct TemoignagesListView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft: Temoignage?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(store.temoignages) { t in
                    Button {
                        draft = t
                    } label: {
                        TemoignageRow(temoignage: t)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: supprimer)
                if store.temoignages.isEmpty {
                    Text("Aucun témoignage. Ajoutez-en un pour qu'il apparaisse sur le site.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Les témoignages marqués « visibles » apparaissent sur la page d'accueil du site. Glissez pour supprimer.")
            }
        }
        .navigationTitle("Témoignages")
        .toolbar {
            ToolbarItem {
                Button {
                    draft = Temoignage.new()
                } label: { Label("Nouveau témoignage", systemImage: "plus") }
            }
        }
        .sheet(item: $draft) { t in
            NavigationStack {
                TemoignageEditView(initial: t)
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func supprimer(at offsets: IndexSet) {
        let ids = offsets.map { store.temoignages[$0].id }
        Task {
            do {
                for id in ids { try await store.repo.delete("temoignage", id: id) }
                await store.loadTemoignages()
            } catch { errorText = error.localizedDescription }
        }
    }
}

private struct TemoignageRow: View {
    let temoignage: Temoignage
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: temoignage.visible ? "eye" : "eye.slash")
                .foregroundStyle(temoignage.visible ? Color.hkSageDeep : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(temoignage.auteur).font(.headline)
                    if let e = temoignage.evenement, !e.isEmpty {
                        Text("· \(e)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(temoignage.texte)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TemoignageEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: Temoignage
    @State private var errorText: String?
    private let isNew: Bool

    init(initial: Temoignage) {
        self._draft = State(initialValue: initial)
        self.isNew = !initial.auteur.isEmpty == false && initial.texte.isEmpty
    }

    var body: some View {
        Form {
            Section("Auteur") {
                TextField("Prénom ou « Camille & Léa »", text: $draft.auteur)
                TextField("Type d'événement (facultatif)", text: Binding(
                    get: { draft.evenement ?? "" },
                    set: { draft.evenement = $0.isEmpty ? nil : $0 }))
            }
            Section("Témoignage") {
                TextField("Texte", text: $draft.texte, axis: .vertical)
                    .lineLimit(4...12)
            }
            Section("Affichage") {
                Toggle("Visible sur le site", isOn: $draft.visible)
                Stepper("Ordre : \(draft.ordre) (plus petit = en premier)",
                        value: $draft.ordre, in: -100...100)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau témoignage" : draft.auteur)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { Task { await save() } }
                    .disabled(draft.auteur.isEmpty || draft.texte.isEmpty)
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
            _ = try await store.repo.upsert("temoignage", draft)
            await store.loadTemoignages()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
