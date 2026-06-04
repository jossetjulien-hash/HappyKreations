import Foundation
import EventKit

/// Crée des rappels dans l'app Rappels d'Apple via EventKit.
/// Les rappels remontent automatiquement sur tous les appareils via iCloud.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    let store = EKEventStore()

    /// Identifiant de la source (compte) préférée pour les rappels — auto par défaut.
    /// Auto : préfère une source iCloud (ex. josset.julien@icloud.com) sur le
    /// compte pro éventuellement marqué par défaut côté macOS.
    static let preferredSourceKey = "happykreations.remindersSourceId"

    private init() {}

    var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                return try await store.requestFullAccessToReminders()
            } else {
                return try await store.requestAccess(to: .reminder)
            }
        } catch {
            return false
        }
    }

    /// Listes de rappels disponibles, groupées par compte (source).
    /// Utilisé par l'écran Réglages pour choisir explicitement le compte.
    struct SourceOption: Identifiable, Hashable {
        let id: String         // sourceIdentifier
        let title: String      // ex. "iCloud", "Exchange" — affiché à l'utilisateur
        let calendarId: String // identifiant du calendrier par défaut de cette source
    }

    func availableSources() -> [SourceOption] {
        let cals = store.calendars(for: .reminder)
        // Une option par source, calendrier par défaut = premier calendrier de cette source.
        var seen: [String: SourceOption] = [:]
        for cal in cals {
            let sid = cal.source.sourceIdentifier
            if seen[sid] == nil {
                seen[sid] = SourceOption(
                    id: sid, title: cal.source.title, calendarId: cal.calendarIdentifier)
            }
        }
        return Array(seen.values).sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    /// Calendrier à utiliser pour un nouveau rappel.
    /// 1. Préférence utilisateur (Réglages) si encore valide.
    /// 2. Sinon, premier calendrier d'une source dont le titre contient "icloud".
    /// 3. Sinon, calendrier par défaut macOS/iOS.
    private func targetCalendar() -> EKCalendar? {
        let cals = store.calendars(for: .reminder)

        if let preferred = UserDefaults.standard.string(forKey: Self.preferredSourceKey),
           let cal = cals.first(where: { $0.source.sourceIdentifier == preferred }) {
            return cal
        }
        if let icloud = cals.first(where: { $0.source.title.lowercased().contains("icloud") }) {
            return icloud
        }
        return store.defaultCalendarForNewReminders()
    }

    /// Crée un rappel et le sauvegarde dans la liste choisie (cf. targetCalendar).
    /// `dueDate` est interprété en heure locale.
    @discardableResult
    func add(title: String, notes: String? = nil, dueDate: Date? = nil) async throws -> Bool {
        if !hasAccess {
            let granted = await requestAccess()
            guard granted else { return false }
        }
        guard let calendar = targetCalendar() else {
            throw NSError(domain: "RemindersService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Aucune liste de rappels disponible."])
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        if let due = dueDate {
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            reminder.dueDateComponents = comps
            let alarm = EKAlarm(absoluteDate: due)
            reminder.addAlarm(alarm)
        }
        try store.save(reminder, commit: true)
        return true
    }
}
