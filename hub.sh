#!/usr/bin/env bash
# ============================================================================
# hub.sh — Exploitation du HUB depuis la racine POULIDOR (sans aller dans HUB_base)
#
# Sous-commandes :
#   update   [--dev] [--dry-run]  git pull --ff-only + submodules + build + up
#   start    [--dev] [--dry-run]  démarre le stack (up -d, sans build)
#   stop     [--dev] [--dry-run]  arrête le stack (down — JAMAIS -v : volumes préservés)
#   restart  [--dev] [--dry-run]  redémarre les conteneurs (compose restart)
#   rebuild  [--dev] [--dry-run]  make build + up -d (sans git pull)
#   logs     [--dev]              logs -f --tail=100 (Ctrl-C pour quitter)
#   status   [--dev]              état des conteneurs + health + version API
#
# `update-hub.sh` est un alias rétrocompatible de `hub.sh update`.
#
# ⚠️ stop/down ne passe JAMAIS -v : détruire les volumes (hub-db etc.)
#    détruirait les données. C'est une règle d'or du parc.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB="$ROOT/HUB_base"
MODE="prod"
DRY_RUN=0
CMD=""

die() { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }

run() {
    echo "+ $*"
    if [ "$DRY_RUN" != "1" ]; then
        "$@"
    fi
}

usage() {
    cat <<'EOF'
hub.sh — Exploitation du HUB depuis la racine POULIDOR

Usage : ./hub.sh <commande> [--dev] [--dry-run]

Commandes :
  update   [--dev] [--dry-run]  git pull --ff-only + submodules + make build + up
  start    [--dev] [--dry-run]  démarre le stack (up -d, sans build)
  stop     [--dev] [--dry-run]  arrête le stack (down — les volumes sont préservés)
  restart  [--dev] [--dry-run]  redémarre les conteneurs (compose restart)
  rebuild  [--dev] [--dry-run]  make build + up -d (sans git pull)
  logs     [--dev]              suit les logs (logs -f --tail=100, Ctrl-C pour sortir)
  status   [--dev]              conteneurs + health API + version déployée

Options :
  --dev       cible le stack DEV (docker-compose.dev.yml) au lieu de la prod
  --dry-run   affiche les commandes sans les exécuter (hors `logs`)
  -h, --help  cette aide

Alias : update-hub.sh = `hub.sh update`

⚠️ stop/down n'utilise JAMAIS -v : les volumes (hub-db, etc.) sont préservés.
EOF
}

# Arguments de compose selon le mode (prod inclut l'override s'il existe,
# parité avec le Makefile de HUB_base).
compose_args() {
    if [ "$MODE" = "dev" ]; then
        if [ -f "$HUB/docker-compose.override.yml" ]; then
            echo "-f docker-compose.yml -f docker-compose.override.yml -f docker-compose.dev.yml"
        else
            echo "-f docker-compose.yml -f docker-compose.dev.yml"
        fi
    else
        if [ -f "$HUB/docker-compose.override.yml" ]; then
            echo "-f docker-compose.yml -f docker-compose.override.yml"
        else
            echo "-f docker-compose.yml"
        fi
    fi
}

# Health hub-api ; $1 = strict (1: échec fatal en prod, 0: simple avertissement dev)
wait_health() {
    local strict="${1:-1}"
    info "Attente du health de hub-api (http://localhost:8000/api/health, 60 s max)…"
    local okhit=0
    for _ in $(seq 1 30); do
        if curl -sf http://localhost:8000/api/health > /dev/null 2>&1; then
            okhit=1
            break
        fi
        sleep 2
    done
    if [ "$okhit" != "1" ]; then
        if [ "$strict" = "1" ]; then
            die "hub-api ne répond pas au health check — regarde : docker logs hub-api"
        fi
        info "⚠ hub-api ne répond pas sur :8000 — en mode DEV les ports/mounts peuvent différer (docker-compose.dev.yml)."
        return 0
    fi
    local run_version
    run_version="$(curl -sf http://localhost:8000/api/health | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)"
    ok "hub-api opérationnel — version déployée : ${run_version:-inconnue}"
}

# ─── Parse ─────────────────────────────────────────────────────────────────
[ $# -gt 0 ] || { usage; exit 1; }
CMD="$1"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --dev) MODE="dev" ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Option inconnue pour '$CMD' : $1 (voir ./hub.sh --help)" ;;
    esac
    shift
done

# ─── Pré-vols ──────────────────────────────────────────────────────────────
[ -d "$HUB" ] || die "HUB_base introuvable sous $ROOT — lance ce script depuis la racine POULIDOR."
[ -f "$HUB/Makefile" ] || die "$HUB n'est pas un checkout HUB_base valide (Makefile manquant)."
if [ "$DRY_RUN" != "1" ] && [ "$CMD" != "logs" ]; then
    docker info > /dev/null 2>&1 || die "Docker ne répond pas — démarre-le et relance."
fi
COMPOSE="$(compose_args)"

# Toutes les commandes compose/make s'exécutent depuis HUB_base
# (les chemins -f sont relatifs à ce dossier, parité avec le Makefile).
cd "$HUB"

case "$CMD" in
    # ── update : pull + submodules + build + up ───────────────────────────
    update)
        OLD_VERSION="$(cat "$HUB/VERSION" 2>/dev/null || echo 'n/a')"
        echo "🚀 Mise à jour du HUB (mode $MODE) — version actuelle : $OLD_VERSION"
        run git -C "$ROOT" pull --ff-only
        run git -C "$ROOT" submodule update --init --recursive
        NEW_VERSION="$(cat "$HUB/VERSION" 2>/dev/null || echo 'n/a')"
        if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
            info "HUB_base déjà à jour (v$NEW_VERSION) — rebuild/déploiement quand même."
        else
            ok "HUB_base mis à jour : $OLD_VERSION → $NEW_VERSION"
        fi
        run make build
        # shellcheck disable=SC2086
        run docker compose $COMPOSE up -d
        [ "$DRY_RUN" = "1" ] && { ok "Dry-run terminé — aucune commande exécutée."; exit 0; }
        wait_health 1
        ;;

    # ── start / stop / restart / rebuild ─────────────────────────────────
    start)
        echo "▶ Démarrage du HUB (mode $MODE)"
        # shellcheck disable=SC2086
        run docker compose $COMPOSE up -d
        [ "$DRY_RUN" = "1" ] && exit 0
        wait_health 1
        ;;
    stop)
        echo "■ Arrêt du HUB (mode $MODE) — volumes préservés (jamais -v)."
        # shellcheck disable=SC2086
        run docker compose $COMPOSE down
        [ "$DRY_RUN" = "1" ] && exit 0
        ok "HUB arrêté."
        ;;
    restart)
        echo "⟳ Redémarrage du HUB (mode $MODE)"
        # shellcheck disable=SC2086
        run docker compose $COMPOSE restart
        [ "$DRY_RUN" = "1" ] && exit 0
        wait_health 1
        ;;
    rebuild)
        echo "🔨 Rebuild du HUB (mode $MODE) — build + up, sans git pull."
        run make build
        # shellcheck disable=SC2086
        run docker compose $COMPOSE up -d
        [ "$DRY_RUN" = "1" ] && exit 0
        wait_health 1
        ;;

    # ── logs (attaché) ───────────────────────────────────────────────────
    logs)
        cd "$HUB"
        # shellcheck disable=SC2086
        exec docker compose $COMPOSE logs -f --tail=100
        ;;

    # ── status ───────────────────────────────────────────────────────────
    status)
        echo "📋 HUB (mode $MODE) — repo : v$(cat "$HUB/VERSION" 2>/dev/null || echo 'n/a')"
        run docker compose $COMPOSE ps
        if curl -sf http://localhost:8000/api/health > /dev/null 2>&1; then
            wait_health 0
        else
            info "⚠ hub-api ne répond pas sur :8000."
        fi
        ;;

    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        die "Commande inconnue : '$CMD' (voir ./hub.sh --help)"
        ;;
esac
