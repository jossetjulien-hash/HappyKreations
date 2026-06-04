// Edge Function : webhook-stripe
// Endpoint signé pour Stripe. À `checkout.session.completed`, enregistre le paiement
// et passe la commande en `confirmee`.

import Stripe from "https://esm.sh/stripe@16?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendCommandeConfirmation } from "../_shared/email.ts";

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

      // Email de confirmation au client (best-effort, n'interrompt jamais le webhook).
      try {
        await envoyerConfirmation(commande_id);
      } catch (mailErr) {
        console.error("Email confirmation (non bloquant) :", mailErr);
      }
    }
    // checkout.session.expired / payment_intent.payment_failed → on log et on laisse
    return new Response("ok");
  } catch (err) {
    console.error("Erreur webhook :", err);
    return new Response("internal_error", { status: 500 });
  }
});

/** Récupère la commande + client + lignes et déclenche l'email de confirmation. */
async function envoyerConfirmation(commande_id: string): Promise<void> {
  const { data: cmd, error } = await db.from("commande")
    .select(`
      total, acompte, date_retrait, type_evenement, allergies, message_gravure, couleur,
      client:client_id ( nom, email ),
      lignes:commande_ligne ( quantite, declinaison, produit:produit_id ( nom ) )
    `)
    .eq("id", commande_id)
    .single();
  if (error || !cmd) {
    console.warn("Commande introuvable pour email :", commande_id, error);
    return;
  }

  const client = cmd.client as { nom?: string; email?: string } | null;
  if (!client?.email) return; // pas d'email → rien à envoyer

  const { data: configRows } = await db.from("config")
    .select("cle, valeur").eq("cle", "nom_atelier");
  const nomAtelier = configRows?.[0]?.valeur ?? "HappyKreations";

  const lignes = (cmd.lignes as Array<{
    quantite: number; declinaison: string | null; produit: { nom: string } | null;
  }> ?? []).map((l) => ({
    nom: l.produit?.nom ?? "Produit",
    quantite: l.quantite,
    declinaison: l.declinaison,
  }));

  await sendCommandeConfirmation({
    clientNom: client.nom ?? "",
    clientEmail: client.email,
    dateRetrait: cmd.date_retrait ?? null,
    typeEvenement: cmd.type_evenement ?? null,
    total: Number(cmd.total ?? 0),
    acompte: Number(cmd.acompte ?? 0),
    lignes,
    allergies: (cmd.allergies as string[]) ?? [],
    messageGravure: cmd.message_gravure ?? null,
    couleur: cmd.couleur ?? null,
    nomAtelier,
    commandeId: commande_id,
  });
}
