import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                grid
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Tableau de bord")
        .toolbar {
            #if os(macOS)
            ToolbarItem {
                Button("Rafraîchir") { Task { await store.loadAll() } }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bonjour 👋").font(.title2).bold()
            if let email = auth.userEmail {
                Text(email).foregroundStyle(.secondary).font(.subheadline)
            }
        }
    }

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: 240), spacing: 16)]
        return LazyVGrid(columns: columns, spacing: 16) {
            stat("Commandes à venir", value: "\(commandesAVenir.count)", icon: "calendar.badge.clock", tint: .blue)
            stat("Alertes stock", value: "\(alertesStock)", icon: "exclamationmark.triangle", tint: .orange)
            stat("Encaissé ce mois", value: euros(encaisseMois), icon: "eurosign.circle", tint: .green)
            stat("Reste dû global", value: euros(resteDuGlobal), icon: "creditcard", tint: .red)
        }
    }

    private func stat(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title).bold().foregroundStyle(tint)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }

    private var commandesAVenir: [Commande] {
        let today = Calendar.current.startOfDay(for: Date())
        return store.commandes.filter {
            ($0.date_retrait ?? .distantFuture) >= today
            && $0.statut != .annulee && $0.statut != .soldee
        }
    }

    private var alertesStock: Int {
        store.matieresDisponibles.filter(\.sous_seuil).count
    }

    private var encaisseMois: Double {
        let cal = Calendar.current
        let comp = cal.dateComponents([.year, .month], from: Date())
        let monthStart = cal.date(from: comp) ?? Date()
        return store.paiements
            .filter { $0.statut == .reussi && $0.date >= monthStart }
            .reduce(0) { $0 + $1.montant }
    }

    private var resteDuGlobal: Double {
        store.commandes.reduce(0.0) { acc, c in
            if c.statut == .annulee || c.statut == .soldee { return acc }
            let paye = store.paiementsTotal(commande: c.id)
            return acc + max(0, c.total - paye)
        }
    }

    private func euros(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: v as NSNumber) ?? "\(v) €"
    }
}
