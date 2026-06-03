# HappyKreations — Formulaire de commande

Formulaire public Next.js qui :
1. Lit le catalogue (`produit` où `visible_formulaire`) + capacités (`capacite_jour`) via la clé Supabase `anon`.
2. À la validation, appelle l'Edge Function `creer-paiement` qui crée la commande et une session Stripe Checkout.
3. Redirige le client vers Stripe pour l'acompte. Le webhook `webhook-stripe` confirme la commande côté serveur.

## Lancer en local
```bash
cp .env.example .env.local
npm install
npm run dev
```

## Déploiement
Vercel ou Cloudflare Pages. Renseigner les variables `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL`.

Côté Edge Function `creer-paiement` : configurer les secrets `STRIPE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
Côté Stripe : webhook vers `…/functions/v1/webhook-stripe`, secret dans `STRIPE_WEBHOOK_SECRET`.
