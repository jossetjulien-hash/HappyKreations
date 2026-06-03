export default function Merci() {
  return (
    <div className="container">
      <div className="card" style={{ textAlign: "center", padding: 40 }}>
        <h1>Merci !</h1>
        <p>Votre acompte a bien été reçu. Vous recevrez une confirmation par email sous peu.</p>
        <p className="muted">Nous vous recontactons rapidement pour finaliser les détails.</p>
        <a href="/" style={{ color: "var(--accent)", display: "inline-block", marginTop: 16 }}>
          Retour à la page de commande
        </a>
      </div>
    </div>
  );
}
