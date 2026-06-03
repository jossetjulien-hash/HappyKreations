import Foundation
import EventKit

/// Crée des rappels dans l'app Rappels d'Apple via EventKit.
/// Les rappels remontent automatiquement sur tous les appareils via iCloud.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    let store = EKEventStore()

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

    /// Crée un rappel et le sauvegarde dans la liste de rappels par défaut.
    /// `dueDate` est interprété en heure locale.
    @discardableResult
    func add(title: String, notes: String? = nil, dueDate: Date? = nil) async throws -> Bool {
        if !hasAccess {
            let granted = await requestAccess()
            guard granted else { return false }
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()
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
