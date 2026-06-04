import SwiftUI

/// Vignette de la photo de référence d'une commande, avec placeholder
/// discret si aucune photo n'est jointe. Utilisée dans la liste des commandes,
/// le tableau de bord et la fiche commande.
struct CommandePhotoThumb: View {
    let url: String?
    var size: CGFloat = 48
    var showPlaceholder: Bool = true

    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        Color.secondary.opacity(0.08)
                    @unknown default:
                        placeholder
                    }
                }
            } else if showPlaceholder {
                placeholder
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.06)
            Image(systemName: "photo")
                .font(.system(size: size * 0.32))
                .foregroundStyle(.secondary)
        }
    }
}
