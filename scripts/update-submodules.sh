#!/usr/bin/env bash
# =============================================================================
# update-submodules.sh — aligne TOUS les sous-modules sur les pointeurs du méta.
#
# Filet de sécurité quand `./hubctl update "*"` ne fonctionne pas (hub down, réseau,
# cas particulier…) : refait manuellement le cœur de la mise à jour, soit
#
#     git submodule update --init --recursive
#
# après avoir (par défaut) rafraîchi le méta-repo sur origin/main — car aligner
# les sous-modules sur des pointeurs LOCAUX périmés ne met rien à jour.
#
# Usage :
#   scripts/update-submodules.sh              # fetch + ff main + alignement
#   scripts/update-submodules.sh --no-fetch   # aligne sur les pointeurs LOCAUX
#   scripts/update-submodules.sh --force      # écarte les modifs locales des sous-modules
#   scripts/update-submodules.sh --yes        # sans confirmation (utile avec --force)
#
# Garde-fous :
#   - à exécuter depuis la branche `main` du méta-repo (c'est elle qui porte
#     les pointeurs de référence) ;
#   - par défaut, un sous-module avec des modifications locales N'EST PAS
#     écrasé (git refuse) — `--force` le fait explicitement, avec confirmation.
# =============================================================================
set -euo pipefail

NO_FETCH=0; FORCE=0; YES=0
for arg in "$@"; do
  case "$arg" in
    --no-fetch) NO_FETCH=1 ;;
    --force)    FORCE=1 ;;
    --yes)      YES=1 ;;
    *) echo "❌ Option inconnue : $arg (voir l'en-tête du script)"; exit 1 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"
[ -f .gitmodules ] || { echo "❌ Racine du méta-repo introuvable (.gitmodules absent)"; exit 1; }

BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "❌ Branche courante : '$BRANCH' — passe sur main d'abord : git checkout main"
  exit 1
fi

echo "── État AVANT ──────────────────────────────────────────────"
git submodule status || true
# légende : ' ' aligné · '+' diffère du pointeur · '-' non initialisé · 'U' conflit

if [ "$NO_FETCH" -eq 0 ]; then
  echo "── Méta : fetch + fast-forward origin/main ─────────────────"
  git fetch origin
  BEHIND=$(git rev-list --count HEAD..origin/main)
  if [ "$BEHIND" -eq 0 ]; then
    echo "✅ main déjà à jour avec origin/main"
  elif git merge --ff-only origin/main; then
    echo "✅ main avancé de $BEHIND commit(s)"
  else
    echo "⚠️  Fast-forward refusé (WIP local en conflit avec origin/main)."
    echo "    J'aligne quand même les sous-modules sur les pointeurs LOCAUX"
    echo "    ($(git rev-parse --short HEAD)) — règle ton WIP puis relance le"
    echo "    script pour terminer la mise à jour."
  fi
else
  echo "── --no-fetch : alignement sur les pointeurs LOCAUX ────────"
fi

echo "── Alignement : git submodule update --init --recursive ────"
if [ "$FORCE" -eq 1 ]; then
  if [ "$YES" -ne 1 ]; then
    read -rp "⚠️  --force écarte les modifications locales des sous-modules. Confirmer ? [o/N] " r
    [[ "$r" =~ ^[oO]$ ]] || { echo "annulé"; exit 1; }
  fi
  git submodule update --init --recursive --force
else
  git submodule update --init --recursive
fi

echo "── État APRÈS ──────────────────────────────────────────────"
git submodule status || true

echo "── Versions des sous-modules ───────────────────────────────"
for f in HUB_base/VERSION HUBapp_TEMPLATE_base/VERSION hubctl_src/VERSION HUBsocle/VERSION; do
  [ -f "$f" ] && echo "  $(dirname "$f") : $(tr -d '[:space:]' < "$f")"
done
if [ -f hub-mcp/pyproject.toml ]; then
  echo "  hub-mcp : $(grep -m1 '^version' hub-mcp/pyproject.toml | cut -d= -f2 | tr -d ' "')"
fi
if [ -f HUBCSS/package.json ]; then
  echo "  HUBCSS  : $(python3 -c "import json;print(json.load(open('HUBCSS/package.json'))['version'])" 2>/dev/null || echo '?')"
fi

echo ""
echo "✅ Sous-modules alignés sur les pointeurs du méta ($(git rev-parse --short HEAD))."
echo "   Rappel : les apps (APPS/*) ne sont PAS des sous-modules — leurs mises à jour"
echo "   passent par git (dans chaque app) ou ./hubctl update \"*\"."
