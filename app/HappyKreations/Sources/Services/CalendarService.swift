import Foundation
import EventKit

/// Pont vers l'app Calendrier locale (EventKit). Les événements écrits ici
/// remontent automatiquement vers tous les appareils Apple via iCloud — pas
/// besoin de gérer une authentification supplémentaire : on hérite de l'iCloud
/// déjà configuré au niveau du système.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()

    private init() {}

    private static let urlScheme = "happykreations"

    // MARK: - Autorisation

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var hasAccess: Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    // MARK: - Calendriers disponibles

    /// Calendriers où l'app peut écrire (filtre les "Anniversaires", abonnements, etc.).
    var writableCalendars: [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    var defaultCalendar: EKCalendar? {
        store.defaultCalendarForNewEvents
    }

    func calendar(id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    // MARK: - Sync d'une commande

    /// Crée ou met à jour l'événement Calendrier correspondant à la commande.
    /// Si la commande est annulée ou sans date de retrait → supprime l'événement existant.
    func sync(commande: Commande, clientNom: String?, calendar: EKCalendar) throws {
        let existing = findEvent(commandeId: commande.id, calendar: calendar)

        guard let date = commande.date_retrait,
              commande.statut != .annulee else {
            // Plus de date / annulée → supprimer
            if let e = existing {
                try store.remove(e, span: .thisEvent, commit: true)
            }
            return
        }

        let event = existing ?? EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title(commande: commande, clientNom: clientNom)
        event.startDate = date
        event.endDate = date
        event.isAllDay = true
        event.url = URL(string: "\(Self.urlScheme)://commande/\(commande.id.uuidString)")
        event.notes = notes(commande: commande)

        try store.save(event, span: .thisEvent, commit: true)
    }

    func remove(commandeId: UUID, calendar: EKCalendar) throws {
        if let e = findEvent(commandeId: commandeId, calendar: calendar) {
            try store.remove(e, span: .thisEvent, commit: true)
        }
    }

    /// Supprime tout événement HappyKreations (identifié par son URL custom
    /// `happykreations://commande/<uuid>`) dont l'UUID n'est pas dans la liste
    /// fournie. Utilisé pour nettoyer les commandes supprimées en BDD.
    func removeOrphans(existingCommandeIds: Set<UUID>, calendar: EKCalendar) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let end = cal.date(byAdding: .year, value: 2, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let scheme = Self.urlScheme
        let prefix = "\(scheme)://commande/"
        for event in store.events(matching: predicate) {
            guard let url = event.url?.absoluteString, url.hasPrefix(prefix) else { continue }
            let uuidStr = String(url.dropFirst(prefix.count))
            guard let id = UUID(uuidString: uuidStr) else { continue }
            if !existingCommandeIds.contains(id) {
                try? store.remove(event, span: .thisEvent, commit: true)
            }
        }
    }

    /// Cherche l'événement appartenant à une commande dans une fenêtre temporelle large.
    private func findEvent(commandeId: UUID, calendar: EKCalendar) -> EKEvent? {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let end = cal.date(byAdding: .year, value: 2, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        guard let target = URL(string: "\(Self.urlScheme)://commande/\(commandeId.uuidString)") else {
            return nil
        }
        return store.events(matching: predicate).first { $0.url == target }
    }

    // MARK: - Formatage

    private func title(commande: Commande, clientNom: String?) -> String {
        let prefix: String
        switch commande.statut {
        case .confirmee:     prefix = "🎁"
        case .en_production: prefix = "🍫"
        case .prete:         prefix = "📦"
        case .livree:        prefix = "✅"
        default:             prefix = "📝"
        }
        let nom = clientNom ?? "Client"
        if let evt = commande.type_evenement, !evt.isEmpty {
            return "\(prefix) \(nom) — \(evt)"
        }
        return "\(prefix) \(nom)"
    }

    private func notes(commande: Commande) -> String {
        var lines: [String] = []
        lines.append("Statut : \(commande.statut.libelle)")
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = Locale(identifier: "fr_FR")
        let total = fmt.string(from: commande.total as NSNumber) ?? "—"
        let acompte = fmt.string(from: commande.acompte as NSNumber) ?? "—"
        lines.append("Total : \(total) — Acompte : \(acompte)")
        if let e = commande.type_evenement, !e.isEmpty {
            lines.append("Événement : \(e)")
        }
        if let n = commande.notes, !n.isEmpty {
            lines.append("")
            lines.append(n)
        }
        lines.append("")
        lines.append("HappyKreations")
        return lines.joined(separator: "\n")
    }
}
