import SwiftUI
import PhotosUI
import MapKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CommandeEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let commandeId: UUID
    @State var draft: Commande
    var isNew: Bool = false
    /// Appelé après création réussie d'une nouvelle commande. Permet à la
    /// Boîte de réception, par exemple, de marquer son `commande_entrante`
    /// associé comme « importée » + lier l'UUID de la commande créée.
    var onCreated: ((Commande) -> Void)? = nil

    @State private var lignes: [CommandeLigne] = []
    @State private var paiements: [Paiement] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var photoRefItem: PhotosPickerItem?
    @State private var photoRefUploading = false
    @State private var photoResultatItem: PhotosPickerItem?
    @State private var photoResultatUploading = false
    @State private var generationLien = false
    @State private var lienAPartager: URL?
    @State private var nouveauClient: Client?
    @State private var adresseQuery: String = ""
    @State private var adresseSuggestions: [BANAddressService.Suggestion] = []
    @State private var adresseRechercheEnCours = false
    @State private var adresseSearchTask: Task<Void, Never>?

    init(commandeId: UUID, draft: Commande? = nil, isNew: Bool = false,
         onCreated: ((Commande) -> Void)? = nil) {
        self.commandeId = commandeId
        self._draft = State(initialValue: draft ?? Commande.new())
        self.isNew = isNew
        self.onCreated = onCreated
    }

    /// Allergènes courants pour les chocolats & meringues (cases à cocher).
    private static let allergenesCourants = [
        "Gluten", "Lait", "Œuf", "Fruits à coque", "Arachide", "Soja", "Sésame",
    ]

    var body: some View {
        Form {
            sectionInfos
            sectionPhotoRef
            sectionPhotoResultat
            sectionPersonnalisation
            sectionLignes
            sectionLivraison
            sectionTotaux
            sectionPaiements
            sectionStatut
            sectionDocuments
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "Nouvelle commande" : "Commande")
        .task { await load() }
        .onChange(of: photoRefItem) { _, item in
            guard let item else { return }
            Task { await uploadPhotoRef(item) }
        }
        .onChange(of: photoResultatItem) { _, item in
            guard let item else { return }
            Task { await uploadPhotoResultat(item) }
        }
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
        .sheet(isPresented: .init(get: { lienAPartager != nil }, set: { if !$0 { lienAPartager = nil } })) {
            if let url = lienAPartager {
                ShareSheet(items: [url])
                    .presentationDetents([.medium])
            }
        }
        .sheet(item: $nouveauClient) { c in
            NavigationStack {
                ClientEditView(clientId: c.id, draft: c, isNew: true) { created in
                    // Sélectionne automatiquement le nouveau client sur la commande.
                    draft.client_id = created.id
                }
            }
        }
    }

    private var sectionInfos: some View {
        Section("Informations") {
            HStack {
                Picker("Client", selection: $draft.client_id) {
                    Text("— Aucun —").tag(UUID?.none)
                    ForEach(store.clients) { c in
                        Text(c.nom).tag(Optional(c.id))
                    }
                }
                Button {
                    nouveauClient = Client.new()
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Créer un nouveau client")
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

    private var sectionPhotoRef: some View {
        Section {
            HStack(spacing: 14) {
                PhotoRefThumb(url: draft.photo_ref_url, size: 88)
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $photoRefItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label(draft.photo_ref_url == nil
                              ? "Ajouter une photo de référence"
                              : "Remplacer la photo",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(photoRefUploading || isNew)
                    if isNew {
                        Text("Enregistre d'abord la commande pour pouvoir y joindre une photo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if photoRefUploading {
                        ProgressView().controlSize(.small)
                    }
                    if draft.photo_ref_url != nil && !photoRefUploading && !isNew {
                        Button(role: .destructive) {
                            draft.photo_ref_url = nil
                            Task { await save() }
                        } label: { Label("Supprimer", systemImage: "trash") }
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Photo de référence")
        } footer: {
            Text("Photo « comme ce style » envoyée par le client ou prise par vous, visible aussi sur la feuille de production.")
        }
    }

    private var sectionPhotoResultat: some View {
        Section {
            HStack(spacing: 14) {
                PhotoRefThumb(url: draft.photo_resultat_url, size: 88)
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $photoResultatItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label(draft.photo_resultat_url == nil
                              ? "Ajouter la photo finale"
                              : "Remplacer la photo",
                              systemImage: "checkmark.seal.fill")
                    }
                    .disabled(photoResultatUploading || isNew)
                    if isNew {
                        Text("Enregistre d'abord la commande pour pouvoir ajouter la photo du résultat.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if photoResultatUploading {
                        ProgressView().controlSize(.small)
                    }
                    if draft.photo_resultat_url != nil && !photoResultatUploading && !isNew {
                        Button(role: .destructive) {
                            draft.photo_resultat_url = nil
                            Task { await save() }
                        } label: { Label("Supprimer", systemImage: "trash") }
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Photo après production")
        } footer: {
            Text("Photo du résultat fini, visible dans l'historique du client et affichée automatiquement dans la galerie « Inspirations » de votre site.")
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

    private var sectionLivraison: some View {
        Section("Remise du produit") {
            Picker("Mode", selection: $draft.mode_remise) {
                ForEach(ModeRemise.allCases) { m in
                    Text(m.libelle).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.mode_remise) { _, new in
                if new == .retrait {
                    draft.zone_livraison_id = nil
                    draft.frais_livraison = 0
                    draft.adresse_livraison = nil
                    draft.latitude = nil
                    draft.longitude = nil
                    adresseQuery = ""
                    adresseSuggestions = []
                }
            }
            if draft.mode_remise == .livraison {
                adresseInput
                suggestionsList
                adresseMap
                zonePicker
            }
        }
    }

    @ViewBuilder private var adresseInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adresse de livraison").font(.caption).foregroundStyle(.secondary)
            TextField("Commencez à taper votre adresse…",
                      text: $adresseQuery, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .onChange(of: adresseQuery) { _, new in
                    // Debounce 300 ms : annule la recherche précédente.
                    adresseSearchTask?.cancel()
                    if new.isEmpty {
                        adresseSuggestions = []
                        return
                    }
                    adresseSearchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if Task.isCancelled { return }
                        adresseRechercheEnCours = true
                        let results = await BANAddressService.search(new)
                        if Task.isCancelled { return }
                        adresseSuggestions = results
                        adresseRechercheEnCours = false
                    }
                }
            if adresseRechercheEnCours {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder private var suggestionsList: some View {
        if !adresseSuggestions.isEmpty {
            ForEach(adresseSuggestions) { s in
                Button {
                    appliquerSuggestion(s)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(.subheadline).foregroundStyle(.primary)
                        if let cp = s.postcode, let v = s.city {
                            Text("\(cp) — \(v)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var adresseMap: some View {
        if let lat = draft.latitude, let lon = draft.longitude {
            VStack(alignment: .leading, spacing: 6) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                    Marker(draft.adresse_livraison ?? "Livraison",
                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        .tint(Color.hkRoseDeep)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    ouvrirDansPlans(lat: lat, lon: lon)
                } label: {
                    Label("Ouvrir l'itinéraire dans Plans", systemImage: "map")
                }
            }
        }
    }

    @ViewBuilder private var zonePicker: some View {
        let zonesActives = store.zonesLivraison.filter { $0.actif && $0.tarif > 0 }
        Picker("Zone", selection: $draft.zone_livraison_id) {
            Text("— Choisir —").tag(UUID?.none)
            ForEach(zonesActives) { z in
                HStack {
                    Text(z.nom)
                    Spacer()
                    Text(z.tarif, format: .currency(code: "EUR"))
                        .foregroundStyle(.secondary)
                }
                .tag(Optional(z.id))
            }
        }
        .onChange(of: draft.zone_livraison_id) { _, new in
            draft.frais_livraison = store.zoneLivraison(id: new)?.tarif ?? 0
        }
        if zonesActives.isEmpty {
            Text("Aucune zone configurée. Ajoute-en une dans Réglages → Zones de livraison.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func appliquerSuggestion(_ s: BANAddressService.Suggestion) {
        draft.adresse_livraison = s.label
        draft.latitude = s.latitude
        draft.longitude = s.longitude
        adresseQuery = s.label
        adresseSuggestions = []
        // Détection auto de la zone selon le code postal — modifiable
        // manuellement ensuite par le user via le picker.
        if let detected = store.detectZoneLivraison(codePostal: s.postcode) {
            draft.zone_livraison_id = detected.id
            draft.frais_livraison = detected.tarif
        }
    }

    private func ouvrirDansPlans(lat: Double, lon: Double) {
        // URL universelle Apple Plans : ouvre l'app sur iOS/macOS avec
        // mode itinéraire en voiture depuis la position actuelle.
        let urlStr = "http://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d"
        guard let url = URL(string: urlStr) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private var sectionTotaux: some View {
        Section("Totaux") {
            HStack { Text("Sous-total produits"); Spacer()
                Text(totalProduits, format: .currency(code: "EUR")).foregroundStyle(.secondary)
            }
            if draft.frais_livraison > 0 {
                HStack { Text("Frais de livraison"); Spacer()
                    Text(draft.frais_livraison, format: .currency(code: "EUR")).foregroundStyle(.secondary)
                }
            }
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
            Button {
                Task { await partagerLienPaiement(motif: .acompte) }
            } label: {
                Label(generationLien ? "Génération…" : "Partager un lien d'acompte",
                      systemImage: "link")
            }
            .disabled(isNew || generationLien || acompte <= 0 || encaisse > 0)
            Button {
                Task { await partagerLienPaiement(motif: .solde) }
            } label: {
                Label(generationLien ? "Génération…" : "Partager un lien de solde",
                      systemImage: "link.circle")
            }
            .disabled(isNew || generationLien || resteDu <= 0)
        }
    }

    private var sectionDocuments: some View {
        Section {
            LabeledContent("Référence", value: draft.refCourte)
            if let n = draft.numero_facture {
                LabeledContent("Facture", value: n)
            } else {
                Text("Le numéro de facture sera attribué automatiquement quand l'acompte sera reçu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let r = draft.rappel_envoye_at {
                LabeledContent("Rappel J-3 envoyé") {
                    Text(r.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Color.hkSageDeep)
                }
            }
            if let o = draft.email_confirmation_ouvert_at {
                LabeledContent("Confirmation ouverte ✓") {
                    Text(o.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Color.hkSageDeep)
                }
            }
            if let o = draft.email_rappel_ouvert_at {
                LabeledContent("Rappel ouvert ✓") {
                    Text(o.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Color.hkSageDeep)
                }
            }
            Button {
                Task { await partagerDevisPDF() }
            } label: {
                Label("Devis PDF", systemImage: "doc.text")
            }
            .disabled(isNew || lignes.isEmpty)
            Button {
                Task { await partagerFacturePDF() }
            } label: {
                Label("Facture PDF", systemImage: "doc.richtext")
            }
            .disabled(isNew)
            Button {
                Task { await partagerEtiquettesPDF() }
            } label: {
                Label("Étiquettes à coller", systemImage: "tag")
            }
            .disabled(isNew || lignes.isEmpty)
        } header: {
            Text("Documents")
        } footer: {
            Text("La facture est numérotée séquentiellement (F\(Calendar.current.component(.year, from: Date()))-001…). Un rappel J-3 est envoyé automatiquement au client par email quand l'atelier a une clé Resend configurée.")
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

    private var totalProduits: Double {
        lignes.reduce(0) { $0 + Double($1.quantite) * $1.prix_unitaire }
    }
    private var totalCalcule: Double {
        totalProduits + draft.frais_livraison
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
        adresseQuery = draft.adresse_livraison ?? ""
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
            var inserted: Commande? = nil
            if isNew {
                let row: Commande = try await store.repo.insert("commande", d)
                inserted = row
                for var l in lignes {
                    l.commande_id = row.id
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
            if let inserted { onCreated?(inserted) }
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
            // 1. Retire l'événement Calendrier associé s'il existe (avant le
            //    delete BDD pour avoir encore le contexte de la commande).
            if store.calendarSyncEnabled,
               let cid = store.calendarSyncId,
               let cal = CalendarService.shared.calendar(id: cid) {
                try? CalendarService.shared.remove(commandeId: commandeId, calendar: cal)
            }
            // 2. Supprime la commande dans Supabase (cascade sur les lignes
            //    et paiements grâce aux FK ON DELETE CASCADE).
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

    // MARK: - Upload photo de référence

    private func uploadPhotoRef(_ item: PhotosPickerItem) async {
        photoRefUploading = true
        defer { photoRefUploading = false; photoRefItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let (payload, ext) = compressedJPEG(data) ?? (data, "jpg")
            let url = try await store.repo.uploadPhotoCommande(
                commande: commandeId, data: payload, ext: ext)
            draft.photo_ref_url = url
            _ = try await store.repo.update("commande", draft, id: draft.id)
            await store.loadCommandes()
        } catch { errorText = error.localizedDescription }
    }

    private func uploadPhotoResultat(_ item: PhotosPickerItem) async {
        photoResultatUploading = true
        defer { photoResultatUploading = false; photoResultatItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let (payload, ext) = compressedJPEG(data) ?? (data, "jpg")
            let url = try await store.repo.uploadPhotoResultat(
                commande: commandeId, data: payload, ext: ext)
            draft.photo_resultat_url = url
            _ = try await store.repo.update("commande", draft, id: draft.id)
            await store.loadCommandes()
        } catch { errorText = error.localizedDescription }
    }

    private func compressedJPEG(_ data: Data) -> (Data, String)? {
        #if canImport(UIKit)
        if let img = UIImage(data: data),
           let jpeg = img.jpegData(compressionQuality: 0.8) {
            return (jpeg, "jpg")
        }
        #endif
        return nil
    }

    // MARK: - Export PDF (facture / étiquettes)

    @MainActor
    private func partagerFacturePDF() async {
        let atelier = CommandeExport.Atelier.from(config: store.config)
        guard let url = CommandeExport.generateFacturePDF(
            commande: draft,
            client: store.client(id: draft.client_id),
            lignes: lignes,
            produit: { store.produit(id: $0) },
            atelier: atelier,
            encaisse: encaisse
        ) else {
            errorText = "Génération du PDF impossible."
            return
        }
        partagerFichier(url)
    }

    @MainActor
    private func partagerDevisPDF() async {
        let atelier = CommandeExport.Atelier.from(config: store.config)
        guard let url = CommandeExport.generateDevisPDF(
            commande: draft,
            client: store.client(id: draft.client_id),
            lignes: lignes,
            produit: { store.produit(id: $0) },
            atelier: atelier
        ) else {
            errorText = "Aucune ligne dans la commande."
            return
        }
        partagerFichier(url)
    }

    @MainActor
    private func partagerEtiquettesPDF() async {
        let atelier = CommandeExport.Atelier.from(config: store.config)
        guard let url = CommandeExport.generateEtiquettesPDF(
            commande: draft,
            client: store.client(id: draft.client_id),
            lignes: lignes,
            produit: { store.produit(id: $0) },
            atelier: atelier
        ) else {
            errorText = "Aucune ligne dans la commande."
            return
        }
        partagerFichier(url)
    }

    private func partagerFichier(_ url: URL) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        #else
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let rootVC = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        rootVC?.present(av, animated: true)
        #endif
    }

    // MARK: - Lien de paiement Stripe

    private func partagerLienPaiement(motif: Repository.MotifPaiement) async {
        generationLien = true
        defer { generationLien = false }
        do {
            let lien = try await store.repo.creerLienPaiement(
                commande: commandeId, motif: motif)
            guard let url = URL(string: lien.checkout_url) else {
                errorText = "URL de paiement invalide."
                return
            }
            // Si le client a un email → ouvre directement Mail avec un brouillon
            // pré-rempli (destinataire + corps avec le lien). Sinon on retombe
            // sur la share sheet (Messages, WhatsApp, copie…).
            let client = store.client(id: draft.client_id)
            if let email = client?.email?.trimmingCharacters(in: .whitespaces),
               !email.isEmpty,
               ouvrirMailAvecLien(url: url, motif: motif, client: client, email: email) {
                return
            }
            lienAPartager = url
        } catch {
            errorText = "Génération du lien : \(error.localizedDescription)"
        }
    }

    /// Construit un mailto: et l'ouvre dans l'app Mail. Retourne `false` si
    /// l'ouverture échoue → appelant retombe sur la share sheet.
    private func ouvrirMailAvecLien(url: URL, motif: Repository.MotifPaiement,
                                    client: Client?, email: String) -> Bool {
        let libelle = motif == .acompte ? "acompte" : motif == .solde ? "solde" : "paiement"
        let prenom = client?.nom.split(separator: " ").first.map(String.init) ?? ""
        let salutation = prenom.isEmpty ? "Bonjour," : "Bonjour \(prenom),"
        let subject = "Lien de paiement HappyKreations — \(libelle)"
        let body = """
        \(salutation)

        Voici votre lien de paiement sécurisé pour votre \(libelle) :
        \(url.absoluteString)

        À très vite,
        HappyKreations
        """
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = email
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let mailto = comps.url else { return false }
        #if os(iOS)
        guard UIApplication.shared.canOpenURL(mailto) else { return false }
        UIApplication.shared.open(mailto)
        return true
        #else
        return NSWorkspace.shared.open(mailto)
        #endif
    }
}

/// Sheet de partage cross-platform : ouvre Messages, WhatsApp, Mail, etc.
struct ShareSheet: View {
    let items: [Any]

    var body: some View {
        #if os(iOS)
        UIShareSheetWrapper(items: items)
        #else
        // macOS : copie dans le presse-papiers (premier URL trouvé dans items)
        VStack(spacing: 16) {
            Text("Lien à partager").font(.headline)
            if let url = items.compactMap({ $0 as? URL }).first {
                Text(url.absoluteString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        #endif
    }
}

#if os(iOS)
import UIKit
private struct UIShareSheetWrapper: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

/// Vignette de la photo de référence (avec placeholder).
private struct PhotoRefThumb: View {
    let url: String?
    var size: CGFloat = 88

    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18))
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LigneRow: View {
    @EnvironmentObject var store: AppStore
    @Binding var ligne: CommandeLigne

    var body: some View {
        VStack(spacing: 6) {
            Picker("Produit", selection: $ligne.produit_id) {
                ForEach(store.produits) { p in
                    Text(p.nom.isEmpty ? "(Produit sans nom)" : p.nom).tag(p.id)
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
