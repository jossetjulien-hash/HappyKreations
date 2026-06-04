import WidgetKit
import SwiftUI

// MARK: - Données partagées via App Group
//
// L'app principale écrit après chaque chargement la liste des retraits du
// jour dans UserDefaults(suiteName: groupId). Le widget la lit ici (lecture
// rapide, fonctionne hors-ligne, pas de réseau dans le widget).

enum WidgetSharedStore {
    static let groupId = "group.com.happykreations.app"
    static let dataKey = "widget.today.payload"
    static let updatedKey = "widget.today.updated"

    struct Payload: Codable {
        let updated: Date
        let nbRetraitsAujourdhui: Int
        let prochaines: [Ligne]

        struct Ligne: Codable, Identifiable {
            let id: String       // UUID stringifié
            let clientNom: String
            let total: Double
            /// Date ISO de retrait (informatif, sans heure).
            let dateRetrait: Date?
        }
    }

    static func load() -> Payload? {
        guard let defaults = UserDefaults(suiteName: groupId),
              let data = defaults.data(forKey: dataKey)
        else { return nil }
        return try? JSONDecoder.iso8601.decode(Payload.self, from: data)
    }

    static func save(_ payload: Payload) {
        guard let defaults = UserDefaults(suiteName: groupId) else { return }
        if let data = try? JSONEncoder.iso8601.encode(payload) {
            defaults.set(data, forKey: dataKey)
            defaults.set(payload.updated, forKey: updatedKey)
        }
    }
}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - TimelineProvider

struct AujourdhuiProvider: TimelineProvider {
    func placeholder(in context: Context) -> AujourdhuiEntry {
        AujourdhuiEntry(
            date: .now,
            nb: 2,
            lignes: [
                .init(client: "Camille L.", total: 48.50, dateRetrait: .now),
                .init(client: "Paul D.",    total: 32.00, dateRetrait: .now),
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AujourdhuiEntry) -> Void) {
        completion(entry(from: WidgetSharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AujourdhuiEntry>) -> Void) {
        let now = Date()
        let current = entry(from: WidgetSharedStore.load(), date: now)
        // Rafraîchit toutes les 30 min pour rester à jour sans consommer
        // trop de budget système. L'app force aussi une mise à jour via
        // WidgetCenter.shared.reloadTimelines() après chaque loadAll.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: [current], policy: .after(next)))
    }

    private func entry(from payload: WidgetSharedStore.Payload?, date: Date = .now) -> AujourdhuiEntry {
        AujourdhuiEntry(
            date: date,
            nb: payload?.nbRetraitsAujourdhui ?? 0,
            lignes: (payload?.prochaines ?? []).map {
                AujourdhuiEntry.Ligne(client: $0.clientNom, total: $0.total, dateRetrait: $0.dateRetrait)
            }
        )
    }
}

struct AujourdhuiEntry: TimelineEntry {
    let date: Date
    let nb: Int
    let lignes: [Ligne]

    struct Ligne {
        let client: String
        let total: Double
        let dateRetrait: Date?
    }
}

// MARK: - Vue du widget

struct AujourdhuiWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: AujourdhuiEntry

    var body: some View {
        switch family {
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer()
            Text("\(entry.nb)")
                .font(.system(size: 44, weight: .light, design: .serif))
                .foregroundStyle(.primary)
            Text(entry.nb <= 1 ? "retrait aujourd'hui" : "retraits aujourd'hui")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.lignes.isEmpty {
                Spacer()
                Text("Rien à retirer aujourd'hui ✿")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.lignes.prefix(3).enumerated()), id: \.offset) { _, l in
                    HStack {
                        Text(l.client).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(l.total, format: .currency(code: "EUR"))
                            .font(.subheadline).bold()
                    }
                }
                if entry.nb > 3 {
                    Text("+ \(entry.nb - 3) autre\(entry.nb - 3 > 1 ? "s" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    /// En-tête : monogramme + logotype.
    private var header: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            (
                Text("happy")
                    .font(.system(size: 14, weight: .light, design: .serif))
                +
                Text("kreations")
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 0.788, green: 0.514, blue: 0.533))
            )
        }
    }
}

// MARK: - Widget root

@main
struct HappyKreationsWidget: Widget {
    let kind = "HappyKreationsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AujourdhuiProvider()) { entry in
            AujourdhuiWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.984, green: 0.965, blue: 0.937),
                            Color(red: 0.953, green: 0.918, blue: 0.863),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Aujourd'hui")
        .description("Les commandes à retirer aujourd'hui dans ton atelier.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
