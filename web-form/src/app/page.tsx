"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import type { Produit, CapaciteJour, ConfigItem, LigneCommande, ClientInfo } from "@/lib/types";

const SUPABASE_FN_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/creer-paiement`;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

const ALLERGENES = ["Gluten", "Lait", "Œuf", "Fruits à coque", "Arachide", "Soja", "Sésame"];

export default function Page() {
  const [produits, setProduits] = useState<Produit[]>([]);
  const [capacites, setCapacites] = useState<CapaciteJour[]>([]);
  const [config, setConfig] = useState<Record<string, string>>({});
  const [quantites, setQuantites] = useState<Record<string, { qte: number; decli?: string }>>({});
  const [dateRetrait, setDateRetrait] = useState<string | null>(null);
  const [typeEvenement, setTypeEvenement] = useState("");
  const [dateEvenement, setDateEvenement] = useState<string>("");
  const [notes, setNotes] = useState("");
  const [allergies, setAllergies] = useState<string[]>([]);
  const [messageGravure, setMessageGravure] = useState("");
  const [couleur, setCouleur] = useState("");
  const [photoRef, setPhotoRef] = useState<File | null>(null);
  const [photoRefPreview, setPhotoRefPreview] = useState<string | null>(null);
  const [client, setClient] = useState<ClientInfo>({ nom: "" });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function onPhotoChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0] ?? null;
    setPhotoRef(f);
    setPhotoRefPreview(f ? URL.createObjectURL(f) : null);
  }

  /** Upload la photo de référence dans le bucket public commandes-refs.
   *  Retourne l'URL publique ou null si pas de photo. */
  async function uploadPhotoRef(): Promise<string | null> {
    if (!photoRef) return null;
    const ext = (photoRef.name.split(".").pop() || "jpg").toLowerCase();
    const path = `${crypto.randomUUID()}.${ext}`;
    const { error: upErr } = await supabase.storage
      .from("commandes-refs")
      .upload(path, photoRef, { contentType: photoRef.type, upsert: false });
    if (upErr) throw new Error(`Photo : ${upErr.message}`);
    const { data } = supabase.storage.from("commandes-refs").getPublicUrl(path);
    return `${data.publicUrl}?v=${Date.now()}`;
  }

  useEffect(() => {
    (async () => {
      const [{ data: p }, { data: c }, { data: cf }] = await Promise.all([
        supabase.from("produit").select("*").eq("visible_formulaire", true).eq("actif", true),
        supabase.from("capacite_jour").select("*"),
        supabase.from("config").select("*"),
      ]);
      setProduits(p ?? []);
      setCapacites(c ?? []);
      setConfig(Object.fromEntries((cf as ConfigItem[] ?? []).map((x) => [x.cle, x.valeur])));
    })();
  }, []);

  const delaiMini = Number(config["delai_mini_jours"] ?? 7);
  const acomptePourcent = Number(config["acompte_pourcent"] ?? 30);

  const datesProposees = useMemo(() => {
    const out: { date: string; jour: number; mois: string; ok: boolean }[] = [];
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const moisFmt = new Intl.DateTimeFormat("fr-FR", { month: "short" });
    // Marge +1 jour pour absorber les décalages de fuseau entre le navigateur
    // (heure locale) et l'Edge Function (UTC), qui peuvent faire perdre 1 jour.
    for (let i = delaiMini + 1; i < delaiMini + 61; i++) {
      const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i);
      // Format AAAA-MM-JJ en utilisant les composantes LOCALES (pas toISOString
      // qui passe en UTC et peut renvoyer la veille).
      const y = d.getFullYear();
      const m = String(d.getMonth() + 1).padStart(2, "0");
      const j = String(d.getDate()).padStart(2, "0");
      const iso = `${y}-${m}-${j}`;
      const cap = capacites.find((c) => c.date === iso);
      const ok = !(cap?.bloque ?? false);
      out.push({ date: iso, jour: d.getDate(), mois: moisFmt.format(d), ok });
    }
    return out;
  }, [capacites, delaiMini]);

  const lignes: LigneCommande[] = Object.entries(quantites)
    .filter(([, v]) => v.qte > 0)
    .map(([produit_id, v]) => ({ produit_id, quantite: v.qte, declinaison: v.decli }));

  const total = lignes.reduce((s, l) => {
    const p = produits.find((pp) => pp.id === l.produit_id);
    return s + (p?.prix_vente ?? 0) * l.quantite;
  }, 0);
  const acompte = Math.round(total * acomptePourcent) / 100;

  function setQte(p: Produit, delta: number) {
    setQuantites((q) => {
      const cur = q[p.id] ?? { qte: 0, decli: p.declinaisons[0] };
      const next = Math.max(0, cur.qte + delta);
      return { ...q, [p.id]: { ...cur, qte: next } };
    });
  }
  function setDecli(p: Produit, decli: string) {
    setQuantites((q) => ({ ...q, [p.id]: { qte: q[p.id]?.qte ?? 0, decli } }));
  }

  async function submit() {
    setError(null);
    if (!client.nom.trim()) return setError("Indiquez votre nom.");
    if (!client.email && !client.telephone) return setError("Email ou téléphone requis.");
    if (!dateRetrait) return setError("Choisissez une date de retrait.");
    if (lignes.length === 0) return setError("Sélectionnez au moins un produit.");

    setLoading(true);
    try {
      // Upload de la photo de référence en amont (l'edge function n'aura
      // qu'à stocker l'URL — pas de gestion de fichier côté serveur).
      const photoUrl = await uploadPhotoRef();

      const r = await fetch(SUPABASE_FN_URL, {
        method: "POST",
        headers: { "content-type": "application/json", apikey: ANON, authorization: `Bearer ${ANON}` },
        body: JSON.stringify({
          client,
          date_retrait: dateRetrait,
          date_evenement: dateEvenement || null,
          type_evenement: typeEvenement || null,
          lignes,
          notes,
          allergies,
          message_gravure: messageGravure || null,
          couleur: couleur || null,
          photo_ref_url: photoUrl,
          origin: window.location.origin,
        }),
      });
      const data = await r.json();
      if (!r.ok) {
        setError(data?.error ?? "Erreur lors de la création de la commande.");
      } else if (data.checkout_url) {
        window.location.href = data.checkout_url;
      }
    } catch (e) {
      setError(String((e as Error).message));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="container">
      <header className="brand">
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
        <div className="logotype">happy<b>kreations</b></div>
        <div className="tagline">créations faites main</div>
        <div className="lede">Composez votre commande pour votre événement</div>
      </header>

      <section className="card">
        <h2><span className="step">1.</span> Vos produits</h2>
        {produits.length === 0 && <p className="muted">Catalogue en cours de chargement…</p>}
        {produits.map((p) => {
          const q = quantites[p.id]?.qte ?? 0;
          return (
            <div key={p.id} className="produit-card">
              {p.photo_url ? (
                <img src={p.photo_url} alt={p.nom} className="produit-photo" />
              ) : (
                <div className="produit-photo placeholder" aria-hidden="true">
                  {p.categorie === "coffret" ? "🍫" : "🌀"}
                </div>
              )}
              <div className="produit-infos">
                <strong>{p.nom}</strong>
                <div className="muted">
                  {p.prix_vente.toFixed(2)} € · {p.categorie}
                </div>
                {p.declinaisons.length > 0 && (
                  <select
                    value={quantites[p.id]?.decli ?? p.declinaisons[0]}
                    onChange={(e) => setDecli(p, e.target.value)}
                    style={{ marginTop: 6, maxWidth: 200 }}
                  >
                    {p.declinaisons.map((d) => <option key={d}>{d}</option>)}
                  </select>
                )}
              </div>
              <div className="qte-control">
                <button type="button" onClick={() => setQte(p, -1)} disabled={q === 0}>−</button>
                <span style={{ minWidth: 24, textAlign: "center" }}>{q}</span>
                <button type="button" onClick={() => setQte(p, +1)}>+</button>
              </div>
            </div>
          );
        })}
      </section>

      <section className="card">
        <h2><span className="step">2.</span> Date de retrait</h2>
        <p className="muted">
          Minimum {delaiMini} jours avant la date de l’événement.
        </p>
        <div className="dates-grid">
          {datesProposees.map((d) => (
            <button
              key={d.date}
              type="button"
              disabled={!d.ok}
              className={`date-cell ${dateRetrait === d.date ? "selected" : ""} ${d.ok ? "" : "disabled"}`}
              onClick={() => d.ok && setDateRetrait(d.date)}
            >
              <div className="day">{d.jour}</div>
              <div className="month">{d.mois}</div>
            </button>
          ))}
        </div>
      </section>

      <section className="card">
        <h2><span className="step">3.</span> Votre événement</h2>
        <label>Type d’événement</label>
        <input value={typeEvenement} onChange={(e) => setTypeEvenement(e.target.value)} placeholder="Mariage, baptême, communion…" />
        <label>Date de l’événement (si différente du retrait)</label>
        <input type="date" value={dateEvenement} onChange={(e) => setDateEvenement(e.target.value)} />

        <label>Allergies à signaler</label>
        <div className="chips">
          {ALLERGENES.map((a) => {
            const on = allergies.includes(a);
            return (
              <button
                key={a}
                type="button"
                className={`chip ${on ? "on" : ""}`}
                onClick={() =>
                  setAllergies((cur) => (on ? cur.filter((x) => x !== a) : [...cur, a]))
                }
              >
                {on ? "✓ " : ""}{a}
              </button>
            );
          })}
        </div>

        <label>Message à graver (facultatif)</label>
        <input value={messageGravure} onChange={(e) => setMessageGravure(e.target.value)} placeholder="Camille & Léa, 14·06·2026…" />

        <label>Couleur souhaitée (facultatif)</label>
        <input value={couleur} onChange={(e) => setCouleur(e.target.value)} placeholder="Rose poudré, sauge, thème champêtre…" />

        <label>Photo « comme ce style » (facultatif)</label>
        <div className="photo-ref-uploader">
          <label className="photo-ref-trigger">
            <input type="file" accept="image/*" onChange={onPhotoChange} hidden />
            {photoRefPreview ? "Remplacer la photo" : "Joindre une photo de référence"}
          </label>
          {photoRefPreview && (
            <div className="photo-ref-preview">
              <img src={photoRefPreview} alt="Aperçu" />
              <button type="button" className="photo-ref-remove"
                onClick={() => { setPhotoRef(null); setPhotoRefPreview(null); }}>
                Retirer
              </button>
            </div>
          )}
        </div>

        <label>Notes</label>
        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Toute autre préférence…" />
      </section>

      <section className="card">
        <h2><span className="step">4.</span> Vos coordonnées</h2>
        <label>Nom complet *</label>
        <input value={client.nom} onChange={(e) => setClient({ ...client, nom: e.target.value })} />
        <label>Email</label>
        <input type="email" value={client.email ?? ""} onChange={(e) => setClient({ ...client, email: e.target.value })} />
        <label>Téléphone</label>
        <input type="tel" value={client.telephone ?? ""} onChange={(e) => setClient({ ...client, telephone: e.target.value })} />
      </section>

      <section className="card summary">
        <h2><span className="step">✿</span> Récapitulatif</h2>
        <p>Total : <strong>{total.toFixed(2)} €</strong></p>
        <p>Acompte à régler maintenant ({acomptePourcent} %) : <strong>{acompte.toFixed(2)} €</strong></p>
        <p className="muted">Le solde sera réglé au retrait.</p>
        {error && <p className="error">{error}</p>}
        <button type="button" onClick={submit} disabled={loading} style={{ marginTop: 12 }}>
          {loading ? "Redirection vers Stripe…" : "Régler l’acompte"}
        </button>
      </section>

      <p className="muted" style={{ textAlign: "center", marginTop: 20, fontSize: 12 }}>
        Paiement sécurisé Stripe. Aucune donnée bancaire ne transite par notre site.
      </p>
    </div>
  );
}
