// Edge Function : resend-webhook
//
// Reçoit les événements Resend (email.opened, email.bounced…). Pour chaque
// événement `email.opened`, on retrouve la commande via le tag `commande_id`
// embarqué à l'envoi et on date l'ouverture (selon le tag `kind`).
//
// Sécurité : vérification de la signature HMAC-SHA256 envoyée par Resend
// (header `svix-signature`, secret RESEND_WEBHOOK_SECRET). Si le secret n'est
// pas configuré, on accepte (utile en local) mais on log un avertissement.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

interface ResendEvent {
  type?: string;       // "email.opened", "email.delivered", "email.bounced", …
  created_at?: string;
  data?: {
    tags?: Array<{ name: string; value: string }>;
    email_id?: string;
  };
}

/** Vérifie la signature Resend (HMAC-SHA256 base64 du body brut). */
async function verifySignature(
  rawBody: string, signatureHeader: string | null, secret: string,
): Promise<boolean> {
  if (!signatureHeader) return false;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(rawBody));
  const computed = btoa(String.fromCharCode(...new Uint8Array(sig)));
  // svix-signature contient une ou plusieurs paires "v1,<sig>" séparées par
  // des espaces. On accepte si l'une au moins matche notre HMAC.
  return signatureHeader.split(" ").some((part) => {
    const [, value] = part.split(",");
    return value === computed;
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method_not_allowed", { status: 405 });
  }
  const raw = await req.text();
  const secret = Deno.env.get("RESEND_WEBHOOK_SECRET");
  if (secret) {
    const ok = await verifySignature(raw, req.headers.get("svix-signature"), secret);
    if (!ok) return new Response("invalid_signature", { status: 401 });
  } else {
    console.warn("RESEND_WEBHOOK_SECRET absent — signature non vérifiée.");
  }

  let event: ResendEvent;
  try { event = JSON.parse(raw); } catch { return new Response("bad_json", { status: 400 }); }

  // On ne traite que l'ouverture pour l'instant.
  if (event.type !== "email.opened") {
    return new Response("ok");
  }

  const tags = event.data?.tags ?? [];
  const commandeId = tags.find((t) => t.name === "commande_id")?.value;
  const kind = tags.find((t) => t.name === "kind")?.value;
  if (!commandeId || !kind) {
    return new Response("ok");
  }

  const now = new Date().toISOString();
  const colonne = kind === "rappel"
    ? "email_rappel_ouvert_at"
    : "email_confirmation_ouvert_at";

  // Premier ouvert remporté : on n'écrase pas si déjà rempli.
  const { data: existing } = await db.from("commande")
    .select(colonne).eq("id", commandeId).maybeSingle();
  if (existing && (existing as Record<string, unknown>)[colonne] != null) {
    return new Response("ok");
  }

  const { error } = await db.from("commande")
    .update({ [colonne]: now }).eq("id", commandeId);
  if (error) {
    console.error("Échec MAJ commande :", error);
    return new Response("db_error", { status: 500 });
  }
  return new Response("ok");
});
