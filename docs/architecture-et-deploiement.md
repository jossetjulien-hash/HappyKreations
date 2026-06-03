# Architecture & déploiement

## Structure du dépôt (monorepo GitHub)

```
.
├── docs/                       # les documents de spec (ce dossier)
│   ├── 00-README-claude-code.md
│   ├── cahier-des-charges-appli-gestion.md
│   ├── schema-supabase.sql
│   ├── backend-edge-functions.md
│   └── architecture-et-deploiement.md
├── app/                        # SwiftUI (iOS 17+ / macOS 14+)
│   ├── HappyKreations.xcodeproj
│   └── Sources/                # vues, modèles, client Supabase, cache local
├── web-form/                   # formulaire de commande public
│   └── ...                     # Next.js (recommandé) ou statique + JS
└── supabase/
    ├── migrations/             # schema-supabase.sql versionné ici
    └── functions/              # edge functions (voir backend-edge-functions.md)
        ├── creer-paiement/
        ├── webhook-stripe/
        ├── parse-claude/
        ├── ingest-email/
        └── webhook-messenger/
```

## Flux de données (rappel)

- **App** (clients authentifiés) ⇄ **Supabase** (Postgres + Realtime), avec cache local offline.
- **Formulaire** (anon, lecture catalogue/capacités) → **Edge Function** (service_role) pour créer commande + session Stripe.
- **Stripe / Meta** → **Edge Functions** (webhooks signés) → Supabase.
- **Claude API** appelée uniquement côté Edge Functions (`parse-claude`).

## Variables d'environnement

`.env.example` à créer à la racine (et secrets équivalents côté Supabase Functions / Vercel) :

```
# Supabase (app + web-form : URL + clé ANON seulement)
SUPABASE_URL=
SUPABASE_ANON_KEY=

# Réservé aux Edge Functions (NE JAMAIS exposer côté client)
SUPABASE_SERVICE_ROLE_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
ANTHROPIC_API_KEY=

# Phase 3 (email)
ORDER_IMAP_HOST=
ORDER_IMAP_USER=
ORDER_IMAP_PASSWORD=

# Phase 4 (Messenger)
META_APP_SECRET=
META_VERIFY_TOKEN=
META_PAGE_ACCESS_TOKEN=
```

Règle : `SERVICE_ROLE`, `STRIPE_SECRET`, `ANTHROPIC`, `META_*` ne vivent **que** dans les secrets des Edge Functions. L'app et la page web n'utilisent que `SUPABASE_URL` + `SUPABASE_ANON_KEY`.

## Étapes de déploiement

### Supabase (déjà créé)
1. `supabase link --project-ref <ref>`
2. Placer `schema-supabase.sql` dans `supabase/migrations/` → `supabase db push`.
3. `supabase functions deploy <nom>` pour chaque fonction.
4. `supabase secrets set STRIPE_SECRET_KEY=... ANTHROPIC_API_KEY=... ...`
5. Créer les **deux comptes** dans Auth ; insérer leur ligne dans `app_user`.
6. Planifier `ingest-email` (cron) en phase 3.

### GitHub (déjà créé)
- Pousser le monorepo ; une branche par phase.
- (Optionnel) CI : lint + build de `web-form`, `supabase functions deploy` sur merge.

### Formulaire web (phase 2)
- Déployer `web-form/` sur **Vercel** ou **Cloudflare Pages**.
- Configurer le webhook Stripe vers `…/functions/v1/webhook-stripe` et récupérer `STRIPE_WEBHOOK_SECRET`.

### App iOS/macOS
- Ouvrir `app/` dans **Xcode**, configurer la signature.
- **Compte Apple Developer (~99 €/an)** requis pour installer durablement sur iPhone et passer par **TestFlight**.

## Ordre conseillé pour Claude Code
Schéma Supabase → types → échafaudage monorepo → **phase 1** (app cœur) → phase 2 (formulaire + Stripe) → phase 3 (email) → phase 4 (Messenger). Voir `00-README-claude-code.md` pour les definitions of done.
