export default function Merci() {
  return (
    <div className="container">
      <header className="brand">
        <div className="logotype">happy<b>kreations</b></div>
        <div className="tagline">créations faites main</div>
      </header>
      <div className="card" style={{ textAlign: "center", padding: 40 }}>
        <div className="lede" style={{ fontSize: "2.2rem", marginBottom: 8 }}>Merci infiniment ✿</div>
        <p>Votre acompte a bien été reçu. Vous recevrez une confirmation par email sous peu.</p>
        <p className="muted">Nous vous recontactons rapidement pour finaliser les petits détails avec soin.</p>
        <a href="/" style={{ color: "var(--accent)", display: "inline-block", marginTop: 20, fontWeight: 700 }}>
          Retour à l'accueil
        </a>
      </div>
    </div>
  );
}
