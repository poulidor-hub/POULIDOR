#!/usr/bin/env bash
# reset-hub.sh — Réinitialiser le Hub d'un banc de test (usage DEV).
#
# Modes :
#   --db-only (défaut)  Reset de la base du Hub uniquement (le .env, les
#                       secrets JWT/SA et les certs sont conservés).
#                       ⚠️ Les apps devront se ré-enregistrer (leurs
#                       SA/client_id sont perdus).
#   --full              + suppression de HUB_base/secrets/ (clés JWT, SA,
#                       clés backup) et HUB_base/certs/ (PKI).
#   --env               + suppression de HUB_base/.env, puis ./hubctl init
#                       --force (retour à l'état « installation neuve »).
#
# Options : --yes (sans confirmation) ; --dry-run (afficher sans exécuter).
#
# ⚠️ BANC DE TEST UNIQUEMENT — ce script détruit des données. Vérifiez que
# vous n'êtes pas sur un serveur de production avant de confirmer.
set -euo pipefail

MODE="db-only"
ASSUME_YES=0
DRY_RUN=0

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

for arg in "$@"; do
  case "$arg" in
    --db-only|--full|--env) MODE="${arg#--}" ;;
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage 0 ;;
    *) echo "Argument inconnu : $arg" >&2; usage 1 ;;
  esac
done

# Racine du parc (scripts/banc/ → ../../)
PARC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HUB_DIR="$PARC_ROOT/HUB_base"
cd "$PARC_ROOT"

run() { # run <cmd...> — exécute (ou affiche en dry-run)
  if [[ $DRY_RUN -eq 1 ]]; then echo "[dry-run] $*"; else "$@"; fi
}

[[ -f "$HUB_DIR/docker-compose.yml" ]] || { echo "✗ $HUB_DIR introuvable — n'est-ce pas une racine de parc ?" >&2; exit 1; }

# ── Récap + garde-fous ────────────────────────────────────────────────
API_PORT="$(grep -E '^HUB_API_PORT=' "$HUB_DIR/.env" 2>/dev/null | cut -d= -f2 || true)"
API_PORT="${API_PORT:-8000}"
APP_ENV="$(grep -E '^APP_ENV=' "$HUB_DIR/.env" 2>/dev/null | cut -d= -f2 || true)"

echo "Réinitialisation du Hub — mode : $MODE"
echo "  Parc      : $PARC_ROOT"
echo "  Port API  : $API_PORT"
[[ -n "$APP_ENV" ]] && echo "  APP_ENV   : $APP_ENV"
[[ "$APP_ENV" == "production" ]] && \
  echo "  ⚠️ APP_ENV=production — si ce n'est PAS un banc de test, ABANDONNEZ."
echo "  Actions   :"
echo "    - arrêt des services Hub (compose down, volumes conservés sauf postgres)"
echo "    - suppression du volume hub_base_postgres_data"
[[ "$MODE" != "db-only" ]] && echo "    - suppression de HUB_base/secrets/ et HUB_base/certs/"
if [[ "$MODE" == "env" ]]; then
  echo "    - suppression de HUB_base/.env puis ./hubctl init --force"
fi
echo "    - redémarrage (make up-prod) + health check"
echo

if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
  read -rp "Tapez RESET pour confirmer : " confirmation
  [[ "$confirmation" == "RESET" ]] || { echo "Abandon."; exit 1; }
fi

# ── Exécution ─────────────────────────────────────────────────────────
echo "── 1/4 Arrêt du Hub…"
run docker compose -f "$HUB_DIR/docker-compose.yml" down

echo "── 2/4 Suppression du volume PostgreSQL…"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] docker volume rm hub_base_postgres_data"
else
  docker volume rm hub_base_postgres_data 2>/dev/null \
    || echo "  (volume absent — rien à supprimer)"
fi

if [[ "$MODE" != "db-only" ]]; then
  echo "── 3/4 Suppression secrets/ et certs/…"
  run rm -rf "$HUB_DIR/secrets" "$HUB_DIR/certs"
  run mkdir -p "$HUB_DIR/secrets" "$HUB_DIR/certs"
  if [[ "$MODE" == "env" ]]; then
    run rm -f "$HUB_DIR/.env"
    echo "── init : régénération du .env et des clés (hubctl init --force)…"
    run "$PARC_ROOT/hubctl" init --force
  fi
else
  echo "── 3/4 (secrets/ et certs/ conservés en mode db-only)"
fi

echo "── 4/4 Redémarrage…"
[[ "$MODE" == "env" ]] || run make -C "$HUB_DIR" up-prod

if [[ $DRY_RUN -eq 0 ]]; then
  echo -n "Health check"
  ok=0
  for _ in $(seq 1 30); do
    if curl -skf "http://localhost:${API_PORT}/health" >/dev/null 2>&1; then ok=1; break; fi
    echo -n "."; sleep 2
  done
  echo
  [[ $ok -eq 1 ]] && echo "✓ Hub opérationnel sur :${API_PORT}" \
                  || { echo "✗ Hub non sain après 60 s — voir make -C HUB_base logs"; exit 1; }
fi

cat <<'EOS'

⚠️ Les apps doivent maintenant se RÉ-ENREGISTRER (leurs SA / client_id
   sont perdus avec la base). Deux voies :
   • reset complet d'une app : scripts/banc/reset-app.sh <slug>
   • re-boot simple          : le backend retente l'enregistrement au
     démarrage ; si l'ancienne fiche persiste côté Hub, mettre
     FORCE_REPLACE_APP=true dans HUB_base/.env le temps du re-register
     (docker compose up -d hub-api pour recharger le .env), puis
     retirer APPS/<slug>/backend/storage/.hub_credentials et relancer
     l'app (make up).
   Détail : docs/cheatsheet-dev-banc.md §Réinitialisations.
EOS
