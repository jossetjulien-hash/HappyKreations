# Backend — Supabase Edge Functions

Fonctions Deno/TypeScript déployées sur Supabase. **Toutes les clés secrètes vivent ici** (secrets des functions), jamais dans l'app ni la page web.

Secrets attendus : `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `ANTHROPIC_API_KEY`, et (phases 3-4) `ORDER_IMAP_*`, `META_APP_SECRET`, `META_VERIFY_TOKEN`, `META_PAGE_ACCESS_TOKEN`.

---

## 1. `creer-paiement` — appelée par le formulaire (phase 2)

**Entrée** (POST JSON) : `{ client, date_retrait, type_evenement, lignes:[{produit_id, quantite, declinaison}], notes }`

**Logique**
1. Vérifier la **disponibilité de la date** : `capacite_jour` non `bloque`, somme des unités déjà prévues < `plafond_unites`, et `date_retrait >= today + delai_mini_jours`. Sinon → `409`.
2. Créer/retrouver le `client`, créer la `commande` (`canal='formulaire'`, `statut='a_confirmer'`) + ses `commande_ligne` (prix repris depuis `produit`).
3. Calculer l'acompte = `total * config.acompte_pourcent / 100`.
4. Créer une **Stripe Checkout Session** (mode `payment`, montant = acompte) avec `metadata.commande_id`.
5. Retourner `{ checkout_url }`.

```ts
import Stripe from "https://esm.sh/stripe@16?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  const body = await req.json();
  // 1. valider la date (capacite_jour, delai_mini_jours) -> sinon 409
  // 2. upsert client, insert commande + commande_ligne
  // 3. lire total + acompte_pourcent -> acompte
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "eur",
        product_data: { name: "Acompte commande" },
        unit_amount: Math.round(acompteEnEuros * 100),
      },
    }],
    metadata: { commande_id: commandeId },
    success_url: `${origin}/merci`,
    cancel_url: `${origin}/`,
  });
  return Response.json({ checkout_url: session.url });
});
```

---

## 2. `webhook-stripe` — appelée par Stripe (phase 2)

**Logique** : vérifier la signature (`STRIPE_WEBHOOK_SECRET`), sur `checkout.session.completed` → insérer un `paiement` (`moyen='stripe'`, `statut='reussi'`, `stripe_session_id`, `stripe_payment_intent`) et passer la commande en `confirmee`.

```ts
Deno.serve(async (req) => {
  const sig = req.headers.get("stripe-signature")!;
  const raw = await req.text();
  const event = await stripe.webhooks.constructEventAsync(
    raw, sig, Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
  );
  if (event.type === "checkout.session.completed") {
    const s = event.data.object;
    const commande_id = s.metadata.commande_id;
    await db.from("paiement").insert({
      commande_id, montant: s.amount_total / 100, moyen: "stripe",
      statut: "reussi", stripe_session_id: s.id, stripe_payment_intent: s.payment_intent,
    });
    await db.from("commande").update({ statut: "confirmee" }).eq("id", commande_id);
  }
  return new Response("ok");
});
```
> Toujours répondre `200` rapidement ; ne jamais confirmer une commande sur le seul retour navigateur.

---

## 3. `parse-claude` — extraction structurée (phases 1, 3, 4)

Transforme un message libre en commande structurée. Utilisée par la **saisie assistée** (app), `ingest-email` et `webhook-messenger`.

**Entrée** : `{ texte, canal }` → **Sortie** : le JSON défini au cahier des charges (§8).

```ts
const res = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: {
    "content-type": "application/json",
    "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
    "anthropic-version": "2023-06-01",
  },
  body: JSON.stringify({
    model: "claude-sonnet-4-20250514",
    max_tokens: 1000,
    system: "Tu extrais une commande depuis un message client. Réponds UNIQUEMENT par un JSON valide, sans texte ni balises. Schéma: {client:{nom,contact}, canal, type_evenement, date_evenement, date_retrait, lignes:[{produit,quantite,declinaison}], notes}. Mets null si une info est absente.",
    messages: [{ role: "user", content: texte }],
  }),
});
const data = await res.json();
const json = JSON.parse(data.content.find((b) => b.type === "text").text);
```
> Ne jamais importer en aveugle : le résultat alimente `commande_entrante` (statut `a_valider`) pour validation humaine (sauf formulaire, déjà structuré).

---

## 4. `ingest-email` — cron (phase 3)

Planifiée (Supabase cron). Relève l'adresse dédiée (IMAP ou API du fournisseur de mail), et pour chaque nouveau message : `parse-claude` → insert `commande_entrante` (`canal='email'`, `message_brut`, `donnee_extraite`).

---

## 5. `webhook-messenger` — appelée par Meta (phase 4)

- `GET` : répondre au défi de vérification (`hub.challenge` vs `META_VERIFY_TOKEN`).
- `POST` : vérifier la signature `X-Hub-Signature-256` (`META_APP_SECRET`), extraire le texte du message de la Page, `parse-claude` → insert `commande_entrante` (`canal='messenger'`).
> Prérequis externe : app Meta + permission `pages_messaging` + **vérification business + revue de l'app** (délai long, à lancer tôt).
