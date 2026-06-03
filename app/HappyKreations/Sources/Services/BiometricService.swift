import Foundation
import LocalAuthentication

/// Wrapper sur LocalAuthentication pour Face ID / Touch ID.
enum BiometricService {
    enum Kind {
        case none, touchID, faceID, opticID

        var libelle: String {
            switch self {
            case .none:     return "Biométrie"
            case .touchID:  return "Touch ID"
            case .faceID:   return "Face ID"
            case .opticID:  return "Optic ID"
            }
        }

        var icon: String {
            switch self {
            case .none:     return "lock.shield"
            case .touchID:  return "touchid"
            case .faceID:   return "faceid"
            case .opticID:  return "opticid"
            }
        }
    }

    /// Type de biométrie disponible sur l'appareil (ou .none si rien n'est configuré).
    static var available: Kind {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                    error: &error) else { return .none }
        switch ctx.biometryType {
        case .faceID:   return .faceID
        case .touchID:  return .touchID
        case .opticID:  return .opticID
        default:        return .none
        }
    }

    /// Lance la demande biométrique. Fallback automatique sur le code de l'appareil.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Utiliser le code"
        do {
            return try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
