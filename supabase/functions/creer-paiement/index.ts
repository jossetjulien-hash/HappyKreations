// Edge Function : creer-paiement
// Appelée par le formulaire web. Crée la commande puis une session Stripe Checkout
// pour l'acompte. Renvoie l'URL de paiement hébergée par Stripe.
//
// POST JSON :
// {
//   client: { nom, telephone?, email?, messenger? },
//   date_retrait: "AAAA-MM-JJ",
//   date_evenement?: "AAAA-MM-JJ",
//   type_evenement?: string,
//   lignes: [{ produit_id, quantite, declinaison? }],
//   notes?: string,
//   origin?: string  // URL du site appelant pour success/cancel
// }

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
    const body = await req.json();
    const {
      client, date_retrait, date_evenement, type_evenement, lignes, notes,
      allergies, message_gravure, couleur, photo_ref_url, code_promo_id,
      mode_remise, zone_livraison_id, adresse_livraison, latitude, longitude, origin,
    } = body;
    if (!client?.nom || !date_retrait || !Array.isArray(lignes) || lignes.length === 0) {
      return json({ error: "payload_incomplet" }, { status: 400 });
    }
    // Normalise les champs structurés (jamais faire confiance au client).
    const allergiesClean = Array.isArray(allergies)
      ? allergies.filter((a) => typeof a === "string").slice(0, 20)
      : [];
    const gravureClean = typeof message_gravure === "string"
      ? message_gravure.slice(0, 200) : null;
    const couleurClean = typeof couleur === "string"
      ? couleur.slice(0, 80) : null;
    // L'URL est uploadée en amont par le client dans le bucket public
    // commandes-refs. On valide juste qu'elle pointe bien dessus.
    const photoRefClean = typeof photo_ref_url === "string"
      && photo_ref_url.includes("/storage/v1/object/public/commandes-refs/")
      ? photo_ref_url.slice(0, 500)
      : null;
    const modeRemiseClean = mode_remise === "livraison" ? "livraison" : "retrait";
    const adresseClean = typeof adresse_livraison === "string"
      ? adresse_livraison.slice(0, 300) : null;
    const latClean = typeof latitude === "number" && isFinite(latitude) ? latitude : null;
    const lonClean = typeof longitude === "number" && isFinite(longitude) ? longitude : null;

    // 1. Valider la disponibilité de la date
    const [{ data: capJour }, { data: configRows }] = await Promise.all([
      db.from("capacite_jour").select("*").eq("date", date_retrait).maybeSingle(),
      db.from("config").select("*").in("cle", ["delai_mini_jours", "acompte_pourcent"]),
    ]);

    if (capJour?.bloque) return json({ error: "date_bloquee" }, { status: 409 });

    const delaiMini = Number(configRows?.find((c) => c.cle === "delai_mini_jours")?.valeur ?? 7);
    const acomptePourcent = Number(
      configRows?.find((c) => c.cle === "acompte_pourcent")?.valeur ?? 30,
    );
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const dateRet = new Date(`${date_retrait}T00:00:00Z`);
    const diffJours = Math.floor((dateRet.getTime() - today.getTime()) / 86_400_000);
    if (diffJours < delaiMini) {
      return json({ error: "delai_minimum_non_respecte", delai_mini_jours: delaiMini }, { status: 409 });
    }

    // Vérifier plafond éventuel
    if (capJour?.plafond_unites) {
      const { data: commandesDuJour } = await db.from("commande")
        .select("id")
        .eq("date_retrait", date_retrait)
        .neq("statut", "annulee");
      const prevues = commandesDuJour?.length ?? 0;
      const nouvellesUnites = lignes.reduce((s, l) => s + Number(l.quantite || 0), 0);
      if (prevues + nouvellesUnites > capJour.plafond_unites) {
        return json({ error: "plafond_depasse" }, { status: 409 });
      }
    }

    // 2. Upsert client (par email ou messenger si fournis)
    let clientId: string;
    if (client.email) {
      const { data } = await db.from("client").select("id").eq("email", client.email).maybeSingle();
      if (data) clientId = data.id;
      else {
        const { data: inserted, error } = await db.from("client").insert(client).select("id").single();
        if (error) throw error;
        clientId = inserted.id;
      }
    } else {
      const { data: inserted, error } = await db.from("client").insert(client).select("id").single();
      if (error) throw error;
      clientId = inserted.id;
    }

    // 3. Récupérer les prix actuels des produits (jamais faire confiance au client)
    const produitIds = lignes.map((l) => l.produit_id);
    const { data: produits, error: prodErr } = await db.from("produit")
      .select("id, nom, prix_vente, visible_formulaire, actif, qte_min, qte_max").in("id", produitIds);
    if (prodErr) throw prodErr;
    const lignesValidees = lignes.map((l) => {
      const p = produits?.find((pp) => pp.id === l.produit_id);
      if (!p || !p.visible_formulaire || !p.actif) {
        throw new Error(`produit_indisponible:${l.produit_id}`);
      }
      const qte = Number(l.quantite);
      if (p.qte_min != null && qte < Number(p.qte_min)) {
        throw new Error(`qte_min:${p.nom}:${p.qte_min}`);
      }
      if (p.qte_max != null && qte > Number(p.qte_max)) {
        throw new Error(`qte_max:${p.nom}:${p.qte_max}`);
      }
      return { ...l, prix_unitaire: Number(p.prix_vente), nom: p.nom };
    });

    const totalBrut = lignesValidees.reduce((s, l) => s + l.prix_unitaire * Number(l.quantite), 0);

    // 4. Code promo (re-validation serveur — ne JAMAIS faire confiance au client)
    let remise = 0;
    let codePromoIdValide: string | null = null;
    if (typeof code_promo_id === "string" && code_promo_id.length > 0) {
      const { data: code } = await db.from("code_promo")
        .select("id, type, valeur, date_debut, date_fin, max_utilisations, utilisations, actif")
        .eq("id", code_promo_id).maybeSingle();
      const maintenant = new Date();
      if (code
          && code.actif
          && new Date(code.date_debut) <= maintenant
          && maintenant <= new Date(code.date_fin)
          && (code.max_utilisations == null || code.utilisations < code.max_utilisations)) {
        codePromoIdValide = code.id;
        remise = code.type === "fixe"
          ? Math.min(Number(code.valeur), totalBrut)
          : Math.round(totalBrut * Number(code.valeur)) / 100;
      }
      // Sinon on ignore silencieusement le code (l'utilisateur a saisi un
      // code expiré ou inexistant entre la validation client et le submit).
    }

    // Frais de livraison : re-validation depuis la BDD (jamais faire
    // confiance au tarif envoyé par le client).
    let fraisLivraison = 0;
    let zoneLivraisonIdValide: string | null = null;
    if (modeRemiseClean === "livraison" && typeof zone_livraison_id === "string" && zone_livraison_id.length > 0) {
      const { data: zone } = await db.from("zone_livraison")
        .select("id, tarif, actif")
        .eq("id", zone_livraison_id).maybeSingle();
      if (!zone || !zone.actif) {
        return json({ error: "zone_invalide" }, { status: 400 });
      }
      fraisLivraison = Math.round(Number(zone.tarif) * 100) / 100;
      zoneLivraisonIdValide = zone.id;
    }

    const total = Math.max(0, totalBrut - remise) + fraisLivraison;
    const acompte = Math.round(total * acomptePourcent) / 100;

    // 5. Créer la commande
    const { data: cmd, error: cmdErr } = await db.from("commande").insert({
      client_id: clientId,
      canal: "formulaire",
      type_evenement: type_evenement ?? null,
      date_evenement: date_evenement ?? null,
      date_retrait,
      statut: "a_confirmer",
      total,
      acompte,
      notes: notes ?? null,
      allergies: allergiesClean,
      message_gravure: gravureClean,
      couleur: couleurClean,
      photo_ref_url: photoRefClean,
      code_promo_id: codePromoIdValide,
      remise: remise > 0 ? remise : null,
      mode_remise: modeRemiseClean,
      zone_livraison_id: zoneLivraisonIdValide,
      frais_livraison: fraisLivraison,
      adresse_livraison: modeRemiseClean === "livraison" ? adresseClean : null,
      latitude: modeRemiseClean === "livraison" ? latClean : null,
      longitude: modeRemiseClean === "livraison" ? lonClean : null,
    }).select("id").single();
    if (cmdErr) throw cmdErr;

    for (const l of lignesValidees) {
      await db.from("commande_ligne").insert({
        commande_id: cmd.id,
        produit_id: l.produit_id,
        quantite: Number(l.quantite),
        prix_unitaire: l.prix_unitaire,
        declinaison: l.declinaison ?? null,
      });
    }

    // 5b. Incrémente le compteur du code promo (anti race-condition simple :
    //     on l'a déjà validé plus haut, on ne fait que +1).
    if (codePromoIdValide) {
      const { data: actuel } = await db.from("code_promo")
        .select("utilisations").eq("id", codePromoIdValide).single();
      const next = (Number(actuel?.utilisations ?? 0)) + 1;
      await db.from("code_promo").update({ utilisations: next }).eq("id", codePromoIdValide);
    }

    // 6. Stripe Checkout
    const base = origin || req.headers.get("origin") || "https://example.com";
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "eur",
          product_data: {
            name: `Acompte commande HappyKreations`,
            description: `${acomptePourcent}% du total ${total.toFixed(2)} €`,
          },
          unit_amount: Math.round(acompte * 100),
        },
      }],
      metadata: { commande_id: cmd.id },
      success_url: `${base}/merci?id=${cmd.id}`,
      cancel_url: `${base}/?annule=1`,
    });

    return json({ checkout_url: session.url, commande_id: cmd.id });
  } catch (err) {
    console.error(err);
    return json({ error: String((err as Error).message ?? err) }, { status: 500 });
  }
});
