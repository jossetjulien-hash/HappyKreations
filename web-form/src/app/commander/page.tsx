"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import type { Produit, CapaciteJour, ConfigItem, LigneCommande, ClientInfo, ZoneLivraison, PlageBlocage } from "@/lib/types";

const SUPABASE_FN_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/creer-paiement`;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

const ALLERGENES = ["Gluten", "Lait", "Œuf", "Fruits à coque", "Arachide", "Soja", "Sésame"];

export default function Page() {
  const [produits, setProduits] = useState<Produit[]>([]);
  const [capacites, setCapacites] = useState<CapaciteJour[]>([]);
  const [config, setConfig] = useState<Record<string, string>>({});
  const [zones, setZones] = useState<ZoneLivraison[]>([]);
  const [plagesBlocage, setPlagesBlocage] = useState<PlageBlocage[]>([]);
  const [modeRemise, setModeRemise] = useState<"retrait" | "livraison">("retrait");
  const [zoneId, setZoneId] = useState<string | null>(null);
  const [adresseLivraison, setAdresseLivraison] = useState("");
  const [adresseCoords, setAdresseCoords] = useState<{ lat: number; lon: number } | null>(null);
  const [adresseSuggestions, setAdresseSuggestions] = useState<Array<{
    id: string; label: string; postcode: string; city: string; lat: number; lon: number;
  }>>([]);
  const [adresseRecherche, setAdresseRecherche] = useState(false);
  // Pour chaque produit : map { parfum → quantité }.
  // - Produits sans déclinaisons → clé unique "" (vide)
  // - Produits avec déclinaisons → une clé par parfum sélectionné
  const [quantites, setQuantites] = useState<Record<string, Record<string, number>>>({});
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
  const [codeInput, setCodeInput] = useState("");
  const [codeApplique, setCodeApplique] = useState<{ id: string; type: string; valeur: number; libelle: string } | null>(null);
  const [codeError, setCodeError] = useState<string | null>(null);
  const [verifCode, setVerifCode] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function appliquerCode() {
    const c = codeInput.trim().toUpperCase();
    if (!c) return;
    setVerifCode(true); setCodeError(null);
    try {
      // La policy anon_code_promo_valider filtre déjà actif + dates +
      // utilisations : si on récupère une ligne, c'est qu'il est valide.
      const { data, error } = await supabase
        .from("code_promo")
        .select("id, type, valeur")
        .ilike("code", c)
        .maybeSingle();
      if (error || !data) {
        setCodeError("Code invalide ou expiré.");
        setCodeApplique(null);
      } else {
        const lib = data.type === "fixe"
          ? `${Number(data.valeur).toFixed(2).replace(".", ",")} €`
          : `${Math.round(Number(data.valeur))} %`;
        setCodeApplique({ id: data.id, type: data.type, valeur: Number(data.valeur), libelle: lib });
      }
    } catch {
      setCodeError("Vérification impossible.");
    } finally {
      setVerifCode(false);
    }
  }

  // Debounce BAN address autocomplete
  useEffect(() => {
    if (modeRemise !== "livraison") { setAdresseSuggestions([]); return; }
    const q = adresseLivraison.trim();
    if (q.length < 3) { setAdresseSuggestions([]); return; }
    setAdresseRecherche(true);
    const timer = setTimeout(async () => {
      try {
        const url = `https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(q)}&limit=6&lat=-21.115&lon=55.536`;
        const r = await fetch(url);
        const j = await r.json();
        const feats = (j?.features ?? []) as Array<{
          properties: { id: string; label: string; postcode?: string; city?: string };
          geometry: { coordinates: [number, number] };
        }>;
        const filtered = feats
          .filter((f) => f.properties.postcode?.startsWith("974"))
          .map((f) => ({
            id: f.properties.id,
            label: f.properties.label,
            postcode: f.properties.postcode ?? "",
            city: f.properties.city ?? "",
            lon: f.geometry.coordinates[0],
            lat: f.geometry.coordinates[1],
          }));
        setAdresseSuggestions(filtered);
      } catch { /* ignore */ }
      finally { setAdresseRecherche(false); }
    }, 300);
    return () => clearTimeout(timer);
  }, [adresseLivraison, modeRemise]);

  function appliquerSuggestionAdresse(s: { label: string; postcode: string; lat: number; lon: number }) {
    setAdresseLivraison(s.label);
    setAdresseCoords({ lat: s.lat, lon: s.lon });
    setAdresseSuggestions([]);
    // Détection auto de la zone selon le code postal — modifiable manuellement
    const z = zones.find((zz) => zz.codes_postaux?.includes(s.postcode));
    if (z) setZoneId(z.id);
  }

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
      const [{ data: p }, { data: c }, { data: cf }, { data: z }, { data: pb }] = await Promise.all([
        supabase.from("produit").select("*").eq("visible_formulaire", true).eq("actif", true),
        supabase.from("capacite_jour").select("*"),
        supabase.from("config").select("*"),
        supabase.from("zone_livraison").select("*").eq("actif", true).gt("tarif", 0).order("ordre"),
        supabase.from("plage_blocage").select("*").eq("actif", true).order("date_debut"),
      ]);
      setProduits(p ?? []);
      setCapacites(c ?? []);
      setConfig(Object.fromEntries((cf as ConfigItem[] ?? []).map((x) => [x.cle, x.valeur])));
      setZones((z ?? []) as ZoneLivraison[]);
      setPlagesBlocage((pb ?? []) as PlageBlocage[]);
    })();
  }, []);

  // Helper : true si la date AAAA-MM-JJ tombe dans une plage active
  function isDateBloquee(iso: string): boolean {
    return plagesBlocage.some((p) => iso >= p.date_debut && iso <= p.date_fin);
  }

  // Plages dont la période recouvre aujourd'hui (pour la bannière)
  const aujourdhui = new Date().toISOString().slice(0, 10);
  const plagesEnCours = plagesBlocage.filter(
    (p) => p.message_client && aujourdhui >= p.date_debut && aujourdhui <= p.date_fin);

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
      const ok = !(cap?.bloque ?? false) && !isDateBloquee(iso);
      out.push({ date: iso, jour: d.getDate(), mois: moisFmt.format(d), ok });
    }
    return out;
  }, [capacites, delaiMini, plagesBlocage]);

  // Une ligne par couple (produit, parfum) avec qte > 0
  const lignes: LigneCommande[] = Object.entries(quantites).flatMap(([produit_id, parfumMap]) =>
    Object.entries(parfumMap)
      .filter(([, qte]) => qte > 0)
      .map(([decli, qte]) => ({
        produit_id,
        quantite: qte,
        declinaison: decli || undefined,
      }))
  );

  // Quantité totale (toutes décli confondues) pour un produit donné
  function qteTotale(produitId: string): number {
    const m = quantites[produitId] ?? {};
    return Object.values(m).reduce((s, n) => s + (n || 0), 0);
  }
  // Nombre de parfums actifs (qte > 0) pour un produit
  function nbParfumsActifs(produitId: string): number {
    const m = quantites[produitId] ?? {};
    return Object.values(m).filter((n) => n > 0).length;
  }

  const totalBrut = lignes.reduce((s, l) => {
    const p = produits.find((pp) => pp.id === l.produit_id);
    return s + (p?.prix_vente ?? 0) * l.quantite;
  }, 0);
  const remise = codeApplique
    ? (codeApplique.type === "fixe"
        ? Math.min(codeApplique.valeur, totalBrut)
        : Math.round(totalBrut * codeApplique.valeur) / 100)
    : 0;
  const fraisLivraison = modeRemise === "livraison"
    ? (zones.find((z) => z.id === zoneId)?.tarif ?? 0)
    : 0;
  const total = Math.max(0, totalBrut - remise) + fraisLivraison;
  const acompte = Math.round(total * acomptePourcent) / 100;

  /// Modifie la quantité d'un parfum donné pour un produit.
  /// Pour un produit sans déclinaisons, on utilise decli = "" (clé vide).
  function setParfumQte(p: Produit, decli: string, delta: number) {
    setQuantites((q) => {
      const cur = q[p.id] ?? {};
      const prev = cur[decli] ?? 0;
      let next = prev + delta;
      // Premier ajout sur ce parfum + min global défini → on saute au min
      // (uniquement si c'est le seul parfum actif et qte totale = 0)
      const totalActuel = Object.values(cur).reduce((s, n) => s + (n || 0), 0);
      if (totalActuel === 0 && delta > 0 && p.qte_min && p.qte_min > 1) {
        next = p.qte_min;
      }
      // Plafond qte_max : on borne la SOMME totale du produit
      if (p.qte_max != null) {
        const autresParfums = totalActuel - prev;
        next = Math.min(next, Math.max(0, p.qte_max - autresParfums));
      }
      next = Math.max(0, next);
      const nouvelle = { ...cur, [decli]: next };
      // Si on remet à 0 et qu'il n'y a aucun autre parfum, on nettoie
      const totalNouveau = Object.values(nouvelle).reduce((s, n) => s + (n || 0), 0);
      if (next === 0 && totalNouveau === 0) {
        return { ...q, [p.id]: {} };
      }
      return { ...q, [p.id]: nouvelle };
    });
  }

  async function submit() {
    setError(null);
    if (!client.nom.trim()) return setError("Indiquez votre nom.");
    if (!client.email && !client.telephone) return setError("Email ou téléphone requis.");
    if (!dateRetrait) return setError("Choisissez une date de retrait.");
    if (lignes.length === 0) return setError("Sélectionnez au moins un produit.");
    if (modeRemise === "livraison" && !zoneId) {
      return setError("Choisissez votre zone de livraison.");
    }
    if (modeRemise === "livraison" && !adresseLivraison.trim()) {
      return setError("Renseignez votre adresse de livraison.");
    }
    // Contrôle min/max et nombre de parfums : agrégés par produit
    const totauxParProduit = new Map<string, number>();
    const parfumsParProduit = new Map<string, Set<string>>();
    for (const l of lignes) {
      totauxParProduit.set(l.produit_id, (totauxParProduit.get(l.produit_id) ?? 0) + l.quantite);
      if (!parfumsParProduit.has(l.produit_id)) parfumsParProduit.set(l.produit_id, new Set());
      parfumsParProduit.get(l.produit_id)!.add(l.declinaison ?? "");
    }
    for (const [pid, total] of totauxParProduit) {
      const p = produits.find((pp) => pp.id === pid);
      if (!p) continue;
      const unite = p.categorie === "cornet" ? "cornets" : "pièces";
      if (p.qte_min != null && total < p.qte_min) {
        return setError(`${p.nom} : minimum ${p.qte_min} ${unite}.`);
      }
      if (p.qte_max != null && total > p.qte_max) {
        return setError(`${p.nom} : maximum ${p.qte_max} ${unite}.`);
      }
      const nbParfums = parfumsParProduit.get(pid)?.size ?? 0;
      if (p.max_parfums_par_commande >= 1 && nbParfums > p.max_parfums_par_commande) {
        return setError(`${p.nom} : maximum ${p.max_parfums_par_commande} parfum${p.max_parfums_par_commande > 1 ? "s" : ""} par commande.`);
      }
    }

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
          code_promo_id: codeApplique?.id ?? null,
          mode_remise: modeRemise,
          zone_livraison_id: modeRemise === "livraison" ? zoneId : null,
          adresse_livraison: modeRemise === "livraison" ? adresseLivraison : null,
          latitude: modeRemise === "livraison" ? adresseCoords?.lat ?? null : null,
          longitude: modeRemise === "livraison" ? adresseCoords?.lon ?? null : null,
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
        <a href="/" className="back-home" aria-label="Retour à l'accueil">← Retour à l'accueil</a>
        <img src="/icon.png" alt="Logo HappyKreations" className="brand-logo" width={64} height={64} />
        <svg className="sprig" style={{display:'none'}} viewBox="0 0 80 80" fill="none" aria-hidden="true">
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

      {plagesEnCours.length > 0 && (
        <div className="banniere-conges">
          <strong>✿ Information</strong>
          {plagesEnCours.map((p) => (
            <p key={p.id} style={{ margin: "4px 0 0" }}>{p.message_client}</p>
          ))}
        </div>
      )}

      <section className="card">
        <h2><span className="step">1.</span> Vos produits</h2>
        {produits.length === 0 && <p className="muted">Catalogue en cours de chargement…</p>}
        {produits.map((p) => {
          const total = qteTotale(p.id);
          const nbActifs = nbParfumsActifs(p.id);
          const maxParfums = Math.max(1, p.max_parfums_par_commande);
          const multiParfums = p.declinaisons.length > 0 && maxParfums >= 2;
          return (
            <div key={p.id} className="produit-card produit-card-multi">
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
                {(p.qte_min != null || p.qte_max != null) && (
                  <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
                    {p.qte_min != null && p.qte_max != null
                      ? `Commande de ${p.qte_min} à ${p.qte_max} ${p.categorie === "cornet" ? "cornets" : "pièces"}`
                      : p.qte_min != null
                        ? `Minimum ${p.qte_min} ${p.categorie === "cornet" ? "cornets" : "pièces"}`
                        : `Maximum ${p.qte_max} ${p.categorie === "cornet" ? "cornets" : "pièces"}`}
                  </div>
                )}
                {multiParfums && (
                  <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
                    Jusqu'à {maxParfums} parfums au choix
                  </div>
                )}

                {p.declinaisons.length === 0 ? (
                  // Pas de déclinaisons → un seul contrôle ± sur "" (clé vide)
                  <div className="qte-control" style={{ marginTop: 8 }}>
                    <button type="button"
                      onClick={() => setParfumQte(p, "", -1)}
                      disabled={(quantites[p.id]?.[""] ?? 0) === 0}>−</button>
                    <span style={{ minWidth: 24, textAlign: "center" }}>
                      {quantites[p.id]?.[""] ?? 0}
                    </span>
                    <button type="button"
                      onClick={() => setParfumQte(p, "", +1)}
                      disabled={p.qte_max != null && total >= p.qte_max}>+</button>
                  </div>
                ) : (
                  // Mono ou multi-parfums : une ligne par parfum
                  <div style={{ marginTop: 8 }}>
                    {p.declinaisons.map((d) => {
                      const qte = quantites[p.id]?.[d] ?? 0;
                      const dejaActif = qte > 0;
                      const peutAjouter = dejaActif || nbActifs < maxParfums;
                      return (
                        <div key={d} className="parfum-row">
                          <span className="parfum-nom">{d}</span>
                          <div className="qte-control">
                            <button type="button"
                              onClick={() => setParfumQte(p, d, -1)}
                              disabled={qte === 0}>−</button>
                            <span style={{ minWidth: 24, textAlign: "center" }}>{qte}</span>
                            <button type="button"
                              onClick={() => setParfumQte(p, d, +1)}
                              disabled={!peutAjouter || (p.qte_max != null && total >= p.qte_max)}>+</button>
                          </div>
                        </div>
                      );
                    })}
                    {total > 0 && (
                      <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>
                        Total : <strong>{total}</strong>
                        {nbActifs > 1 ? ` (${nbActifs} parfums)` : ""}
                      </div>
                    )}
                  </div>
                )}
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

      {zones.length > 0 && (
        <section className="card">
          <h2><span className="step">5.</span> Comment recevez-vous votre commande ?</h2>
          <div className="chips">
            <button type="button"
              className={`chip ${modeRemise === "retrait" ? "on" : ""}`}
              onClick={() => { setModeRemise("retrait"); setZoneId(null); }}>
              {modeRemise === "retrait" ? "✓ " : ""}Retrait sur place (gratuit)
            </button>
            <button type="button"
              className={`chip ${modeRemise === "livraison" ? "on" : ""}`}
              onClick={() => setModeRemise("livraison")}>
              {modeRemise === "livraison" ? "✓ " : ""}Livraison
            </button>
          </div>
          {modeRemise === "livraison" && (
            <>
              <label style={{ marginTop: 12 }}>Adresse de livraison</label>
              <div style={{ position: "relative" }}>
                <input
                  value={adresseLivraison}
                  onChange={(e) => {
                    setAdresseLivraison(e.target.value);
                    setAdresseCoords(null);
                  }}
                  placeholder="Commencez à taper votre adresse…"
                  autoComplete="off"
                />
                {adresseSuggestions.length > 0 && (
                  <ul className="adresse-suggestions">
                    {adresseSuggestions.map((s) => (
                      <li key={s.id}>
                        <button type="button"
                          onClick={() => appliquerSuggestionAdresse(s)}>
                          <strong>{s.label}</strong>
                          <span className="muted"> · {s.postcode} {s.city}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
                {adresseRecherche && (
                  <span className="muted" style={{ fontSize: 12 }}>Recherche…</span>
                )}
              </div>

              <label style={{ marginTop: 12 }}>Votre zone</label>
              <select value={zoneId ?? ""} onChange={(e) => setZoneId(e.target.value || null)}>
                <option value="">— Choisissez votre zone —</option>
                {zones.map((z) => (
                  <option key={z.id} value={z.id}>
                    {z.nom} — {z.tarif.toFixed(2)} €
                  </option>
                ))}
              </select>
              {zoneId && (
                <p className="muted" style={{ marginTop: 8 }}>
                  Frais de livraison : <strong>{fraisLivraison.toFixed(2)} €</strong>
                </p>
              )}
            </>
          )}
        </section>
      )}

      <section className="card summary">
        <h2><span className="step">✿</span> Récapitulatif</h2>

        <p>Sous-total produits : <strong>{totalBrut.toFixed(2)} €</strong></p>
        {fraisLivraison > 0 && (
          <p>Frais de livraison : <strong>{fraisLivraison.toFixed(2)} €</strong></p>
        )}

        {/* Code promo */}
        <label style={{ marginTop: 12 }}>Code promo (facultatif)</label>
        {codeApplique ? (
          <div className="code-applique">
            <span>
              <strong>{codeInput.toUpperCase()}</strong> appliqué — réduction {codeApplique.libelle}
              {" "}(−{remise.toFixed(2)} €)
            </span>
            <button type="button" className="link-action"
              onClick={() => { setCodeApplique(null); setCodeInput(""); setCodeError(null); }}>
              Retirer
            </button>
          </div>
        ) : (
          <div className="code-row">
            <input value={codeInput}
              onChange={(e) => { setCodeInput(e.target.value); setCodeError(null); }}
              placeholder="FETEMERES2026"
              style={{ textTransform: "uppercase" }} />
            <button type="button" className="secondary"
              onClick={appliquerCode}
              disabled={verifCode || codeInput.trim().length === 0}>
              {verifCode ? "..." : "Appliquer"}
            </button>
          </div>
        )}
        {codeError && <p className="error" style={{ marginTop: 6 }}>{codeError}</p>}

        <p>Total : <strong>{total.toFixed(2)} €</strong></p>
        <p>Acompte à régler maintenant ({acomptePourcent} %) : <strong>{acompte.toFixed(2)} €</strong></p>
        <p className="muted">Le solde sera réglé au retrait.</p>
        <div className="info-paiement">
          <strong>🔒 Paiement sécurisé par Stripe</strong>
          <p>
            Après avoir cliqué, vous serez redirigé·e vers la page de paiement.
            Votre banque vous demandera de confirmer la transaction (notification
            dans son application, SMS, ou Face/Touch ID). C’est une étape normale
            et obligatoire — gardez votre téléphone à portée de main.
          </p>
          <p className="muted" style={{ marginTop: 6, fontSize: 12 }}>
            En cas de souci, contactez-nous et nous vous renverrons un lien de paiement.
          </p>
        </div>
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
