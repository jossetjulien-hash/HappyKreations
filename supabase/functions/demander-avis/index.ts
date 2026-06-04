// Edge Function : demander-avis
//
// Appelée par pg_cron une fois par jour. Détecte les commandes dont le
// retrait a eu lieu HIER (et qui sont passées en livree / soldee), n'a
// pas déjà reçu de demande d'avis, et envoie un email avec lien vers
// /avis/{commande_id}.
//
// Anti-doublon : commande.demande_avis_envoyee_at non null = skip.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendDemandeAvis } from "../_shared/email.ts";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function isoDate(d: Date): string { return d.toISOString().slice(0, 10); }

Deno.serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response("method_not_allowed", { status: 405 });
  }
  const resume = { envoyes: 0, ignores: 0, erreurs: [] as string[] };
  try {
    const now = new Date();
    const hier = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const { data: commandes, error } = await db.from("commande")
      .select(`id, statut, client:client_id ( nom, email )`)
      .gte("date_retrait", isoDate(hier))
      .lt("date_retrait",  isoDate(today))
      .in("statut", ["livree", "soldee"])
      .is("demande_avis_envoyee_at", null);

    if (error) throw error;
    const liste = commandes ?? [];

    const { data: configRows } = await db.from("config")
      .select("cle, valeur").in("cle", ["nom_atelier"]);
    const nomAtelier = configRows?.[0]?.valeur || "HappyKreations";
    const baseUrl = Deno.env.get("PUBLIC_SITE_URL") ?? "https://commande.happykreations.fr";

    for (const c of liste) {
      const client = c.client as { nom?: string; email?: string } | null;
      if (!client?.email) { resume.ignores++; continue; }
      const ok = await sendDemandeAvis({
        clientNom: client.nom ?? "",
        clientEmail: client.email,
        nomAtelier,
        commandeId: c.id,
        baseUrl,
      });
      if (ok) {
        await db.from("commande").update({ demande_avis_envoyee_at: new Date().toISOString() }).eq("id", c.id);
        resume.envoyes++;
      } else {
        resume.ignores++;
      }
    }
  } catch (err) {
    resume.erreurs.push(err instanceof Error ? err.message : String(err));
    console.error("Erreur cron demander-avis :", err);
  }
  return new Response(JSON.stringify(resume), { headers: { "content-type": "application/json" } });
});
