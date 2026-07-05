#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$ROOT_DIR/HUBapp_TEMPLATE_base"
APPS_DIR="$ROOT_DIR/APPS"

usage() {
  echo "Usage: $0 <app-name>"
  echo ""
  echo "Copie le template HUBapp_TEMPLATE_base dans APPS/<app-name>."
  echo "Le nom doit commencer par une lettre minuscule, contenir uniquement"
  echo "des caracteres a-z, 0-9, - ou _."
  exit 1
}

[ $# -eq 1 ] || usage

APP_NAME="$1"

if ! echo "$APP_NAME" | grep -Eq '^[a-z][a-z0-9_-]*$'; then
  echo "❌ Nom invalide: '$APP_NAME'"
  echo "   Doit commencer par une lettre minuscule et ne contenir que a-z, 0-9, - ou _"
  exit 1
fi

if [ -d "$APPS_DIR/$APP_NAME" ]; then
  echo "❌ L'application '$APP_NAME' existe deja dans APPS/"
  exit 1
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "❌ Template introuvable: $TEMPLATE_DIR"
  exit 1
fi

# Garde-fou : le submodule template doit être initialisé (pas un dossier vide)
if [ ! -f "$TEMPLATE_DIR/Makefile" ] || [ ! -d "$TEMPLATE_DIR/backend" ]; then
  echo "❌ Le template n'est pas initialisé."
  echo "   Lancez d'abord : git submodule update --init HUBapp_TEMPLATE_base"
  exit 1
fi

mkdir -p "$APPS_DIR"

# Copie du template SANS son .git (sinon l'app hérite du dépôt template).
# On utilise rsync si dispo, sinon cp + nettoyage.
if command -v rsync &> /dev/null; then
  rsync -a --exclude '.git' "$TEMPLATE_DIR/" "$APPS_DIR/$APP_NAME/"
else
  cp -r "$TEMPLATE_DIR" "$APPS_DIR/$APP_NAME"
  rm -rf "$APPS_DIR/$APP_NAME/.git"
fi
# Au cas où des sous-répertoires contiendraient leur propre .git
find "$APPS_DIR/$APP_NAME" -name ".git" -type d -prune -exec rm -rf {} + 2>/dev/null || true

cat >> "$APPS_DIR/$APP_NAME/.env" <<'EOF'

# --- APPS/ path overrides (car le Makefile est un niveau plus profond) ---
HUB_STACK_DIR=../..
HUB_MCP_SRC=../../hub-mcp/hub_mcp
EOF

echo ""
echo "✅ Application '$APP_NAME' creee dans APPS/$APP_NAME/"
echo "   ➜ cd APPS/$APP_NAME && python INITIALISE.py"
