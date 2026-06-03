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
    @Published var commandes: [Commande] = []
    @Published var paiements: [Paiement] = []
    @Published var fournisseurs: [Fournisseur] = []
    @Published var bonsReappro: [BonReappro] = []
    @Published var capacites: [CapaciteJour] = []
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
        _ = await (c, p, m, co, pa, f, b, k, cf)
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
        do { produits = try await repo.selectAll(Produit.self, from: "produit", orderBy: "nom") }
        catch { lastError = "produit: \(error.localizedDescription)" }
    }

    func loadMatieres() async {
        do {
            matieres = try await repo.selectAll(Matiere.self, from: "matiere", orderBy: "nom")
            matieresDisponibles = try await repo.matieresDisponibles()
        } catch { lastError = "matiere: \(error.localizedDescription)" }
    }

    func loadCommandes() async {
        do {
            commandes = try await repo.selectAll(Commande.self, from: "commande",
                                                 orderBy: "date_retrait", ascending: true)
            await syncCommandesToCalendar()
        } catch { lastError = "commande: \(error.localizedDescription)" }
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
        stopRealtime()
        let client = SupabaseService.shared.client
        let channel = client.channel("public:happykreations")

        Task {
            let commandes = channel.postgresChange(AnyAction.self,
                                                   schema: "public", table: "commande")
            let matieres = channel.postgresChange(AnyAction.self,
                                                  schema: "public", table: "matiere")
            let produits = channel.postgresChange(AnyAction.self,
                                                  schema: "public", table: "produit")

            await channel.subscribe()

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
                self.realtimeTasks = [t1, t2, t3]
            }
        }
    }

    func stopRealtime() {
        for t in realtimeTasks { t.cancel() }
        realtimeTasks = []
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

    /// Pousse l'état actuel des commandes dans le Calendrier sélectionné.
    func syncCommandesToCalendar() async {
        guard calendarSyncEnabled,
              CalendarService.shared.hasAccess,
              let cid = calendarSyncId,
              let cal = CalendarService.shared.calendar(id: cid)
        else { return }
        for cmd in commandes {
            let nom = client(id: cmd.client_id)?.nom
            try? CalendarService.shared.sync(commande: cmd, clientNom: nom, calendar: cal)
        }
    }
}
