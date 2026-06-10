import SwiftUI

/// Liste + édition des zones de livraison configurables (nom, tarif, ordre).
/// Les zones actives sont exposées au formulaire web (RLS publique).
struct ZonesLivraisonView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft: ZoneLivraison?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(store.zonesLivraison) { z in
                    Button {
                        draft = z
                    } label: {
                        ZoneRow(zone: z)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: supprimer)
                if store.zonesLivraison.isEmpty {
                    Text("Aucune zone. Ajoute une zone pour proposer la livraison sur le formulaire.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Les zones marquées « actives » apparaissent sur le formulaire web. Indique « 0 € » pour proposer le retrait sur place.")
            }
        }
        .navigationTitle("Zones de livraison")
        .toolbar {
            ToolbarItem {
                Button {
                    draft = ZoneLivraison.new()
                } label: { Label("Nouvelle zone", systemImage: "plus") }
            }
        }
        .sheet(item: $draft) { z in
            NavigationStack {
                ZoneEditView(initial: z)
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func supprimer(at offsets: IndexSet) {
        let ids = offsets.map { store.zonesLivraison[$0].id }
        Task {
            do {
                for id in ids { try await store.repo.delete("zone_livraison", id: id) }
                await store.loadZonesLivraison()
            } catch { errorText = error.localizedDescription }
        }
    }
}

private struct ZoneRow: View {
    let zone: ZoneLivraison
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: zone.actif ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(zone.actif ? Color.green : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(zone.nom).font(.headline)
                if let d = zone.description, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(zone.tarif, format: .currency(code: "EUR"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(zone.tarif == 0 ? Color.green : .primary)
        }
        .padding(.vertical, 4)
    }
}

struct ZoneEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: ZoneLivraison
    @State private var errorText: String?
    private let isNew: Bool

    init(initial: ZoneLivraison) {
        self._draft = State(initialValue: initial)
        self.isNew = initial.nom.isEmpty
    }

    var body: some View {
        Form {
            Section("Zone") {
                TextField("Nom (ex. « Nord — Saint-Denis »)", text: $draft.nom)
                TextField("Description (facultatif)", text: Binding(
                    get: { draft.description ?? "" },
                    set: { draft.description = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
                    .lineLimit(1...3)
            }
            Section("Tarif") {
                HStack {
                    Text("Frais de livraison")
                    Spacer()
                    TextField("0", value: $draft.tarif, format: .number)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(width: 100)
                    Text("€")
                }
            }
            Section("Affichage") {
                Toggle("Active (visible sur le formulaire)", isOn: $draft.actif)
                Stepper("Ordre : \(draft.ordre) (plus petit = en premier)",
                        value: $draft.ordre, in: 0...100)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouvelle zone" : draft.nom)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { Task { await save() } }
                    .disabled(draft.nom.trimmingCharacters(in: .whitespaces).isEmpty)
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
            _ = try await store.repo.upsert("zone_livraison", draft)
            await store.loadZonesLivraison()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
