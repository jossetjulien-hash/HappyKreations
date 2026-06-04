// Envoi d'emails transactionnels via Resend (https://resend.com).
// Configuration par variables d'environnement (secrets Supabase) :
//   RESEND_API_KEY  — clé API Resend (obligatoire pour envoyer).
//   EMAIL_FROM      — expéditeur, ex. "HappyKreations <commande@happykreations.fr>".
//                     Défaut : l'expéditeur de test Resend (onboarding@resend.dev),
//                     qui n'envoie qu'à l'adresse du compte tant que le domaine
//                     n'est pas vérifié.
//
// Si RESEND_API_KEY est absent, l'envoi est ignoré silencieusement (l'app
// continue de fonctionner sans email).

const PALETTE = {
  cream: "#FBF6EF",
  creamDeep: "#F3EADC",
  rose: "#E7B5B8",
  roseDeep: "#C98388",
  sage: "#A9BCA1",
  sageDeep: "#7E947A",
  ink: "#4F4A45",
  inkSoft: "#7b6f63",
};

export interface CommandeEmailData {
  clientNom: string;
  clientEmail: string;
  dateRetrait: string | null;      // "AAAA-MM-JJ"
  typeEvenement: string | null;
  total: number;
  acompte: number;
  lignes: { nom: string; quantite: number; declinaison: string | null }[];
  allergies: string[];
  messageGravure: string | null;
  couleur: string | null;
  nomAtelier: string;
}

function euros(n: number): string {
  return `${n.toFixed(2).replace(".", ",")} €`;
}

function dateFr(iso: string | null): string {
  if (!iso) return "à convenir";
  try {
    return new Intl.DateTimeFormat("fr-FR", {
      weekday: "long", day: "numeric", month: "long", year: "numeric",
    }).format(new Date(`${iso}T12:00:00Z`));
  } catch {
    return iso;
  }
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] ?? c));
}

export function renderCommandeConfirmation(d: CommandeEmailData): string {
  const p = PALETTE;
  const reste = Math.max(0, d.total - d.acompte);

  const lignesHtml = d.lignes.map((l) => `
    <tr>
      <td style="padding:8px 0;border-bottom:1px solid ${p.creamDeep};color:${p.ink};">
        ${escapeHtml(l.nom)}${l.declinaison ? ` <span style="color:${p.inkSoft};">· ${escapeHtml(l.declinaison)}</span>` : ""}
      </td>
      <td style="padding:8px 0;border-bottom:1px solid ${p.creamDeep};text-align:right;color:${p.ink};white-space:nowrap;">
        × ${l.quantite}
      </td>
    </tr>`).join("");

  const details: string[] = [];
  if (d.allergies.length) {
    details.push(`<strong>Allergies signalées :</strong> ${escapeHtml(d.allergies.join(", "))}`);
  }
  if (d.messageGravure) {
    details.push(`<strong>Message à graver :</strong> « ${escapeHtml(d.messageGravure)} »`);
  }
  if (d.couleur) {
    details.push(`<strong>Couleur souhaitée :</strong> ${escapeHtml(d.couleur)}`);
  }
  const detailsHtml = details.length
    ? `<div style="margin-top:18px;padding:16px;background:${p.cream};border-radius:12px;font-size:14px;color:${p.ink};line-height:1.8;">
         ${details.join("<br>")}
       </div>`
    : "";

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:${p.cream};font-family:'Helvetica Neue',Arial,sans-serif;color:${p.ink};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${p.cream};padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">

        <tr><td align="center" style="padding-bottom:24px;">
          <div style="font-family:Georgia,'Times New Roman',serif;font-size:30px;font-weight:300;letter-spacing:-1px;color:${p.ink};">
            happy<span style="font-style:italic;color:${p.roseDeep};">kreations</span>
          </div>
          <div style="font-size:11px;letter-spacing:3px;text-transform:uppercase;color:${p.inkSoft};margin-top:8px;">
            créations faites main
          </div>
        </td></tr>

        <tr><td style="background:#ffffff;border:1px solid ${p.creamDeep};border-radius:20px;padding:32px;">
          <div style="font-family:Georgia,serif;font-size:22px;color:${p.ink};margin-bottom:6px;">
            Merci ${escapeHtml(d.clientNom)} ✿
          </div>
          <p style="font-size:15px;line-height:1.7;color:${p.ink};margin:0 0 20px;">
            Votre acompte a bien été reçu et votre commande est <strong style="color:${p.sageDeep};">confirmée</strong>.
            Nous la préparons avec soin pour vous.
          </p>

          <div style="background:${p.cream};border-radius:14px;padding:18px 20px;margin-bottom:18px;">
            <div style="font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:${p.sageDeep};font-weight:bold;margin-bottom:4px;">
              Retrait prévu
            </div>
            <div style="font-family:Georgia,serif;font-size:18px;color:${p.ink};">
              ${dateFr(d.dateRetrait)}
            </div>
            ${d.typeEvenement ? `<div style="font-size:13px;color:${p.inkSoft};margin-top:4px;">${escapeHtml(d.typeEvenement)}</div>` : ""}
          </div>

          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:15px;">
            ${lignesHtml}
          </table>

          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:16px;font-size:15px;">
            <tr><td style="color:${p.inkSoft};padding:3px 0;">Total</td>
                <td style="text-align:right;color:${p.ink};padding:3px 0;">${euros(d.total)}</td></tr>
            <tr><td style="color:${p.inkSoft};padding:3px 0;">Acompte réglé</td>
                <td style="text-align:right;color:${p.sageDeep};padding:3px 0;font-weight:bold;">− ${euros(d.acompte)}</td></tr>
            <tr><td style="color:${p.ink};padding:8px 0 0;font-weight:bold;border-top:1px solid ${p.creamDeep};">Reste à régler au retrait</td>
                <td style="text-align:right;color:${p.roseDeep};padding:8px 0 0;font-weight:bold;border-top:1px solid ${p.creamDeep};">${euros(reste)}</td></tr>
          </table>

          ${detailsHtml}
        </td></tr>

        <tr><td align="center" style="padding-top:24px;">
          <div style="font-family:Georgia,serif;font-style:italic;font-size:18px;color:${p.sageDeep};">
            À très vite ✿
          </div>
          <div style="font-size:13px;color:${p.inkSoft};margin-top:6px;">
            ${escapeHtml(d.nomAtelier)}
          </div>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body></html>`;
}

/** Envoie l'email de confirmation. Renvoie true si envoyé, false si ignoré/échec. */
export async function sendCommandeConfirmation(d: CommandeEmailData): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("RESEND_API_KEY absent — email de confirmation ignoré.");
    return false;
  }
  if (!d.clientEmail) {
    console.warn("Client sans email — confirmation ignorée.");
    return false;
  }
  const from = Deno.env.get("EMAIL_FROM") ?? "HappyKreations <onboarding@resend.dev>";

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "authorization": `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [d.clientEmail],
        subject: `Votre commande ${d.nomAtelier} est confirmée ✿`,
        html: renderCommandeConfirmation(d),
      }),
    });
    if (!res.ok) {
      console.error("Échec envoi Resend :", res.status, await res.text());
      return false;
    }
    return true;
  } catch (err) {
    console.error("Erreur envoi email :", err);
    return false;
  }
}

// ===========================================================================
// RAPPEL J-3 (cron quotidien)
// ===========================================================================

export interface RappelEmailData {
  clientNom: string;
  clientEmail: string;
  dateRetrait: string | null;
  nomAtelier: string;
  adresseAtelier: string;
  telephoneAtelier: string;
  lignes: { nom: string; quantite: number; declinaison: string | null }[];
  total: number;
  acompte: number;
  allergies: string[];
  messageGravure: string | null;
  couleur: string | null;
  photoRefUrl: string | null;
}

export function renderRappelRetrait(d: RappelEmailData): string {
  const p = PALETTE;
  const reste = Math.max(0, d.total - d.acompte);

  const lignesHtml = d.lignes.map((l) => `
    <tr>
      <td style="padding:6px 0;color:${p.ink};">
        ${escapeHtml(l.nom)}${l.declinaison ? ` <span style="color:${p.inkSoft};">· ${escapeHtml(l.declinaison)}</span>` : ""}
      </td>
      <td style="padding:6px 0;text-align:right;color:${p.ink};white-space:nowrap;">
        × ${l.quantite}
      </td>
    </tr>`).join("");

  const details: string[] = [];
  if (d.allergies.length) {
    details.push(`<strong>Allergies :</strong> ${escapeHtml(d.allergies.join(", "))}`);
  }
  if (d.messageGravure) {
    details.push(`<strong>Message à graver :</strong> « ${escapeHtml(d.messageGravure)} »`);
  }
  if (d.couleur) {
    details.push(`<strong>Couleur :</strong> ${escapeHtml(d.couleur)}`);
  }
  const detailsHtml = details.length
    ? `<div style="margin-top:14px;padding:14px;background:${p.cream};border-radius:10px;font-size:13px;color:${p.ink};line-height:1.7;">${details.join("<br>")}</div>`
    : "";

  const lieuHtml = (d.adresseAtelier || d.telephoneAtelier)
    ? `<div style="margin-top:12px;font-size:13px;color:${p.ink};">
         ${d.adresseAtelier ? `📍 ${escapeHtml(d.adresseAtelier)}<br>` : ""}
         ${d.telephoneAtelier ? `📞 ${escapeHtml(d.telephoneAtelier)}` : ""}
       </div>`
    : "";

  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:${p.cream};font-family:'Helvetica Neue',Arial,sans-serif;color:${p.ink};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${p.cream};padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">

        <tr><td align="center" style="padding-bottom:24px;">
          <div style="font-family:Georgia,'Times New Roman',serif;font-size:30px;font-weight:300;letter-spacing:-1px;color:${p.ink};">
            happy<span style="font-style:italic;color:${p.roseDeep};">kreations</span>
          </div>
          <div style="font-size:11px;letter-spacing:3px;text-transform:uppercase;color:${p.inkSoft};margin-top:8px;">
            créations faites main
          </div>
        </td></tr>

        <tr><td style="background:#ffffff;border:1px solid ${p.creamDeep};border-radius:20px;padding:32px;">
          <div style="font-family:Georgia,serif;font-size:22px;color:${p.ink};margin-bottom:6px;">
            Bonjour ${escapeHtml(d.clientNom)} ✿
          </div>
          <p style="font-size:15px;line-height:1.7;color:${p.ink};margin:0 0 20px;">
            Petit rappel tout doux : votre commande est <strong style="color:${p.sageDeep};">prête à être retirée dans 3 jours</strong>. J'avais hâte de vous la faire découvrir !
          </p>

          <div style="background:${p.cream};border-radius:14px;padding:18px 20px;margin-bottom:18px;">
            <div style="font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:${p.sageDeep};font-weight:bold;margin-bottom:4px;">
              Retrait prévu
            </div>
            <div style="font-family:Georgia,serif;font-size:20px;color:${p.ink};">
              ${dateFr(d.dateRetrait)}
            </div>
            ${lieuHtml}
          </div>

          <div style="font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:${p.sageDeep};font-weight:bold;margin-bottom:6px;">
            Votre commande
          </div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;">
            ${lignesHtml}
          </table>

          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:12px;font-size:14px;">
            <tr><td style="color:${p.ink};padding:6px 0 0;font-weight:bold;border-top:1px solid ${p.creamDeep};">Reste à régler au retrait</td>
                <td style="text-align:right;color:${p.roseDeep};padding:6px 0 0;font-weight:bold;border-top:1px solid ${p.creamDeep};">${euros(reste)}</td></tr>
          </table>

          ${detailsHtml}

          <p style="font-size:13px;color:${p.inkSoft};margin:20px 0 0;line-height:1.6;">
            Si vous avez le moindre empêchement, contactez-moi simplement par retour de mail — on s'arrange ✿
          </p>
        </td></tr>

        <tr><td align="center" style="padding-top:24px;">
          <div style="font-family:Georgia,serif;font-style:italic;font-size:18px;color:${p.sageDeep};">
            À très vite ✿
          </div>
          <div style="font-size:13px;color:${p.inkSoft};margin-top:6px;">
            ${escapeHtml(d.nomAtelier)}
          </div>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body></html>`;
}

/** Envoie le rappel J-3. true si envoyé, false sinon. */
export async function sendRappelRetrait(d: RappelEmailData): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("RESEND_API_KEY absent — rappel J-3 ignoré.");
    return false;
  }
  if (!d.clientEmail) {
    console.warn("Client sans email — rappel J-3 ignoré.");
    return false;
  }
  const from = Deno.env.get("EMAIL_FROM") ?? "HappyKreations <onboarding@resend.dev>";

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "authorization": `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [d.clientEmail],
        subject: `Votre retrait ${d.nomAtelier} — c'est dans 3 jours ✿`,
        html: renderRappelRetrait(d),
      }),
    });
    if (!res.ok) {
      console.error("Échec rappel Resend :", res.status, await res.text());
      return false;
    }
    return true;
  } catch (err) {
    console.error("Erreur envoi rappel :", err);
    return false;
  }
}
