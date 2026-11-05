#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# =============================================================================
# Migration unique vers l'historique post-purge open source (méta 0.80.14+).
# =============================================================================
# Contexte : l'historique git a été réécrit (purge de secrets avant open
# source). Un déploiement existant ne peut plus faire `hubctl update` :
# son clone n'a plus d'ancêtre commun avec le remote.
#
# Ce script remplace le dépôt git par un clone frais SANS toucher aux données :
#   conservés (non versionnés) : .env*, APPS/, storage/, secrets/, vault/,
#   exports/, certs/, backups, volumes Docker (intacts).
#
# Auth : l'URL origin EXISTANTE de votre déploiement est réutilisée (SSH/clé de
# déploiement). Override possible : --url <URL>. En cas d'échec, l'ancien .git
# est restauré automatiquement (rollback sans perte).
#
# Récupération du script depuis un déploiement existant (pas besoin de merge) :
#   git fetch origin && git show origin/main:scripts/migration-oss.sh > scripts/migration-oss.sh
# (ou après publication publique : curl -fsSL https://raw.githubusercontent.com/POULIDOR-Audit-Developpement/POULIDOR/main/scripts/migration-oss.sh)
#
# Usage : bash scripts/migration-oss.sh [--url <URL_méta>] [--yes]
set -euo pipefail
URL=""; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    *) echo "option inconnue: $1"; exit 1 ;;
  esac
done

command -v git >/dev/null || { echo "git requis"; exit 1; }
[ -d ".git" ] || { echo "Exécutez à la racine du déploiement (dossier contenant .git)."; exit 1; }

# Priorité à l'authentification déjà en place : URL origin existante > --url > HTTPS défaut
OLD_URL="$(git config --get remote.origin.url 2>/dev/null || echo '')"
[ -z "$URL" ] && [ -n "$OLD_URL" ] && URL="$OLD_URL"
[ -z "$URL" ] && URL="https://github.com/POULIDOR-Audit-Developpement/POULIDOR.git"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
BRANCH="${BRANCH:-main}"

echo "== Migration OSS — vérifications =="
echo "  remote actuel      : ${OLD_URL:-aucun}"
echo "  URL utilisée       : $URL"
echo "  branche cible      : $BRANCH"
echo "  conservés (hors git): .env* APPS/ storage/ secrets/ vault/ exports/ certs/ volumes Docker"
if [ "$YES" -ne 1 ]; then
  read -r -p "Continuer ? [y/N] " rep; [ "$rep" = "y" ] || { echo "abandon"; exit 1; }
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
rollback() {
  echo "❌ échec — ROLLBACK automatique de votre dépôt git d'origine"
  rm -rf .git
  mv ".git.pre-oss-$STAMP" .git
  echo "   État d'origine restauré. Testez l'accès au remote : git fetch origin"
  exit 1
}

echo "== 1/5 Sauvegarde de l'ancien dépôt git =="
mv .git ".git.pre-oss-$STAMP"

echo "== 2/5 Clone frais du méta (URL $URL) =="
git init -q
git remote add origin "$URL"
git fetch --quiet origin || rollback
# -f : les fichiers non versionnés qui collident avec le nouvel arbre (ex. le
# script de migration lui-même) sont écrasés par la version du dépôt ; les
# données hors arbre (.env*, APPS/, storage/…) ne sont jamais touchées.
git checkout -q -f -B "$BRANCH" "origin/$BRANCH" || rollback

echo "== 3/5 Sous-modules (checkout forcé sur les pointeurs, données préservées) =="
git submodule update --init --recursive --force || rollback

echo "== 4/5 Réalignement des sous-modules =="
git submodule foreach --recursive 'git fetch --quiet origin && git checkout -q main 2>/dev/null || true' || true

echo "== 5/5 Vérification =="
echo "  ancien git conservé : .git.pre-oss-$STAMP (supprimez-le après validation)"
echo "  Prochaine étape : ./hub.sh up-prod && ./hubctl doctor"
echo "✅ Migration terminée — la routine officielle redevient : hubctl --prod update hub"
