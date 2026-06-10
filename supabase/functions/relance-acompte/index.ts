// Edge Function : relance-acompte
// Scanne les commandes en attente d'acompte créées il y a + de N heures
// (config.relance_acompte_delai_heures) et envoie un email de relance avec
// un nouveau lien Stripe Checkout.
//
// Appelée par pg_cron quotidien ou manuellement avec { commande_id }.

import Stripe from "https://esm.sh/stripe@16?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

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

async function envoyerRelance(commande: any, client: any, baseUrl: string)
  : Promise<{ ok: boolean; reason?: string }> {
  if (!client?.email) return { ok: false, reason: "client_sans_email" };
  const acompte = Number(commande.acompte ?? 0);
  if (acompte <= 0.49) return { ok: false, reason: "acompte_trop_faible" };

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    customer_email: client.email,
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "eur",
        product_data: {
          name: `Acompte commande HappyKreations`,
          description: `Référence #${String(commande.id).slice(0, 4).toUpperCase()}`,
        },
        unit_amount: Math.round(acompte * 100),
      },
    }],
    metadata: { commande_id: commande.id, kind: "acompte_relance" },
    success_url: `${baseUrl}/merci?id=${commande.id}`,
    cancel_url: `${baseUrl}/?annule=1`,
  });
  const checkoutUrl = session.url ?? "";

  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (resendKey) {
    const refCourte = "#" + String(commande.id).slice(0, 4).toUpperCase();
    const prenom = (client.nom ?? "").split(" ")[0] || "";
    const salutation = prenom ? `Bonjour ${prenom},` : "Bonjour,";
    const dateRet = commande.date_retrait
      ? new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" })
          .format(new Date(`${commande.date_retrait}T12:00:00Z`))
      : "";
    const html = `<!DOCTYPE html>
<html><body style="font-family:-apple-system,Helvetica,sans-serif;background:#FBF6EF;padding:24px;color:#4F4A45;">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:18px;padding:32px;">
    <h1 style="font-family:Georgia,serif;color:#C98388;font-weight:400;margin:0 0 8px;">Votre commande vous attend ✿</h1>
    <p style="color:#7b6f63;margin:0 0 24px;">Référence ${refCourte}${dateRet ? ` — retrait ${dateRet}` : ""}</p>
    <p>${salutation}</p>
    <p>Votre commande est presque finalisée — il manque le règlement de l'acompte pour la confirmer définitivement.</p>
    <p style="text-align:center;margin:28px 0;">
      <a href="${checkoutUrl}" style="display:inline-block;background:#C98388;color:#fff;padding:14px 28px;border-radius:24px;text-decoration:none;font-weight:600;">Régler mon acompte (${acompte.toFixed(2).replace('.', ',')} €)</a>
    </p>
    <p style="color:#7b6f63;font-size:13px;">Si vous ne souhaitez plus cette commande, vous pouvez ignorer ce message — elle sera annulée automatiquement dans quelques jours.</p>
    <p style="color:#7b6f63;font-size:13px;">À très vite,<br>HappyKreations</p>
  </div>
</body></html>`;
    try {
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: Deno.env.get("EMAIL_FROM") ?? "onboarding@resend.dev",
          to: client.email,
          subject: `Votre commande HappyKreations vous attend ✨`,
          html,
          tags: [
            { name: "kind", value: "relance_acompte" },
            { name: "commande_id", value: commande.id },
          ],
        }),
      });
      if (!r.ok) {
        const txt = await r.text();
        console.error("Resend error:", txt);
        return { ok: false, reason: "resend_error" };
      }
    } catch (e) {
      console.error("Resend fetch failed:", e);
      return { ok: false, reason: "resend_fetch_failed" };
    }
  }

  await db.from("commande")
    .update({ relance_acompte_envoye_at: new Date().toISOString() })
    .eq("id", commande.id);
  return { ok: true };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const baseUrl = Deno.env.get("PUBLIC_SITE_URL") ?? "https://commande.happykreations.fr";

  try {
    let body: any = {};
    try { body = await req.json(); } catch { /* GET ou body vide */ }
    const commandeIdSpecifique = typeof body?.commande_id === "string" ? body.commande_id : null;

    const { data: configRows } = await db.from("config").select("*")
      .in("cle", ["relance_acompte_actif", "relance_acompte_delai_heures"]);
    const config = Object.fromEntries((configRows ?? []).map((r: any) => [r.cle, r.valeur]));
    const actif = (config.relance_acompte_actif ?? "true") === "true";
    const delaiHeures = Number(config.relance_acompte_delai_heures ?? 48);

    if (!commandeIdSpecifique && !actif) {
      return json({ ok: true, skipped: "relance_desactivee" });
    }

    let query = db.from("commande")
      .select("id, client_id, statut, total, acompte, date_retrait, created_at, relance_acompte_envoye_at")
      .eq("statut", "a_confirmer");
    if (commandeIdSpecifique) {
      query = query.eq("id", commandeIdSpecifique);
    } else {
      const cutoff = new Date(Date.now() - delaiHeures * 3_600_000).toISOString();
      query = query.lte("created_at", cutoff).is("relance_acompte_envoye_at", null);
    }
    const { data: commandes, error } = await query;
    if (error) throw error;
    if (!commandes || commandes.length === 0) return json({ ok: true, relancees: 0 });

    const clientIds = commandes.map((c: any) => c.client_id).filter((x: any) => x);
    const { data: clients } = await db.from("client")
      .select("id, nom, email").in("id", clientIds);
    const clientMap = new Map((clients ?? []).map((c: any) => [c.id, c]));

    let envoyees = 0;
    const erreurs: any[] = [];
    for (const cmd of commandes) {
      const { data: pmts } = await db.from("paiement")
        .select("id").eq("commande_id", cmd.id).eq("statut", "reussi").limit(1);
      if (pmts && pmts.length > 0) continue;
      const client = clientMap.get(cmd.client_id);
      const r = await envoyerRelance(cmd, client, baseUrl);
      if (r.ok) envoyees++;
      else erreurs.push({ commande_id: cmd.id, reason: r.reason });
    }
    return json({ ok: true, relancees: envoyees, erreurs });
  } catch (err) {
    console.error(err);
    return json({ error: String((err as Error).message ?? err) }, { status: 500 });
  }
});
