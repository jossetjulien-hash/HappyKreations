# HappyKreations

Outil de gestion pour une micro-entreprise artisanale (coffrets de chocolats & cornets de meringues) : commandes, agenda, stock, recettes, fournisseurs, paiements.

## Monorepo

```
.
├── docs/              # spécifications (cahier des charges, SQL, archi)
├── app/               # application SwiftUI (iOS 17+ / macOS 14+)
├── web-form/          # formulaire de commande public (Next.js)
└── supabase/
    ├── migrations/    # schéma versionné
    └── functions/     # Edge Functions Deno/TS
```

## Projet Supabase

- **URL** : `https://mhbakgmqyegwyuzofzbf.supabase.co`
- **Project ref** : `mhbakgmqyegwyuzofzbf`
- **Région** : `eu-west-3`

Le schéma a déjà été appliqué via migration `00000000000001_initial_schema`.

## Démarrage

### 1. Variables d'environnement
```bash
cp .env.example .env
# remplir les secrets côté Edge Functions
```

### 2. Application SwiftUI
```bash
cd app
# Générer le projet Xcode (XcodeGen requis : brew install xcodegen)
xcodegen generate
open HappyKreations.xcodeproj
```
Configurer la signature (Apple Developer ~99 €/an) puis Run.

### 3. Formulaire web
```bash
cd web-form
npm install
npm run dev
```

### 4. Edge Functions (Phase 2)
```bash
supabase link --project-ref mhbakgmqyegwyuzofzbf
supabase functions deploy creer-paiement
supabase functions deploy webhook-stripe
supabase secrets set STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=...
```

### 5. Comptes utilisateurs
Dans le dashboard Supabase → Authentication → créer les **deux comptes** (email + mdp), puis insérer une ligne dans `app_user` pour chacun (id = `auth.users.id`).

## Phases

1. **Phase 1 — Cœur** : app SwiftUI complète ✅
2. **Phase 2 — Formulaire + Stripe** : web-form public (à déployer).

> Les Phases 3 (auto-import email) et 4 (auto-import Messenger) du cahier des charges initial nécessitaient une IA pour parser les messages libres — elles ont été **retirées du scope**. Les commandes entrent désormais soit en **saisie manuelle** (app), soit via le **formulaire en ligne** (Phase 2, structuré, sans IA).

Voir [`docs/00-README-claude-code.md`](docs/00-README-claude-code.md) pour la spec d'origine (historique).
