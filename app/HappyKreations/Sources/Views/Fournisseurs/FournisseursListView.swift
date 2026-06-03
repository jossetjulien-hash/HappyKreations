import SwiftUI

struct FournisseursListView: View {
    @EnvironmentObject var store: AppStore
    @State private var nouveau: Fournisseur?
    @State private var recherche = ""

    var body: some View {
        List {
            Section("Alertes réapprovisionnement") {
                let alertes = store.matieresDisponibles.filter(\.sous_seuil)
                if alertes.isEmpty {
                    Text("Aucune matière sous seuil.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alertes) { d in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(d.nom)
                            Spacer()
                            Text("\(d.disponible.formatted(.number.precision(.fractionLength(0...2)))) \(d.unite) ≤ \(d.stock_actuel.formatted())").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        BonReapproSuggereView()
                    } label: {
                        Label("Préparer des bons de réappro", systemImage: "wand.and.rays")
                    }
                }
            }
            Section("Fournisseurs") {
                ForEach(fournisseursFiltres) { f in
                    NavigationLink(destination: FournisseurDetailView(fournisseurId: f.id)) {
                        FournisseurRow(fournisseur: f)
                    }
                }
                if fournisseursFiltres.isEmpty {
                    Text("Aucun fournisseur.").foregroundStyle(.secondary)
                }
            }
            Section("Bons de réappro récents") {
                if store.bonsReappro.isEmpty {
                    Text("Aucun bon").foregroundStyle(.secondary)
                }
                ForEach(store.bonsReappro) { b in
                    NavigationLink(destination: BonReapproEditView(bonId: b.id)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(store.fournisseurs.first(where: { $0.id == b.fournisseur_id })?.nom ?? "—")
                                Text(b.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(b.statut.libelle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fournisseurs & Réappro")
        .searchable(text: $recherche, prompt: "Rechercher un fournisseur")
        .toolbar {
            ToolbarItem {
                Button { nouveau = Fournisseur.new() } label: {
                    Label("Nouveau fournisseur", systemImage: "plus")
                }
            }
        }
        .sheet(item: $nouveau) { f in
            NavigationStack {
                FournisseurEditView(fournisseurId: f.id, draft: f, isNew: true)
            }
        }
    }

    private var fournisseursFiltres: [Fournisseur] {
        let q = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.fournisseurs }
        return store.fournisseurs.filter {
            $0.nom.lowercased().contains(q)
            || ($0.email ?? "").lowercased().contains(q)
            || ($0.telephone ?? "").lowercased().contains(q)
        }
    }
}

/// Ligne de la liste : avatar à initiales + nom + sous-titre (téléphone ou email).
private struct FournisseurRow: View {
    let fournisseur: Fournisseur

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(initiales: fournisseur.initiales, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(fournisseur.nom).font(.headline)
                if let sous = sousTitre {
                    Text(sous).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var sousTitre: String? {
        if let t = fournisseur.telephone, !t.isEmpty { return t }
        if let e = fournisseur.email, !e.isEmpty { return e }
        if let c = fournisseur.contact, !c.isEmpty { return c }
        return nil
    }
}

/// Avatar circulaire à initiales, façon Contacts iOS.
struct ContactAvatar: View {
    let initiales: String
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initiales.isEmpty ? "?" : initiales)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Fiche contact fournisseur (lecture, façon Contacts iOS)

struct FournisseurDetailView: View {
    @EnvironmentObject var store: AppStore
    let fournisseurId: UUID
    @State private var edition = false

    private var fournisseur: Fournisseur? {
        store.fournisseurs.first { $0.id == fournisseurId }
    }

    var body: some View {
        Group {
            if let f = fournisseur {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 10) {
                            ContactAvatar(initiales: f.initiales, size: 100)
                            Text(f.nom).font(.title2).bold()
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)

                        actionsRapides(for: f)

                        VStack(spacing: 14) {
                            if let t = f.telephone, !t.isEmpty {
                                ContactFieldRow(label: "téléphone", value: t,
                                                tint: .green, icon: "phone.fill",
                                                url: URL(string: "tel:\(telBrut(t))"))
                            }
                            if let e = f.email, !e.isEmpty {
                                ContactFieldRow(label: "email", value: e,
                                                tint: .blue, icon: "envelope.fill",
                                                url: URL(string: "mailto:\(e)"))
                            }
                            if let a = f.adresse, !a.isEmpty {
                                ContactFieldRow(label: "adresse", value: a,
                                                tint: .red, icon: "mappin.and.ellipse",
                                                url: mapsURL(a))
                            }
                            if let n = f.notes, !n.isEmpty {
                                ContactFieldRow(label: "notes", value: n,
                                                tint: .gray, icon: "note.text", url: nil)
                            }
                            // Anciennes données : ne pas perdre le `contact` libre.
                            if let c = f.contact, !c.isEmpty,
                               c != f.telephone, c != f.email {
                                ContactFieldRow(label: "contact", value: c,
                                                tint: .gray, icon: "person.text.rectangle",
                                                url: nil)
                            }
                        }
                        .padding(.horizontal)

                        bonsLies(for: f)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 20)
                }
            } else {
                ContentUnavailableView("Fournisseur introuvable",
                                       systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifier") { edition = true }
            }
        }
        .sheet(isPresented: $edition) {
            NavigationStack {
                if let f = fournisseur {
                    FournisseurEditView(fournisseurId: f.id, draft: f)
                }
            }
        }
    }

    private func actionsRapides(for f: Fournisseur) -> some View {
        HStack(spacing: 18) {
            QuickActionButton(title: "appeler", icon: "phone.fill",
                              url: f.telephone.flatMap { URL(string: "tel:\(telBrut($0))") })
            QuickActionButton(title: "message", icon: "message.fill",
                              url: f.telephone.flatMap { URL(string: "sms:\(telBrut($0))") })
            QuickActionButton(title: "mail", icon: "envelope.fill",
                              url: f.email.flatMap { URL(string: "mailto:\($0)") })
            QuickActionButton(title: "plan", icon: "map.fill",
                              url: f.adresse.flatMap(mapsURL))
        }
        .padding(.horizontal)
    }

    private func bonsLies(for f: Fournisseur) -> some View {
        let bons = store.bonsReappro.filter { $0.fournisseur_id == f.id }
        return VStack(alignment: .leading, spacing: 8) {
            if !bons.isEmpty {
                Text("Bons de réappro").font(.headline)
                ForEach(bons) { b in
                    NavigationLink(destination: BonReapproEditView(bonId: b.id)) {
                        HStack {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading) {
                                Text(b.date.formatted(date: .abbreviated, time: .omitted))
                                Text(b.statut.libelle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func telBrut(_ s: String) -> String {
        s.filter { "+0123456789".contains($0) }
    }

    private func mapsURL(_ adresse: String) -> URL? {
        let q = adresse.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? adresse
        return URL(string: "https://maps.apple.com/?q=\(q)")
    }
}

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let url: URL?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url {
                    Link(destination: url) { icon(enabled: true) }
                } else {
                    icon(enabled: false)
                }
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(enabled: Bool) -> some View {
        ZStack {
            Circle().fill(enabled ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
            Image(systemName: icon)
                .foregroundStyle(enabled ? Color.accentColor : .gray)
        }
        .frame(width: 48, height: 48)
    }
}

private struct ContactFieldRow: View {
    let label: String
    let value: String
    let tint: Color
    let icon: String
    let url: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.18))
                Image(systemName: icon).foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let url {
                    Link(value, destination: url)
                        .font(.body).foregroundStyle(.tint)
                } else {
                    Text(value).font(.body)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }
}

struct FournisseurEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let fournisseurId: UUID
    @State var draft: Fournisseur
    var isNew: Bool = false
    @State private var errorText: String?

    init(fournisseurId: UUID, draft: Fournisseur? = nil, isNew: Bool = false) {
        self.fournisseurId = fournisseurId
        self._draft = State(initialValue: draft ?? Fournisseur.new())
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ContactAvatar(initiales: draft.initiales, size: 96)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                TextField("Nom", text: $draft.nom)
            }
            Section("Coordonnées") {
                TextField("Téléphone", text: Binding(
                    get: { draft.telephone ?? "" },
                    set: { draft.telephone = $0.isEmpty ? nil : $0 }))
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    #endif
                TextField("Email", text: Binding(
                    get: { draft.email ?? "" },
                    set: { draft.email = $0.isEmpty ? nil : $0 }))
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Adresse", text: Binding(
                    get: { draft.adresse ?? "" },
                    set: { draft.adresse = $0.isEmpty ? nil : $0 }),
                    axis: .vertical
                ).lineLimit(1...3)
            }
            Section("Notes") {
                TextField("Notes", text: Binding(
                    get: { draft.notes ?? "" },
                    set: { draft.notes = $0.isEmpty ? nil : $0 }),
                    axis: .vertical
                ).lineLimit(2...6)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouveau fournisseur" : draft.nom)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Créer" : "Enregistrer") { Task { await save() } }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
        }
        .task {
            if !isNew, let f = store.fournisseurs.first(where: { $0.id == fournisseurId }) {
                draft = f
            }
        }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func save() async {
        do {
            if isNew { _ = try await store.repo.insert("fournisseur", draft) }
            else { _ = try await store.repo.update("fournisseur", draft, id: draft.id) }
            await store.loadFournisseurs()
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}

/// Propose un bon de réappro pré-rempli, groupé par fournisseur, à partir des matières sous seuil.
struct BonReapproSuggereView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var liens: [MatiereFournisseur] = []
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        List {
            ForEach(groupes, id: \.fournisseur.id) { groupe in
                Section(groupe.fournisseur.nom) {
                    ForEach(groupe.matieres) { d in
                        HStack {
                            Text(d.nom)
                            Spacer()
                            Text("dispo \(d.disponible.formatted())").font(.caption)
                        }
                    }
                    Button {
                        Task { await creer(groupe: groupe) }
                    } label: {
                        Label("Créer le bon", systemImage: "plus.square.on.square")
                    }
                }
            }
        }
        .navigationTitle("Suggestions de réappro")
        .task { await load() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    struct Groupe {
        var fournisseur: Fournisseur
        var matieres: [MatiereDisponible]
    }

    private var groupes: [Groupe] {
        let sousSeuil = store.matieresDisponibles.filter(\.sous_seuil)
        let parMat = Dictionary(grouping: liens, by: { $0.matiere_id })
        var resultat: [UUID: [MatiereDisponible]] = [:]
        for d in sousSeuil {
            guard let lien = parMat[d.matiere_id]?.first,
                  store.fournisseurs.contains(where: { $0.id == lien.fournisseur_id }) else { continue }
            resultat[lien.fournisseur_id, default: []].append(d)
        }
        return resultat.compactMap { fid, mats in
            guard let f = store.fournisseurs.first(where: { $0.id == fid }) else { return nil }
            return Groupe(fournisseur: f, matieres: mats)
        }
    }

    private func load() async {
        do {
            liens = try await store.repo.selectAll(MatiereFournisseur.self, from: "matiere_fournisseur")
        } catch { errorText = error.localizedDescription }
    }

    private func creer(groupe: Groupe) async {
        loading = true
        defer { loading = false }
        let bon = BonReappro(id: UUID(), fournisseur_id: groupe.fournisseur.id,
                             date: Date(), statut: .brouillon, created_at: nil)
        do {
            let inserted: BonReappro = try await store.repo.insert("bon_reappro", bon)
            for m in groupe.matieres {
                let qte = max(0, (m.stock_actuel * 0) + (m.disponible < 0 ? -m.disponible : 0) + m.stock_actuel * 0 + 1)
                // quantité simple : remettre à un seuil suggéré = 2× seuil_alerte (approx via stock_actuel)
                let suggestion = max(qte, 1)
                let l = ReapproLigne(id: UUID(), bon_reappro_id: inserted.id,
                                     matiere_id: m.matiere_id, quantite: suggestion)
                _ = try await store.repo.insert("reappro_ligne", l)
            }
            await store.loadBons()
        } catch { errorText = error.localizedDescription }
    }
}

struct BonReapproEditView: View {
    @EnvironmentObject var store: AppStore
    let bonId: UUID
    @State private var bon: BonReappro?
    @State private var lignes: [ReapproLigne] = []
    @State private var errorText: String?

    var body: some View {
        Form {
            if let b = bon {
                Section("Bon") {
                    LabeledContent("Fournisseur",
                                   value: store.fournisseurs.first(where: { $0.id == b.fournisseur_id })?.nom ?? "—")
                    LabeledContent("Date", value: b.date.formatted(date: .abbreviated, time: .omitted))
                    Picker("Statut", selection: Binding(
                        get: { b.statut },
                        set: { newVal in
                            var copie = b
                            copie.statut = newVal
                            bon = copie
                            Task { await majStatut() }
                        }
                    )) {
                        ForEach(StatutReappro.allCases) { Text($0.libelle).tag($0) }
                    }
                }
                Section("Lignes") {
                    ForEach(lignes) { l in
                        HStack {
                            Text(store.matieres.first(where: { $0.id == l.matiere_id })?.nom ?? "?")
                            Spacer()
                            Text("\(l.quantite.formatted(.number.precision(.fractionLength(0...2))))")
                        }
                    }
                }
                if b.statut == .recu {
                    Section {
                        Button {
                            Task { await receptionner() }
                        } label: {
                            Label("Encaisser en stock", systemImage: "tray.and.arrow.down")
                        }
                    } footer: {
                        Text("Met à jour le stock_actuel + crée un mouvement \"entrée\" par ligne.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Bon de réappro")
        .task { await load() }
        .alert("Erreur", isPresented: .init(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func load() async {
        do {
            let all = try await store.repo.selectAll(BonReappro.self, from: "bon_reappro")
            bon = all.first { $0.id == bonId }
            let allLignes: [ReapproLigne] = try await store.repo.selectAll(ReapproLigne.self, from: "reappro_ligne")
            lignes = allLignes.filter { $0.bon_reappro_id == bonId }
        } catch { errorText = error.localizedDescription }
    }

    private func majStatut() async {
        guard let b = bon else { return }
        do {
            _ = try await store.repo.update("bon_reappro", b, id: b.id)
            await store.loadBons()
        } catch { errorText = error.localizedDescription }
    }

    private func receptionner() async {
        for l in lignes {
            let mvt = MouvementStock(id: UUID(), matiere_id: l.matiere_id,
                                     date: Date(), type: .entree, quantite: l.quantite,
                                     origine: "reappro", commande_id: nil)
            do {
                _ = try await store.repo.insert("mouvement_stock", mvt)
                if var m = store.matieres.first(where: { $0.id == l.matiere_id }) {
                    m.stock_actuel += l.quantite
                    _ = try await store.repo.update("matiere", m, id: m.id)
                }
            } catch { errorText = error.localizedDescription }
        }
        await store.loadMatieres()
    }
}
