#!/usr/bin/env bash
# reset-app.sh — Réinitialiser une application sur un banc de test (usage DEV).
#
# Usage : scripts/banc/reset-app.sh <slug> [--full] [--yes] [--dry-run]
#
#   défaut   Dé-enregistre l'app côté Hub (API admin), arrête ses
#            conteneurs, supprime ses volumes et ses credentials locaux
#            (.hub_credentials). Le dossier APPS/<slug> est conservé :
#            un simple `make up` re-boot et re-enregistre l'app.
#   --full   En plus : sauvegarde tar.gz du dossier dans
#            hubctl_cli/backups/ puis suppression de APPS/<slug>
#            (retour à scripts/create_app.sh + INITIALISE.py).
#
# ⚠️ BANC DE TEST UNIQUEMENT — ce script détruit des données.
set -euo pipefail

SLUG=""
MODE="keep"
ASSUME_YES=0
DRY_RUN=0

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) MODE="full" ;;
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage 0 ;;
    -*) echo "Argument inconnu : $1" >&2; usage 1 ;;
    *) [[ -z "$SLUG" ]] && SLUG="$1" || { echo "Un seul slug attendu." >&2; usage 1; } ;;
  esac
  shift
done

[[ -n "$SLUG" ]] || usage 1
[[ "$SLUG" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "✗ slug invalide : $SLUG" >&2; exit 1; }

PARC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$PARC_ROOT/APPS/$SLUG"
cd "$PARC_ROOT"

run() { if [[ $DRY_RUN -eq 1 ]]; then echo "[dry-run] $*"; else "$@"; fi; }

# ── Credentials admin : .secrets puis fallback HUB_base/.env ─────────
ADMIN_USER=""; ADMIN_PASS=""; BASE_URL=""
if [[ -f "$PARC_ROOT/.secrets" ]]; then
  # shellcheck disable=SC1091
  set -a; . "$PARC_ROOT/.secrets" >/dev/null 2>&1 || true; set +a
  ADMIN_USER="${HUB_ADMIN_USERNAME:-}"; ADMIN_PASS="${HUB_ADMIN_PASSWORD:-}"; BASE_URL="${HUB_BASE_URL:-}"
fi
if [[ -z "$ADMIN_USER$ADMIN_PASS" && -f "$PARC_ROOT/HUB_base/.env" ]]; then
  ADMIN_USER="$(grep -E '^ADMIN_USERNAME=' "$PARC_ROOT/HUB_base/.env" | cut -d= -f2- || true)"
  ADMIN_PASS="$(grep -E '^ADMIN_PASSWORD=' "$PARC_ROOT/HUB_base/.env" | cut -d= -f2- || true)"
fi
API_PORT="$(grep -E '^HUB_API_PORT=' "$PARC_ROOT/HUB_base/.env" 2>/dev/null | cut -d= -f2 || true)"
API_PORT="${API_PORT:-8000}"
[[ -z "$BASE_URL" ]] && BASE_URL="http://localhost:${API_PORT}"

echo "Reset de l'app « $SLUG » (mode : $MODE)"
echo "  Parc : $PARC_ROOT  •  API : $BASE_URL"
[[ -d "$APP_DIR" ]] || echo "  ⚠️ dossier APPS/$SLUG absent — dé-enregistrement seul."
if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
  read -rp "Tapez RESET pour confirmer : " c
  [[ "$c" == "RESET" ]] || { echo "Abandon."; exit 1; }
fi

# ── 1. Dé-enregistrement côté Hub (best effort) ───────────────────────
if [[ -n "$ADMIN_USER" && -n "$ADMIN_PASS" ]]; then
  echo "── Dé-enregistrement côté Hub…"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] login admin + DELETE /api/apps/{id} pour $SLUG"
  else
    TOKEN="$(curl -s -X POST "$BASE_URL/api/auth/token" \
      -d "username=$ADMIN_USER" -d "password=$ADMIN_PASS" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)"
    if [[ -z "$TOKEN" ]]; then
      echo "  ⚠️ login admin impossible — dé-enregistrez via l'UI (§Administration → Applications)."
    else
      APP_ID="$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/apps" \
        | python3 -c "import json,sys
apps=json.load(sys.stdin)
apps=apps if isinstance(apps,list) else apps.get('apps',apps.get('items',[]))
print(next((str(a.get('id')) for a in apps if a.get('slug')=='$SLUG'),''))" 2>/dev/null || true)"
      if [[ -z "$APP_ID" ]]; then
        echo "  (aucune fiche $SLUG côté Hub — rien à supprimer)"
      else
        CODE="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
          -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/apps/$APP_ID")"
        echo "  DELETE /api/apps/$APP_ID → HTTP $CODE"
      fi
    fi
  fi
else
  echo "── Pas d'credentials admin trouvés (.secrets / HUB_base/.env) —"
  echo "   dé-enregistrez l'app via l'UI avant/après ce script."
fi

# ── 2. Arrêt des conteneurs + volumes ─────────────────────────────────
if [[ -d "$APP_DIR" ]]; then
  echo "── Arrêt des conteneurs de $SLUG (ateliers inclus)…"
  if [[ -f "$APP_DIR/.workshop.env" ]]; then
    run docker compose -f "$APP_DIR/docker-compose.yml" --env-file "$APP_DIR/.workshop.env" \
      -p "${SLUG}-ws" down -v --remove-orphans
  fi
  ( cd "$APP_DIR" && run docker compose down -v --remove-orphans ) \
    || echo "  ⚠️ compose down a échoué (stack déjà arrêtée ?)"

  # Balayage par LABEL de projet compose (jamais par préfixe de nom :
  # un slug proche d'un autre projet ne doit rien matché en dehors de
  # <slug> et <slug>-ws).
  echo "── Balayage des volumes résiduels des projets « ${SLUG} » / « ${SLUG}-ws »…"
  sweep_volumes() {
    local proj="$1"
    docker volume ls -q --filter "label=com.docker.compose.project=${proj}"
  }
  if [[ $DRY_RUN -eq 1 ]]; then
    { sweep_volumes "$SLUG"; sweep_volumes "${SLUG}-ws"; } | sort -u \
      | sed 's/^/[dry-run] docker volume rm /' || true
  else
    { sweep_volumes "$SLUG"; sweep_volumes "${SLUG}-ws"; } | sort -u | while read -r v; do
      docker volume rm "$v" && echo "  volume supprimé : $v"
    done || true
  fi
else
  echo "── Dossier APPS/$SLUG absent : pas de conteneur/volume à balayer."
fi

# ── 3. Credentials locaux ─────────────────────────────────────────────
if [[ -f "$APP_DIR/backend/storage/.hub_credentials" ]]; then
  run rm -f "$APP_DIR/backend/storage/.hub_credentials"
  echo "  .hub_credentials supprimé (re-registration propre au prochain boot)"
fi

# ── 4. Mode --full : backup + suppression du dossier ──────────────────
if [[ "$MODE" == "full" && -d "$APP_DIR" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  BAK="$PARC_ROOT/hubctl_cli/backups/${SLUG}-reset-${TS}.tar.gz"
  echo "── Backup $BAK…"
  run mkdir -p "$(dirname "$BAK")"
  run tar -czf "$BAK" -C "$PARC_ROOT/APPS" "$SLUG"
  run rm -rf "$APP_DIR"
fi

echo
echo "✓ Reset $SLUG terminé."
if [[ "$MODE" == "full" ]]; then
  echo "  Recréer : ./scripts/create_app.sh $SLUG  puis INITIALISE.py (cf. cheatsheet-dev-banc.md)"
else
  echo "  Re-boot : cd APPS/$SLUG && make up   (l'app se ré-enregistre au démarrage)"
fi
