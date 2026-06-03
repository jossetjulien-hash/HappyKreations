import Foundation
import Supabase

/// Client Supabase partagé + encodeur/décodeur tolérant aux dates (`date` et `timestamptz`).
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        let options = SupabaseClientOptions(
            db: SupabaseClientOptions.DatabaseOptions(
                encoder: Self.encoder,
                decoder: Self.decoder
            )
        )
        self.client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: options
        )
    }

    // MARK: - Encodage / décodage des dates

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let v = isoFrac.date(from: s) { return v }
            if let v = iso.date(from: s) { return v }
            if let v = dateOnly.date(from: s) { return v }
            throw DecodingError.dataCorruptedError(in: c,
                debugDescription: "Date Supabase invalide: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            // Encode toujours en ISO8601 — accepté par Postgres pour `date` comme pour `timestamptz`.
            var c = encoder.singleValueContainer()
            try c.encode(isoFrac.string(from: date))
        }
        return e
    }()
}

// MARK: - Helpers de formatage côté UI

enum DateFormat {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func iso(_ date: Date) -> String { yyyyMMdd.string(from: date) }
}

// MARK: - Décodage tolérant des numériques
// Postgrest sérialise les colonnes `numeric(...)` comme chaînes pour préserver la précision.
// Ces helpers permettent de décoder indifféremment un nombre JSON ou une chaîne numérique.
extension KeyedDecodingContainer {
    func decodeDouble(_ key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key), let d = Double(s) { return d }
        throw DecodingError.typeMismatch(
            Double.self,
            .init(codingPath: codingPath + [key],
                  debugDescription: "Valeur non convertible en Double pour la clé \(key.stringValue)")
        )
    }

    func decodeDoubleIfPresent(_ key: Key) -> Double? {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        return nil
    }
}
