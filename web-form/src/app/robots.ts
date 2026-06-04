import type { MetadataRoute } from "next";

/// Robots indexables. Le formulaire de paiement et la page Merci sont
/// référençables sans risque (pas d'info perso). Le webhook Stripe (côté
/// Supabase, hors web-form) n'est pas concerné.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: "https://commande.happykreations.fr/sitemap.xml",
  };
}
