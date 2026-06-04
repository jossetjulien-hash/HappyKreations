import type { MetadataRoute } from "next";

const BASE = "https://commande.happykreations.fr";

/// Sitemap statique — 4 routes publiques. La page de remerciement n'est
/// pas indexée (param querystring + contenu post-paiement).
export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return [
    { url: BASE,                  lastModified: now, priority: 1.0,  changeFrequency: "weekly"  },
    { url: `${BASE}/commander`,   lastModified: now, priority: 0.9,  changeFrequency: "weekly"  },
    { url: `${BASE}/a-propos`,    lastModified: now, priority: 0.7,  changeFrequency: "monthly" },
  ];
}
