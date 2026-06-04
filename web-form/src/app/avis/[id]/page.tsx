"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { supabase } from "@/lib/supabase";

/// Page d'avis post-retrait. L'URL contient l'UUID de la commande, qui sert
/// de capability token (impossible à deviner). À la soumission on insère
/// dans `avis` via la policy `anon_insert_avis`. L'artisan validera
/// l'avis (visible=true) depuis l'app pour qu'il devienne un témoignage
/// public.
export default function AvisPage() {
  const params = useParams<{ id: string }>();
  const commandeId = params.id;
  const [note, setNote] = useState<number>(5);
  const [texte, setTexte] = useState("");
  const [auteur, setAuteur] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function envoyer() {
    setError(null); setLoading(true);
    try {
      const { error } = await supabase.from("avis").insert({
        commande_id: commandeId,
        note,
        texte: texte.trim() || null,
        auteur: auteur.trim() || null,
      });
      if (error) throw error;
      setSubmitted(true);
    } catch (e) {
      setError((e as Error).message || "Erreur lors de l'envoi.");
    } finally { setLoading(false); }
  }

  if (submitted) {
    return (
      <div className="container">
        <header className="brand">
          <img src="/icon.png" alt="" className="brand-logo" width={64} height={64} />
          <div className="logotype">happy<b>kreations</b></div>
          <div className="tagline">créations faites main</div>
        </header>
        <div className="card" style={{ textAlign: "center", padding: 40 }}>
          <div className="lede" style={{ fontSize: "2.2rem", marginBottom: 8 }}>Merci infiniment ✿</div>
          <p>Votre avis a bien été enregistré. C'est un précieux retour pour moi.</p>
          <p className="muted">Avec gratitude.</p>
          <a href="/" style={{ color: "var(--accent)", display: "inline-block", marginTop: 20, fontWeight: 700 }}>
            Retour à l'accueil
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="container">
      <header className="brand">
        <img src="/icon.png" alt="" className="brand-logo" width={64} height={64} />
        <div className="logotype">happy<b>kreations</b></div>
        <div className="tagline">créations faites main</div>
      </header>

      <section className="card">
        <h2><span className="step">✿</span> Votre avis</h2>
        <p className="muted" style={{ marginBottom: 18 }}>
          Quelques mots, une note — vraiment ce que vous voulez. Tout retour est précieux.
        </p>

        <label>Note</label>
        <div className="etoiles">
          {[1, 2, 3, 4, 5].map((n) => (
            <button key={n} type="button"
              className={`etoile ${n <= note ? "on" : ""}`}
              onClick={() => setNote(n)}
              aria-label={`${n} étoile${n > 1 ? "s" : ""}`}>
              ★
            </button>
          ))}
        </div>

        <label>Votre commentaire (facultatif)</label>
        <textarea value={texte} onChange={(e) => setTexte(e.target.value)}
                  placeholder="Quelques mots sur les douceurs, l'événement, l'accueil…" />

        <label>Votre prénom ou nom d'affichage (facultatif)</label>
        <input value={auteur} onChange={(e) => setAuteur(e.target.value)}
               placeholder="Camille, Camille L., @camille…" />

        {error && <p className="error" style={{ marginTop: 8 }}>{error}</p>}

        <button type="button" onClick={envoyer} disabled={loading} style={{ marginTop: 18 }}>
          {loading ? "Envoi en cours…" : "Envoyer mon avis ✿"}
        </button>
      </section>

      <p className="muted" style={{ textAlign: "center", marginTop: 20, fontSize: 12 }}>
        Avec votre accord, votre avis pourra apparaître anonymisé dans la page d'accueil de HappyKreations.
      </p>
    </div>
  );
}
