import SwiftUI

// MARK: - Charte graphique HappyKreations (Édition 2026)

extension Color {
    /// Rose Poudré — couleur primaire.
    static let hkRose      = Color(red: 0.906, green: 0.710, blue: 0.722) // #E7B5B8
    /// Rose profond — accents soutenus / liens.
    static let hkRoseDeep  = Color(red: 0.788, green: 0.514, blue: 0.533) // #C98388
    /// Vert Sauge — couleur secondaire.
    static let hkSage      = Color(red: 0.663, green: 0.737, blue: 0.631) // #A9BCA1
    /// Vert sauge profond.
    static let hkSageDeep  = Color(red: 0.494, green: 0.580, blue: 0.478) // #7E947A
    /// Pêche Douce — accent chaud.
    static let hkPeach     = Color(red: 0.957, green: 0.824, blue: 0.690) // #F4D2B0
    /// Lavande — accent frais.
    static let hkLavender  = Color(red: 0.812, green: 0.769, blue: 0.878) // #CFC4E0
    /// Crème — fond / respiration.
    static let hkCream     = Color(red: 0.984, green: 0.965, blue: 0.937) // #FBF6EF
    /// Crème profond.
    static let hkCreamDeep = Color(red: 0.953, green: 0.918, blue: 0.863) // #F3EADC
    /// Encre Douce — texte / contraste.
    static let hkInk       = Color(red: 0.310, green: 0.290, blue: 0.271) // #4F4A45
}

extension Font {
    /// Titre serif (Fraunces si dispo, sinon serif système « New York »).
    static func hkTitle(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Fraunces", size: size).weight(weight)
    }

    /// Accent manuscrit (Caveat si dispo, sinon arrondi système).
    static func hkScript(_ size: CGFloat) -> Font {
        .custom("Caveat", size: size)
    }
}

extension View {
    /// Applique la teinte de marque à toute la hiérarchie.
    func hkTheme() -> some View {
        self.tint(.hkRoseDeep)
    }
}
