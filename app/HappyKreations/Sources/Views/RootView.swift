import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, commandes, agenda, stock, recettes, fournisseurs, clients, reglages
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Tableau de bord"
        case .commandes:    return "Commandes"
        case .agenda:       return "Agenda"
        case .stock:        return "Stock"
        case .recettes:     return "Recettes"
        case .fournisseurs: return "Fournisseurs"
        case .clients:      return "Clients"
        case .reglages:     return "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:    return "rectangle.3.group"
        case .commandes:    return "list.bullet.rectangle"
        case .agenda:       return "calendar"
        case .stock:        return "shippingbox"
        case .recettes:     return "list.clipboard"
        case .fournisseurs: return "person.2"
        case .clients:      return "person.crop.circle"
        case .reglages:     return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: AppStore
    @State private var selection: AppSection = .dashboard

    var body: some View {
        Group {
            if auth.isAuthenticated {
                mainView
                    .task {
                        await store.loadAll()
                        store.startRealtime()
                    }
            } else {
                LoginView()
            }
        }
    }

    @ViewBuilder
    private var mainView: some View {
        #if os(macOS)
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { s in
                NavigationLink(value: s) {
                    Label(s.label, systemImage: s.icon)
                }
            }
            .navigationTitle(AppConfig.appName)
            .frame(minWidth: 200)
        } detail: {
            NavigationStack {
                sectionView(selection)
            }
            .id(selection)
        }
        #else
        TabView(selection: $selection) {
            ForEach(primaryTabs) { s in
                NavigationStack { sectionView(s) }
                    .tabItem { Label(s.label, systemImage: s.icon) }
                    .tag(s)
            }
            NavigationStack {
                List {
                    ForEach(secondaryTabs) { s in
                        NavigationLink(destination: sectionView(s)) {
                            Label(s.label, systemImage: s.icon)
                        }
                    }
                }
                .navigationTitle("Plus")
            }
            .tabItem { Label("Plus", systemImage: "ellipsis.circle") }
            .tag(AppSection.reglages)
        }
        #endif
    }

    private let primaryTabs: [AppSection] = [.dashboard, .commandes, .agenda, .stock]
    private let secondaryTabs: [AppSection] = [.recettes, .fournisseurs, .clients, .reglages]

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .dashboard:    DashboardView()
        case .commandes:    CommandesListView()
        case .agenda:       AgendaView()
        case .stock:        MatieresListView()
        case .recettes:     RecettesListView()
        case .fournisseurs: FournisseursListView()
        case .clients:      ClientsListView()
        case .reglages:     ReglagesView()
        }
    }
}
