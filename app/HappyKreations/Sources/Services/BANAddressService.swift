import Foundation

/// Wrapper de la Base Adresse Nationale française (api-adresse.data.gouv.fr).
/// Gratuit, sans clé. Limité à La Réunion (codes postaux 974xx) pour
/// éviter d'avoir des suggestions de métropole quand on tape « rue de la Plage ».
enum BANAddressService {
    /// Suggestion d'adresse retournée par la BAN.
    struct Suggestion: Identifiable, Hashable {
        let id: String                  // BAN id
        let label: String               // « 12 Rue des Chocolatiers 97400 Saint-Denis »
        let postcode: String?
        let city: String?
        let latitude: Double
        let longitude: Double
    }

    /// Recherche d'adresses à partir d'une saisie utilisateur. Renvoie [] si
    /// `query` trop court ou si erreur réseau (jamais d'exception remontée).
    static func search(_ query: String) async -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        var comps = URLComponents(string: "https://api-adresse.data.gouv.fr/search/")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "6"),
            // Filtre géographique : centre de La Réunion + rayon ~70 km.
            // Permet à la BAN de privilégier les adresses locales.
            URLQueryItem(name: "lat", value: "-21.115"),
            URLQueryItem(name: "lon", value: "55.536"),
        ]
        guard let url = comps.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(BANResponse.self, from: data)
            return resp.features.compactMap { f -> Suggestion? in
                guard f.geometry.coordinates.count == 2 else { return nil }
                let postcode = f.properties.postcode
                // Filtre dur : on ne garde que les adresses 974xx (La Réunion).
                guard postcode?.hasPrefix("974") == true else { return nil }
                return Suggestion(
                    id: f.properties.id,
                    label: f.properties.label,
                    postcode: postcode,
                    city: f.properties.city,
                    latitude: f.geometry.coordinates[1],
                    longitude: f.geometry.coordinates[0])
            }
        } catch {
            return []
        }
    }

    // MARK: - DTO BAN

    private struct BANResponse: Decodable {
        let features: [Feature]
    }
    private struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry
    }
    private struct Properties: Decodable {
        let id: String
        let label: String
        let postcode: String?
        let city: String?
    }
    private struct Geometry: Decodable {
        let coordinates: [Double]       // [longitude, latitude]
    }
}
