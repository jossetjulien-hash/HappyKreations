import Link from "next/link";
import { supabase } from "@/lib/supabase";
import type { Produit } from "@/lib/types";

// SSR pour avoir une vraie page rapide + SEO. Revalidation toutes les 5 min,
// largement suffisant pour un catalogue artisanal.
export const revalidate = 300;

async function getProduits(): Promise<Produit[]> {
  const { data } = await supabase
    .from("produit")
    .select("*")
    .eq("visible_formulaire", true)
    .eq("actif", true)
    .order("nom");
  return (data as Produit[] | null) ?? [];
}

interface Temoignage {
  id: string;
  auteur: string;
  texte: string;
  evenement: string | null;
  ordre: number;
}

async function getTemoignages(): Promise<Temoignage[]> {
  const { data } = await supabase
    .from("temoignage")
    .select("id, auteur, texte, evenement, ordre")
    .eq("visible", true)
    .order("ordre");
  return (data as Temoignage[] | null) ?? [];
}

export default async function HomePage() {
  const produits = await getProduits();
  const temoignages = await getTemoignages();
  const produitsAvecPhoto = produits.filter((p) => p.photo_url);
  const galerie = produitsAvecPhoto.length > 0 ? produitsAvecPhoto : produits;

  return (
    <main className="home">
      <header className="home-brand">
        <img src="/icon.png" alt="Logo HappyKreations" className="brand-logo" width={72} height={72} />
        <div className="logotype">happy<b>kreations</b></div>
        <div className="tagline">créations faites main</div>
      </header>

      <section className="hero">
        <div className="hero-text">
          <h1>
            Pour vos plus <span className="ital">jolis instants,</span>
            <br />
            des douceurs <span className="script">faites avec soin</span>
          </h1>
          <p className="lede">
            Coffrets de chocolats et cornets de meringues, imaginés pièce par pièce
            pour vos mariages, baptêmes, communions et petites célébrations.
          </p>
          <Link href="/commander" className="cta">
            Composer ma commande
          </Link>
          <div className="hero-meta">
            Acompte 30 % en ligne · Solde au retrait · Délai minimum 7 jours
          </div>
        </div>
        <div className="hero-illus" aria-hidden="true">
          <BigSprig />
        </div>
      </section>

      {galerie.length > 0 && (
        <section className="gallery">
          <h2><span className="step">✿</span> Le catalogue</h2>
          <p className="muted">Quelques-unes de mes créations — tout est sur mesure.</p>
          <div className="gallery-grid">
            {galerie.slice(0, 8).map((p) => (
              <article key={p.id} className="produit-tile">
                {p.photo_url ? (
                  <img src={p.photo_url} alt={p.nom} />
                ) : (
                  <div className="produit-tile-placeholder">
                    {p.categorie === "coffret" ? "🍫" : "🌀"}
                  </div>
                )}
                <div className="produit-tile-info">
                  <strong>{p.nom}</strong>
                  <span>
                    {p.prix_vente.toFixed(2)} € · {p.categorie}
                  </span>
                </div>
              </article>
            ))}
          </div>
        </section>
      )}

      <section className="steps">
        <h2><span className="step">✿</span> Comment ça marche</h2>
        <div className="steps-grid">
          <div className="step-card">
            <div className="step-num">1</div>
            <h3>Vous composez</h3>
            <p>Choisissez vos produits, déclinaisons et la date de retrait — directement depuis le formulaire en ligne.</p>
          </div>
          <div className="step-card">
            <div className="step-num">2</div>
            <h3>Vous validez</h3>
            <p>Un acompte de 30 % par carte sécurise la commande. Le solde se règle simplement le jour du retrait.</p>
          </div>
          <div className="step-card">
            <div className="step-num">3</div>
            <h3>Je prépare</h3>
            <p>Je façonne chaque pièce à la main, avec les détails que vous m'avez confiés. À vous le moment du retrait ✿</p>
          </div>
        </div>
      </section>

      {temoignages.length > 0 && (
        <section className="testimonials">
          <h2><span className="step">✿</span> Ils en parlent</h2>
          <div className="testimonials-grid">
            {temoignages.map((t) => (
              <figure key={t.id} className="testimonial">
                <blockquote>« {t.texte} »</blockquote>
                <figcaption>
                  <strong>{t.auteur}</strong>
                  {t.evenement && <span> · {t.evenement}</span>}
                </figcaption>
              </figure>
            ))}
          </div>
        </section>
      )}

      <section className="cta-bottom">
        <h2>Prêt·e à composer votre commande&nbsp;?</h2>
        <Link href="/commander" className="cta">
          Démarrer ma commande
        </Link>
      </section>

      <footer className="home-footer">
        <div className="logotype small">happy<b>kreations</b></div>
        <div className="muted">créations faites main · paiement sécurisé Stripe</div>
        <div className="footer-links">
          <Link href="/a-propos">L'atelier</Link>
          <span aria-hidden="true">·</span>
          <Link href="/commander">Commander</Link>
        </div>
      </footer>
    </main>
  );
}

function Sprig() {
  return (
    <svg className="sprig" viewBox="0 0 80 80" fill="none" aria-hidden="true">
      <path d="M40 70 C40 50 40 28 40 12" stroke="#7E947A" strokeWidth="1.6" strokeLinecap="round" />
      <g fill="#A9BCA1">
        <ellipse cx="28" cy="50" rx="9" ry="5" transform="rotate(-34 28 50)" />
        <ellipse cx="52" cy="44" rx="9" ry="5" transform="rotate(34 52 44)" />
        <ellipse cx="30" cy="34" rx="8" ry="4.5" transform="rotate(-30 30 34)" />
        <ellipse cx="50" cy="28" rx="8" ry="4.5" transform="rotate(30 50 28)" />
      </g>
      <ellipse cx="40" cy="14" rx="6" ry="7" fill="#E7B5B8" />
    </svg>
  );
}

function BigSprig() {
  return (
    <svg viewBox="0 0 240 280" fill="none" aria-hidden="true">
      <path d="M120 260 C120 200 120 120 120 30" stroke="#7E947A" strokeWidth="2" strokeLinecap="round" />
      <g fill="#A9BCA1">
        <ellipse cx="78" cy="220" rx="34" ry="16" transform="rotate(-32 78 220)" />
        <ellipse cx="162" cy="200" rx="34" ry="16" transform="rotate(32 162 200)" />
        <ellipse cx="82" cy="160" rx="30" ry="14" transform="rotate(-28 82 160)" />
        <ellipse cx="160" cy="140" rx="30" ry="14" transform="rotate(28 160 140)" />
        <ellipse cx="92" cy="100" rx="26" ry="12" transform="rotate(-26 92 100)" />
        <ellipse cx="150" cy="80" rx="26" ry="12" transform="rotate(26 150 80)" />
      </g>
      <ellipse cx="120" cy="32" rx="20" ry="24" fill="#E7B5B8" />
      <ellipse cx="120" cy="32" rx="9" ry="11" fill="#C98388" opacity="0.5" />
    </svg>
  );
}
