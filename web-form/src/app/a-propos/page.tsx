import Link from "next/link";
import { supabase } from "@/lib/supabase";

interface ConfigItem { cle: string; valeur: string; }

async function getAtelier() {
  const { data } = await supabase
    .from("config")
    .select("cle, valeur")
    .in("cle", ["nom_atelier", "adresse_atelier", "email_atelier", "telephone_atelier"]);
  const map = Object.fromEntries(((data as ConfigItem[] | null) ?? []).map((r) => [r.cle, r.valeur]));
  return {
    nom: map["nom_atelier"] || "HappyKreations",
    adresse: map["adresse_atelier"] || "",
    email: map["email_atelier"] || "",
    telephone: map["telephone_atelier"] || "",
  };
}

export const revalidate = 300;

export default async function APropos() {
  const atelier = await getAtelier();

  return (
    <main className="home">
      <header className="home-brand">
        <Link href="/" className="logotype-link" aria-label="Retour à l'accueil">
          <div className="logotype">happy<b>kreations</b></div>
        </Link>
        <div className="tagline">créations faites main</div>
      </header>

      <section className="about-hero">
        <h1>
          <span className="ital">L'atelier,</span><br />
          <span className="script">une histoire de mains</span>
        </h1>
        <p className="lede">
          Chaque coffret, chaque cornet est imaginé puis façonné <strong>pièce par pièce</strong>,
          dans un atelier où le geste compte autant que le goût. Pas de série,
          pas de fabrication industrielle — juste du temps, du soin et de la matière.
        </p>
      </section>

      <section className="about-values">
        <article className="value-card">
          <div className="value-emoji">🍫</div>
          <h3>Artisanal</h3>
          <p>Chocolats tempérés à la main, meringues croustillantes cuites au four bas. Tout est réalisé chez nous, sans dépôt extérieur.</p>
        </article>
        <article className="value-card">
          <div className="value-emoji">✿</div>
          <h3>Sur mesure</h3>
          <p>Vous me racontez votre événement, je crée des douceurs qui collent à votre univers : couleurs, message gravé, allergies prises en compte.</p>
        </article>
        <article className="value-card">
          <div className="value-emoji">🌿</div>
          <h3>Frais & local</h3>
          <p>Matières premières sélectionnées avec attention, fournisseurs identifiés, production à la commande pour garantir la fraîcheur.</p>
        </article>
      </section>

      <section className="about-story">
        <h2><span className="step">✿</span> Comment c'est né</h2>
        <p>
          {atelier.nom} a commencé comme un petit plaisir partagé en famille : faire des
          chocolats pour les anniversaires, des meringues colorées pour les goûters.
          Petit à petit, les amis ont demandé d'en avoir aussi pour leurs mariages,
          leurs baptêmes, leurs baby showers — et l'atelier est devenu une vraie
          micro-entreprise, toujours façonnée à la main, jamais industrialisée.
        </p>
        <p>
          Aujourd'hui, je continue de fabriquer chaque commande avec la même
          attention. C'est important pour moi que chaque pièce soit unique : on ne
          travaille pas avec des moules de série, mais avec des intentions.
        </p>
      </section>

      {(atelier.adresse || atelier.email || atelier.telephone) && (
        <section className="about-contact">
          <h2><span className="step">✿</span> Me joindre</h2>
          <div className="contact-grid">
            {atelier.adresse && (
              <div className="contact-item">
                <div className="contact-label">Atelier</div>
                <div>{atelier.adresse}</div>
              </div>
            )}
            {atelier.email && (
              <div className="contact-item">
                <div className="contact-label">Email</div>
                <a href={`mailto:${atelier.email}`}>{atelier.email}</a>
              </div>
            )}
            {atelier.telephone && (
              <div className="contact-item">
                <div className="contact-label">Téléphone</div>
                <a href={`tel:${atelier.telephone}`}>{atelier.telephone}</a>
              </div>
            )}
          </div>
        </section>
      )}

      <section className="cta-bottom">
        <h2>Envie de composer votre commande&nbsp;?</h2>
        <Link href="/commander" className="cta">
          Démarrer ma commande
        </Link>
      </section>

      <footer className="home-footer">
        <Link href="/" className="logotype-link">
          <div className="logotype small">happy<b>kreations</b></div>
        </Link>
        <div className="muted">créations faites main · paiement sécurisé Stripe</div>
      </footer>
    </main>
  );
}
