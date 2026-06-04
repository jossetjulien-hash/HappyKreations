// Edge Function : creer-lien-paiement
//
// Génère une URL de paiement Stripe Checkout pour une commande EXISTANTE.
// Appelée depuis l'app iOS (bouton "Partager le lien de paiement" sur la fiche
// commande), pour les commandes saisies à la main ou pour relancer un solde.
//
// POST JSON :
// {
//   commande_id: string,           // uuid de la commande
//   montant?: number,              // EUR, défaut = acompte si pas encore versé,
//                                  // sinon reste dû
//   motif?: "acompte" | "solde" | "libre"  // libellé sur Stripe
// }
//
// Réponse : { checkout_url: string }
//
// Sécurité : la fonction est appelée depuis l'app authentifiée (verify_jwt
// activé). Le token JWT est validé par Supabase avant exécution.

import Stripe from "https://esm.sh/stripe@16?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleOptions } from "../_shared/cors.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  httpClient: Stripe.createFetchHttpClient(),
});
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function json(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { ...corsHeaders, "content-type": "application/json", ...(init.headers ?? {}) },
  });
}

Deno.serve(async (req) => {
  const pre = handleOptions(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, { status: 405 });

  try {
    const { commande_id, montant, motif } = await req.json();
    if (!commande_id) return json({ error: "commande_id_requis" }, { status: 400 });

    // Récupère la commande + le client pour le contexte sur Stripe
    const { data: cmd, error } = await db.from("commande")
      .select(`
        id, total, acompte, statut,
        client:client_id ( nom, email )
      `)
      .eq("id", commande_id)
      .single();
    if (error || !cmd) return json({ error: "commande_introuvable" }, { status: 404 });

    // Calcul des paiements déjà reçus (pour calculer le solde)
    const { data: paiements } = await db.from("paiement")
      .select("montant, statut")
      .eq("commande_id", commande_id);
    const dejaPaye = (paiements ?? [])
      .filter((p) => p.statut === "reussi")
      .reduce((s, p) => s + Number(p.montant ?? 0), 0);

    // Détermine le montant à demander
    const total = Number(cmd.total ?? 0);
    const acompte = Number(cmd.acompte ?? 0);
    let montantFinal: number;
    let libelle: string;

    if (typeof montant === "number" && montant > 0) {
      // Montant explicite (priorité)
      montantFinal = Math.round(montant * 100) / 100;
      libelle = motif === "solde" ? "Solde" : motif === "acompte" ? "Acompte" : "Paiement";
    } else if (dejaPaye < 0.01 && acompte > 0) {
      // Aucun paiement encore → on prend l'acompte
      montantFinal = acompte;
      libelle = "Acompte";
    } else {
      // Sinon le reste dû
      montantFinal = Math.max(0, total - dejaPaye);
      libelle = "Solde";
    }

    if (montantFinal <= 0) {
      return json({ error: "montant_invalide", detail: "Cette commande est déjà soldée." },
                  { status: 409 });
    }

    const client = cmd.client as { nom?: string; email?: string } | null;
    const { data: configRows } = await db.from("config")
      .select("cle, valeur").eq("cle", "nom_atelier");
    const nomAtelier = configRows?.[0]?.valeur ?? "HappyKreations";

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer_email: client?.email ?? undefined,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "eur",
          product_data: {
            name: `${libelle} commande ${nomAtelier}`,
            description: client?.nom ? `Pour ${client.nom}` : undefined,
          },
          unit_amount: Math.round(montantFinal * 100),
        },
      }],
      metadata: {
        commande_id,
        kind: libelle.toLowerCase(),
      },
      // L'URL de retour pointe sur la page web /merci (web-form Vercel) avec
      // l'id de la commande. Si pas encore déployé, le client verra une 404
      // mais le paiement aura été enregistré côté Stripe + webhook.
      success_url: `https://commande.happykreations.fr/merci?id=${commande_id}`,
      cancel_url: `https://commande.happykreations.fr/?annule=1`,
    });

    return json({
      checkout_url: session.url,
      montant: montantFinal,
      libelle,
    });
  } catch (err) {
    console.error("Erreur creer-lien-paiement :", err);
    return json({ error: String((err as Error).message ?? err) }, { status: 500 });
  }
});
