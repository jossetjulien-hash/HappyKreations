// Edge Function : rappel-retraits
//
// Appelée par le cron Supabase (pg_cron) une fois par jour. Trouve les
// commandes dont le retrait est dans ~3 jours (entre J+2 et J+3 inclus pour
// absorber les décalages de fuseau), n'a pas déjà reçu de rappel, est dans un
// statut "vivant" (confirmee, en_production, prete), et déclenche l'envoi de
// l'email de rappel.
//
// Marque ensuite rappel_envoye_at = now() pour ne plus rappeler.
//
// Anti-spam : la BDD est l'unique source de vérité. Même si quelqu'un appelle
// cet endpoint en boucle, le filtre `rappel_envoye_at is null` garantit qu'on
// n'envoie qu'une seule fois par commande.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendRappelRetrait } from "../_shared/email.ts";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

interface Resume {
  envoyes: number;
  ignores: number;
  erreurs: string[];
}

Deno.serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response("method_not_allowed", { status: 405 });
  }

  const resume: Resume = { envoyes: 0, ignores: 0, erreurs: [] };

  try {
    // Fenêtre de retrait : J+2 à J+3 (UTC). Pour le cas où le cron tourne à 9h
    // UTC = 11h Paris, on attrape "dans 3 jours" même si on est en début ou
    // fin de journée locale.
    const now = new Date();
    const dPlus2 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2);
    const dPlus3 = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 3);

    const { data: commandes, error } = await db.from("commande")
      .select(`
        id, total, acompte, date_retrait, allergies, message_gravure, couleur,
        photo_ref_url, statut,
        client:client_id ( nom, email ),
        lignes:commande_ligne ( quantite, declinaison, produit:produit_id ( nom ) )
      `)
      .gte("date_retrait", isoDate(dPlus2))
      .lte("date_retrait", isoDate(dPlus3))
      .in("statut", ["confirmee", "en_production", "prete"])
      .is("rappel_envoye_at", null);

    if (error) throw error;
    const liste = commandes ?? [];

    // Config atelier (pour signer l'email)
    const { data: configRows } = await db.from("config")
      .select("cle, valeur")
      .in("cle", ["nom_atelier", "adresse_atelier", "telephone_atelier"]);
    const conf = Object.fromEntries((configRows ?? []).map((r) => [r.cle, r.valeur ?? ""]));
    const nomAtelier = conf["nom_atelier"] || "HappyKreations";

    for (const c of liste) {
      const client = c.client as { nom?: string; email?: string } | null;
      if (!client?.email) { resume.ignores++; continue; }

      const lignes = (c.lignes as Array<{
        quantite: number; declinaison: string | null; produit: { nom: string } | null;
      }> ?? []).map((l) => ({
        nom: l.produit?.nom ?? "Produit",
        quantite: l.quantite,
        declinaison: l.declinaison,
      }));

      const ok = await sendRappelRetrait({
        clientNom: client.nom ?? "",
        clientEmail: client.email,
        dateRetrait: c.date_retrait ?? null,
        nomAtelier,
        adresseAtelier: conf["adresse_atelier"] || "",
        telephoneAtelier: conf["telephone_atelier"] || "",
        lignes,
        total: Number(c.total ?? 0),
        acompte: Number(c.acompte ?? 0),
        allergies: (c.allergies as string[]) ?? [],
        messageGravure: c.message_gravure ?? null,
        couleur: c.couleur ?? null,
        photoRefUrl: c.photo_ref_url ?? null,
      });

      if (ok) {
        await db.from("commande")
          .update({ rappel_envoye_at: new Date().toISOString() })
          .eq("id", c.id);
        resume.envoyes++;
      } else {
        resume.ignores++;
      }
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    resume.erreurs.push(msg);
    console.error("Erreur cron rappel-retraits :", msg);
  }

  return new Response(JSON.stringify(resume), {
    headers: { "content-type": "application/json" },
  });
});
