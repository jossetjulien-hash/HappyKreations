// Edge Function : envoyer-push
//
// Diffuse une notification push APNs à tous les appareils enregistrés dans la
// table `appareil`. Appelée par les triggers BDD (nouvelle commande, acompte
// reçu) ou manuellement pour tester.
//
// POST JSON : { titre: string, corps: string, commande_id?: string }
//
// Secrets attendus :
//   APNS_KEY_ID      — identifiant de la clé (10 caractères, ex. ABC123DEFG)
//   APNS_TEAM_ID     — Team ID Apple Developer (ex. YJ8T34YFZZ)
//   APNS_PRIVATE_KEY — contenu du fichier .p8, en-têtes PEM inclus
//   APNS_BUNDLE_ID   — com.happykreations.app (défaut si absent)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

/** base64url sans padding, comme exigé par la spec JWT. */
function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : new Uint8Array(data);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Convertit une clé PEM PKCS#8 (.p8 Apple) en ArrayBuffer. */
function pemToBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

/**
 * Jeton d'authentification APNs (JWT ES256). Apple l'accepte pendant 1 h et
 * refuse qu'on en génère plus d'un toutes les 20 min — on le met donc en cache
 * pour la durée de vie de l'instance.
 */
let jwtCache: { token: string; genere: number } | null = null;

async function apnsJWT(): Promise<string> {
  const maintenant = Math.floor(Date.now() / 1000);
  if (jwtCache && maintenant - jwtCache.genere < 1800) return jwtCache.token;

  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !pem) {
    throw new Error("secrets_apns_manquants");
  }

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBuffer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const entete = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const charge = b64url(JSON.stringify({ iss: teamId, iat: maintenant }));
  const aSigner = `${entete}.${charge}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(aSigner),
  );

  const token = `${aSigner}.${b64url(signature)}`;
  jwtCache = { token, genere: maintenant };
  return token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, { status: 405 });

  try {
    const { titre, corps, commande_id } = await req.json();
    if (!titre || !corps) return json({ error: "titre_et_corps_requis" }, { status: 400 });

    const { data: appareils, error } = await db.from("appareil")
      .select("id, device_token, environnement")
      .eq("actif", true);
    if (error) throw error;
    if (!appareils || appareils.length === 0) {
      return json({ ok: true, envoyees: 0, detail: "aucun_appareil_enregistre" });
    }

    const jwt = await apnsJWT();
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.happykreations.app";
    const charge = JSON.stringify({
      aps: {
        alert: { title: titre, body: corps },
        sound: "default",
        "interruption-level": "active",
      },
      // Permet à l'app d'ouvrir directement la bonne commande au tap.
      commande_id: commande_id ?? null,
    });

    let envoyees = 0;
    const echecs: unknown[] = [];
    const aDesactiver: string[] = [];

    for (const a of appareils) {
      // Les jetons de développement et de production ne sont pas
      // interchangeables : chaque appareil vise son propre serveur.
      const hote = a.environnement === "development"
        ? "https://api.sandbox.push.apple.com"
        : "https://api.push.apple.com";
      try {
        const r = await fetch(`${hote}/3/device/${a.device_token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": bundleId,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "content-type": "application/json",
          },
          body: charge,
        });
        if (r.ok) {
          envoyees++;
        } else {
          const detail = await r.text();
          echecs.push({ appareil: a.id, status: r.status, detail });
          // 410 Gone / BadDeviceToken : l'app a été désinstallée ou le jeton
          // a changé. On désactive pour ne pas réessayer indéfiniment.
          if (r.status === 410 || detail.includes("BadDeviceToken")) {
            aDesactiver.push(a.id);
          }
        }
      } catch (e) {
        echecs.push({ appareil: a.id, detail: String(e) });
      }
    }

    if (aDesactiver.length > 0) {
      await db.from("appareil").update({ actif: false }).in("id", aDesactiver);
    }

    return json({ ok: true, envoyees, total: appareils.length, echecs });
  } catch (err) {
    console.error("Erreur envoyer-push :", err);
    return json({ error: String((err as Error).message ?? err) }, { status: 500 });
  }
});
