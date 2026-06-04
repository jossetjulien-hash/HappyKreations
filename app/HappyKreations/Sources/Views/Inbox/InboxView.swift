import SwiftUI

/// Boîte de réception centralisée : messages reçus par Marketplace, Instagram,
/// WhatsApp, SMS, email, formulaire. Permet de convertir un message en
/// commande pré-remplie en un clic, sans rien perdre dans le flot des DM.
struct InboxView: View {
    @EnvironmentObject var store: AppStore
    @State private var filtre: Filtre = .a_valider
    @State private var draft: CommandeEntrante?
    @State private var detail: CommandeEntrante?
    @State private var errorText: String?

    enum Filtre: String, CaseIterable, Identifiable {
        case a_valider, importee, ignoree, tous
        var id: String { rawValue }
        var libelle: String {
            switch self {
            case .a_valider: return "À valider"
            case .importee:  return "Importées"
            case .ignoree:   return "Ignorées"
            case .tous:      return "Tous"
            }
        }
        func matches(_ e: CommandeEntrante) -> Bool {
            switch self {
            case .a_valider: return e.statut == .a_valider
            case .importee:  return e.statut == .importee
            case .ignoree:   return e.statut == .ignoree
            case .tous:      return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filtre", selection: $filtre) {
                ForEach(Filtre.allCases) { f in
                    Text(libelleAvecCompteur(f)).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                if filtreesAffichees.isEmpty {
                    ContentUnavailableView(
                        videLibelle,
                        systemImage: "tray",
                        description: Text("Tape sur + pour ajouter un message reçu sur Marketplace, Instagram, WhatsApp, SMS…")
                    )
                } else {
                    ForEach(filtreesAffichees) { e in
                        Button { detail = e } label: {
                            InboxRow(entrante: e)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if e.statut != .ignoree {
                                Button(role: .destructive) {
                                    Task { await marquerStatut(e, statut: .ignoree) }
                                } label: {
                                    Label("Ignorer", systemImage: "tray.full")
                                }
                            }
                            if e.statut != .a_valider {
                                Button {
                                    Task { await marquerStatut(e, statut: .a_valider) }
                                } label: {
                                    Label("À valider", systemImage: "tray.and.arrow.down")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Boîte de réception")
        .toolbar {
            ToolbarItem {
                Button {
                    draft = CommandeEntrante.new()
                } label: { Label("Nouveau message", systemImage: "plus") }
            }
        }
        .sheet(item: $draft) { e in
            NavigationStack {
                InboxEditView(entrante: e)
            }
        }
        .sheet(item: $detail) { e in
            NavigationStack {
                InboxDetailView(entrante: e)
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private var filtreesAffichees: [CommandeEntrante] {
        store.commandesEntrantes.filter { filtre.matches($0) }
    }

    private var videLibelle: String {
        switch filtre {
        case .a_valider: return "Aucun message à valider"
        case .importee:  return "Aucun message déjà importé"
        case .ignoree:   return "Aucun message ignoré"
        case .tous:      return "Boîte de réception vide"
        }
    }

    private func libelleAvecCompteur(_ f: Filtre) -> String {
        let n = store.commandesEntrantes.filter { f.matches($0) }.count
        return n > 0 ? "\(f.libelle) · \(n)" : f.libelle
    }

    private func marquerStatut(_ e: CommandeEntrante, statut: StatutEntrante) async {
        var copy = e
        copy.statut = statut
        do {
            _ = try await store.repo.update("commande_entrante", copy, id: e.id)
            await store.loadEntrantes()
        } catch { errorText = error.localizedDescription }
    }
}

/// Ligne de la Boîte de réception : icône colorée du canal + expéditeur +
/// preview du message + date relative + badge de statut.
private struct InboxRow: View {
    let entrante: CommandeEntrante

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(canalTint(entrante.canal).gradient)
                Image(systemName: entrante.canal.icone)
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entrante.expediteur ?? entrante.canal.libelle)
                        .font(.subheadline).bold()
                    Spacer(minLength: 8)
                    Text(entrante.recu_le, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entrante.apercu.isEmpty ? "(message vide)" : entrante.apercu)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                StatutPastille(statut: entrante.statut)
            }
        }
        .padding(.vertical, 4)
    }

    private func canalTint(_ c: CanalCommande) -> Color {
        switch c {
        case .marketplace: return .blue
        case .instagram:   return .pink
        case .whatsapp:    return .green
        case .sms:         return Color.hkSageDeep
        case .messenger:   return .indigo
        case .email:       return Color.hkInk
        case .formulaire:  return .teal
        case .manuel:      return .gray
        }
    }
}

private struct StatutPastille: View {
    let statut: StatutEntrante
    var body: some View {
        Text(statut.libelle.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
    private var tint: Color {
        switch statut {
        case .a_valider: return .orange
        case .importee:  return .green
        case .ignoree:   return .gray
        }
    }
}
