// Edge Function : webhook-stripe
// Endpoint signé pour Stripe. À `checkout.session.completed`, enregistre le paiement
// et passe la commande en `confirmee`.

import Stripe from "https://esm.sh/stripe@16?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method_not_allowed", { status: 405 });
  const sig = req.headers.get("stripe-signature");
  const raw = await req.text();
  if (!sig) return new Response("missing_signature", { status: 400 });

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw, sig, Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
    );
  } catch (err) {
    console.error("Signature invalide :", err);
    return new Response("invalid_signature", { status: 400 });
  }

  try {
    if (event.type === "checkout.session.completed") {
      const s = event.data.object as Stripe.Checkout.Session;
      const commande_id = s.metadata?.commande_id;
      if (!commande_id) {
        console.warn("Session sans commande_id", s.id);
        return new Response("ok"); // ne pas rejouer
      }
      const montant = (s.amount_total ?? 0) / 100;

      await db.from("paiement").insert({
        commande_id,
        montant,
        moyen: "stripe",
        statut: "reussi",
        stripe_session_id: s.id,
        stripe_payment_intent: typeof s.payment_intent === "string"
          ? s.payment_intent
          : s.payment_intent?.id ?? null,
      });
      await db.from("commande").update({ statut: "confirmee" }).eq("id", commande_id);
    }
    // checkout.session.expired / payment_intent.payment_failed → on log et on laisse
    return new Response("ok");
  } catch (err) {
    console.error("Erreur webhook :", err);
    return new Response("internal_error", { status: 500 });
  }
});
