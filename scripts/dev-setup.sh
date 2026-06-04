#!/usr/bin/env bash
# Génère le projet Xcode avec ta signature automatiquement.
#
# - Détecte ton Team ID Apple depuis le trousseau (compte ajouté dans Xcode).
# - Le passe à xcodegen via la variable DEVELOPMENT_TEAM (lue par project.yml).
# - Régénère HappyKreations.xcodeproj puis l'ouvre.
#
# Pré-requis (à faire UNE seule fois) :
#   1. Ouvre Xcode → Settings… → Accounts → "+" → Apple ID
#      → connecte-toi avec josset.julien@icloud.com
#   2. Xcode télécharge automatiquement le certificat "Apple Development"
#      (visible dans Trousseau d'accès).
#
# Ensuite, relance ce script à chaque fois que le project.yml change.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
cd "$APP_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen introuvable. Installe-le avec : brew install xcodegen" >&2
  exit 1
fi

# Récupère le Team ID (10 caractères entre parenthèses) du premier certificat
# Apple Development valide trouvé dans le trousseau.
TEAM_ID=$(security find-identity -p codesigning -v 2>/dev/null \
  | grep -E "Apple (Development|Distribution)" \
  | head -1 \
  | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')

if [ -z "$TEAM_ID" ]; then
  cat >&2 <<'EOF'
⚠️  Aucun certificat Apple Development trouvé dans ton trousseau.

→ Ouvre Xcode → Settings… (Cmd+,) → Accounts → "+" → Apple ID
  Connecte-toi avec josset.julien@icloud.com.
  Xcode télécharge automatiquement le certificat (quelques secondes).

Puis relance ce script.

(Le projet va quand même être généré, mais sans Team de signature : il faudra
le choisir manuellement dans Xcode → onglet Signing & Capabilities.)
EOF
  TEAM_ID=""
else
  echo "✅ Team ID détecté : $TEAM_ID"
fi

export DEVELOPMENT_TEAM="$TEAM_ID"
xcodegen generate

PROJECT="$APP_DIR/HappyKreations.xcodeproj"
echo "📂 Projet généré : $PROJECT"
open "$PROJECT"
