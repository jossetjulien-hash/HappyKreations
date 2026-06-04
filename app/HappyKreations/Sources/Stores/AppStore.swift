import Foundation
import SwiftUI
import Supabase
import EventKit

/// Cache central + abonnements Realtime aux tables principales.
@MainActor
final class AppStore: ObservableObject {
    @Published var clients: [Client] = []
    @Published var produits: [Produit] = []
    @Published var matieres: [Matiere] = []
    @Published var matieresDisponibles: [MatiereDisponible] = []
    @Published var produitsMarges: [ProduitMarge] = []
    @Published var commandes: [Commande] = []
    @Published var paiements: [Paiement] = []
    @Published var fournisseurs: [Fournisseur] = []
    @Published var bonsReappro: [BonReappro] = []
    @Published var capacites: [CapaciteJour] = []
    @Published var commandesEntrantes: [CommandeEntrante] = []
    @Published var codesPromo: [CodePromo] = []
    @Published var temoignages: [Temoignage] = []
    @Published var config: [String: String] = [:]

    @Published var lastError: String?
    @Published var isLoading = false

    // MARK: - Sync Calendrier Apple (EventKit)

    @Published var calendarSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarSyncEnabled, forKey: Self.calSyncEnabledKey) }
    }
    @Published var calendarSyncId: String? {
        didSet { UserDefaults.standard.set(calendarSyncId, forKey: Self.calSyncIdKey) }
    }
    private static let calSyncEnabledKey = "happykreations.calendarSyncEnabled"
    private static let calSyncIdKey = "happykreations.calendarSyncId"

    let repo = Repository()
    private var realtimeTasks: [Task<Void, Never>] = []
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeStarting = false

    init() {
        self.calendarSyncEnabled = UserDefaults.standard.bool(forKey: Self.calSyncEnabledKey)
        self.calendarSyncId = UserDefaults.standard.string(forKey: Self.calSyncIdKey)
    }

    // MARK: - Chargement

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        async let c: () = loadClients()
        async let p: () = loadProduits()
        async let m: () = loadMatieres()
        async let co: () = loadCommandes()
        async let pa: () = loadPaiements()
        async let f: () = loadFournisseurs()
        async let b: () = loadBons()
        async let k: () = loadCapacites()
        async let cf: () = loadConfig()
        async let t: () = loadTemoignages()
        async let e: () = loadEntrantes()
        async let cp: () = loadCodesPromo()
        _ = await (c, p, m, co, pa, f, b, k, cf, t, e, cp)
        // Indexation Spotlight des données fraîchement chargées.
        await SpotlightIndexer.reindex(store: self)
        // Pousse les retraits du jour vers le widget.
        WidgetBridge.push(store: self)
    }

    func loadTemoignages() async {
        do {
            temoignages = try await repo.selectAll(Temoignage.self, from: "temoignage",
                                                   orderBy: "ordre")
        } catch { lastError = "temoignage: \(error.localizedDescription)" }
    }

    func loadEntrantes() async {
        do {
            commandesEntrantes = try await repo.selectAll(
                CommandeEntrante.self, from: "commande_entrante",
                orderBy: "recu_le", ascending: false)
        } catch { lastError = "commande_entrante: \(error.localizedDescription)" }
    }

    func loadCodesPromo() async {
        do {
            codesPromo = try await repo.selectAll(
                CodePromo.self, from: "code_promo",
                orderBy: "date_fin", ascending: false)
        } catch { lastError = "code_promo: \(error.localizedDescription)" }
    }

    func loadPaiements() async {
        do {
            paiements = try await repo.selectAll(Paiement.self, from: "paiement",
                                                  orderBy: "date", ascending: false)
        } catch { lastError = "paiement: \(error.localizedDescription)" }
    }

    func loadClients() async {
        do { clients = try await repo.selectAll(Client.self, from: "client", orderBy: "nom") }
        catch { lastError = "client: \(error.localizedDescription)" }
    }

    func loadProduits() async {
        do {
            produits = try await repo.selectAll(Produit.self, from: "produit", orderBy: "nom")
            produitsMarges = try await repo.produitsMarges()
        } catch { lastError = "produit: \(error.localizedDescription)" }
    }

    func loadMatieres() async {
        do {
            matieres = try await repo.selectAll(Matiere.self, from: "matiere", orderBy: "nom")
            matieresDisponibles = try await repo.matieresDisponibles()
            produitsMarges = try await repo.produitsMarges()
        } catch { lastError = "matiere: \(error.localizedDescription)" }
    }

    /// `true` après le premier chargement réussi — on n'envoie des notifications
    /// que sur les reloads ultérieurs (sinon, au démarrage, on notifierait pour
    /// toutes les commandes déjà existantes).
    private var commandesLoadedOnce = false

    func loadCommandes() async {
        do {
            let avant = commandes
            let nouvelles = try await repo.selectAll(Commande.self, from: "commande",
                                                     orderBy: "date_retrait", ascending: true)
            if commandesLoadedOnce {
                await notifierChangements(avant: avant, apres: nouvelles)
            }
            commandes = nouvelles
            commandesLoadedOnce = true
            await syncCommandesToCalendar()
        } catch { lastError = "commande: \(error.localizedDescription)" }
    }

    /// Détecte les nouveautés et déclenche les notifications locales.
    /// - Nouvelle commande formulaire (insertion) → « Nouvelle commande ».
    /// - Transition a_confirmer → confirmee (acompte Stripe reçu) → « Acompte reçu ».
    private func notifierChangements(avant: [Commande], apres: [Commande]) async {
        let parId = Dictionary(uniqueKeysWithValues: avant.map { ($0.id, $0) })
        for c in apres {
            if let precedent = parId[c.id] {
                if precedent.statut == .a_confirmer && c.statut == .confirmee {
                    await LocalNotificationService.shared.notifyAcompteRecu(
                        c, clientNom: client(id: c.client_id)?.nom)
                }
            } else if c.canal == .formulaire {
                await LocalNotificationService.shared.notifyNouvelleCommande(
                    c, clientNom: client(id: c.client_id)?.nom)
            }
        }
    }

    func loadFournisseurs() async {
        do { fournisseurs = try await repo.selectAll(Fournisseur.self, from: "fournisseur", orderBy: "nom") }
        catch { lastError = "fournisseur: \(error.localizedDescription)" }
    }

    func loadBons() async {
        do {
            bonsReappro = try await repo.selectAll(BonReappro.self, from: "bon_reappro",
                                                   orderBy: "date", ascending: false)
        } catch { lastError = "bon_reappro: \(error.localizedDescription)" }
    }

    func loadCapacites() async {
        do { capacites = try await repo.selectAll(CapaciteJour.self, from: "capacite_jour",
                                                  orderBy: "date") }
        catch { lastError = "capacite_jour: \(error.localizedDescription)" }
    }

    func loadConfig() async {
        do {
            let items = try await repo.config()
            config = Dictionary(uniqueKeysWithValues: items.map { ($0.cle, $0.valeur) })
        } catch { lastError = "config: \(error.localizedDescription)" }
    }

    // MARK: - Realtime

    func startRealtime() {
        // Idempotent : si on est déjà connecté ou en train de s'abonner, ne
        // refait rien. Évite le warning supabase-swift « Cannot add
        // postgres_changes callbacks after subscribe() » qui se déclenche
        // si on rappelle postgresChange sur un channel déjà subscribed.
        guard realtimeChannel == nil, !realtimeStarting else { return }
        realtimeStarting = true

        Task {
            defer { realtimeStarting = false }
            let client = SupabaseService.shared.client
            let channel = client.channel("public:happykreations")

            let commandes = channel.postgresChange(AnyAction.self,
                                                   schema: "public", table: "commande")
            let matieres = channel.postgresChange(AnyAction.self,
                                                  schema: "public", table: "matiere")
            let produits = channel.postgresChange(AnyAction.self,
                                                  schema: "public", table: "produit")

            do {
                try await channel.subscribeWithError()
            } catch {
                lastError = "realtime: \(error.localizedDescription)"
                return
            }

            let t1 = Task { [weak self] in
                for await _ in commandes { await self?.loadCommandes() }
            }
            let t2 = Task { [weak self] in
                for await _ in matieres { await self?.loadMatieres() }
            }
            let t3 = Task { [weak self] in
                for await _ in produits { await self?.loadProduits() }
            }
            await MainActor.run {
                self.realtimeChannel = channel
                self.realtimeTasks = [t1, t2, t3]
            }
        }
    }

    func stopRealtime() {
        for t in realtimeTasks { t.cancel() }
        realtimeTasks = []
        if let channel = realtimeChannel {
            // Désabonnement asynchrone côté Supabase pour que le prochain
            // startRealtime() recrée un channel propre. On capture la ref
            // pour ne pas dépendre de self.
            Task { await SupabaseService.shared.client.removeChannel(channel) }
            realtimeChannel = nil
        }
    }

    // MARK: - Helpers UI

    func client(id: UUID?) -> Client? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    func produit(id: UUID) -> Produit? {
        produits.first { $0.id == id }
    }

    func paiementsTotal(commande id: UUID) -> Double {
        paiements.filter { $0.commande_id == id && $0.statut == .reussi }
            .reduce(0) { $0 + $1.montant }
    }

    var acomptePourcent: Double {
        Double(config["acompte_pourcent"] ?? "30") ?? 30
    }

    // MARK: - Sync vers Calendrier Apple

    func enableCalendarSync(calendarId: String) async {
        let ok = await CalendarService.shared.requestAccess()
        guard ok else {
            lastError = "Accès Calendrier refusé."
            return
        }
        calendarSyncId = calendarId
        calendarSyncEnabled = true
        await syncCommandesToCalendar()
    }

    func disableCalendarSync() {
        calendarSyncEnabled = false
        calendarSyncId = nil
    }

    /// Pousse l'état actuel des commandes dans le Calendrier sélectionné, et
    /// supprime les événements orphelins (commandes qui n'existent plus côté
    /// BDD mais dont l'event est resté dans le calendrier — typiquement après
    /// une suppression depuis une autre interface ou avant l'introduction du
    /// retrait à la suppression).
    func syncCommandesToCalendar() async {
        guard calendarSyncEnabled,
              CalendarService.shared.hasAccess,
              let cid = calendarSyncId,
              let cal = CalendarService.shared.calendar(id: cid)
        else { return }
        // 1. Upsert : crée / met à jour / retire (si annulée) chaque commande.
        for cmd in commandes {
            let nom = client(id: cmd.client_id)?.nom
            try? CalendarService.shared.sync(commande: cmd, clientNom: nom, calendar: cal)
        }
        // 2. Purge les orphelins : tout event HappyKreations dans le calendrier
        //    dont l'UUID n'est plus dans la liste actuelle est supprimé.
        let ids = Set(commandes.map(\.id))
        CalendarService.shared.removeOrphans(existingCommandeIds: ids, calendar: cal)
    }
}
