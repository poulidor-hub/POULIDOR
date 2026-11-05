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
# Usage : bash scripts/migration-oss.sh [--url <URL_méta>] [--yes]
# (exécuter À LA RACINE du déploiement ; rollback : le dépôt git est renommé,
#  pas supprimé — .git.pre-oss-<date>)
set -euo pipefail
URL="https://github.com/POULIDOR-Audit-Developpement/POULIDOR.git"
YES=0
[ "${1:-}" = "--url" ] && { URL="$2"; shift 2; }
[ "${1:-}" = "--yes" ] && { YES=1; shift; }

command -v git >/dev/null || { echo "git requis"; exit 1; }
[ -d ".git" ] || { echo "Exécutez à la racine du déploiement (dossier contenant .git)."; exit 1; }
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

echo "== Migration OSS — vérifications =="
echo "  remote actuel : $(git remote get-url origin 2>/dev/null || echo 'aucun')"
echo "  nouvelle URL  : $URL"
echo "  données locales conservées : .env* APPS/ storage/ secrets/ vault/ exports/ certs/ volumes Docker"
if [ "$YES" -ne 1 ]; then
  read -r -p "Continuer ? [y/N] " rep; [ "$rep" = "y" ] || { echo "abandon"; exit 1; }
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
echo "== 1/5 Sauvegarde de l'ancien dépôt git =="
mv .git ".git.pre-oss-$STAMP"

echo "== 2/5 Clone frais du méta =="
git init -q
git remote add origin "$URL"
git fetch --quiet origin
git checkout -q -B "$BRANCH" "origin/$BRANCH"

echo "== 3/5 Sous-modules (checkout forcé sur les pointeurs, données préservées) =="
git submodule update --init --recursive --force

echo "== 4/5 Nettoyage =="
echo "  ancien git conservé : .git.pre-oss-$STAMP (supprimez-le après validation)"

echo "== 5/5 Vérification =="
git status --porcelain | grep -v '^??' | head -5 || true
echo "  Rappel données : vos fichiers locaux n'ont pas été touchés."
echo "  Prochaine étape : ./hub.sh up-prod && ./hubctl doctor"
echo "  Rollback si besoin : rm -rf .git && mv .git.pre-oss-$STAMP .git"
echo "✅ Migration terminée — relancez ensuite la routine : hubctl --prod update hub"
