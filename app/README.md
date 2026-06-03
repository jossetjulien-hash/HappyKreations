# HappyKreations — App SwiftUI (iOS 17+ / macOS 14+)

Une seule codebase, deux cibles. Les vues s'adaptent automatiquement à la plateforme (sidebar sur macOS / iPadOS, tab bar sur iPhone).

## Structure

```
app/
├── project.yml                     # config XcodeGen (générateur du .xcodeproj)
└── HappyKreations/
    ├── Info.plist
    ├── HappyKreations.entitlements
    ├── Resources/
    │   └── Assets.xcassets
    └── Sources/
        ├── App/                    # entrée + config
        │   ├── HappyKreationsApp.swift
        │   └── Config.swift        # URL Supabase + anon key
        ├── Models/                 # struct Codable miroirs du schéma
        ├── Services/               # client Supabase, Repository, parse-claude
        ├── Stores/                 # AuthStore + AppStore (ObservableObject)
        └── Views/                  # vues SwiftUI groupées par module
```

## Premier lancement

```bash
# 1. Installer XcodeGen (une fois)
brew install xcodegen

# 2. Générer le projet Xcode
cd app
xcodegen generate

# 3. Ouvrir Xcode et lancer
open HappyKreations.xcodeproj
```

Sur la première compilation, Xcode résout automatiquement la dépendance Swift Package `supabase-swift` (≥ 2.20).

## Signature & distribution

- Un **Apple Developer Program** (~99 €/an) est requis pour installer durablement sur iPhone et passer par TestFlight. Sans, un build signé en compte gratuit expire en 7 jours.
- Dans Xcode → Signing & Capabilities, sélectionner l'équipe puis cocher *Automatically manage signing*.
- L'identifiant de bundle par défaut est `com.happykreations.app` — à modifier si nécessaire.

## Configuration Supabase

Les valeurs **publiques** (URL + clé `anon`/publishable) sont stockées dans `Sources/App/Config.swift`. Aucune clé secrète (service_role, Stripe, Anthropic) n'est embarquée — elles vivent uniquement dans les secrets des Edge Functions.

## Comptes utilisateurs

Créer les **deux comptes** dans Supabase → Authentication → Users, puis insérer dans `app_user` :

```sql
insert into app_user (id, nom, role) values
  ('<uuid auth.users>', 'Prénom Nom', 'staff');
```

Sans cette ligne, les écritures de `created_by` resteront nulles.

## Tests à faire après installation

1. Se connecter avec un compte.
2. Créer une matière, un produit, une recette.
3. Créer une commande manuelle → vérifier le total calculé.
4. Passer la commande en *Confirmée* → vérifier que la réservation apparaît sur `v_matiere_disponible`.
5. Passer en *En production* → vérifier que `mouvement_stock` reçoit une `sortie` et que `stock_actuel` diminue.
6. Encaisser un paiement → vérifier le tableau de bord.
7. **Multi-appareils** : ouvrir l'app sur un second appareil (avec l'autre compte) et vérifier que la commande créée apparaît en temps réel via Realtime.
