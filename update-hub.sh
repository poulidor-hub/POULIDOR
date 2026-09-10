#!/usr/bin/env bash
# ============================================================================
# update-hub.sh — Mise à jour + déploiement du HUB depuis le méta-repo POULIDOR
#
# Enchaîne, depuis la racine POULIDOR/ :
#   1. git pull --ff-only (méta-repo, refus de merge automatique)
#   2. git submodule update --init --recursive  (HUB_base, HUBCSS, etc.)
#   3. make build (dans HUB_base)
#   4. make up-prod  (défaut)  ou  up -d en mode DEV (--dev)
#
# Usage :
#   ./update-hub.sh             # prod : pull + submodules + build + up-prod
#   ./update-hub.sh --dev       # idem, déploiement DEV (docker-compose.dev.yml)
#   ./update-hub.sh --dry-run   # affiche la séquence sans l'exécuter
#   ./update-hub.sh -h          # aide
#
# Note --dev : `make up-dev` est attaché (logs au premier plan) ; ce script
# lance le stack DEV détaché (up -d) pour se terminer. Pour suivre les logs :
#   cd HUB_base && docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB="$ROOT/HUB_base"
MODE="prod"
DRY_RUN=0

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
update-hub.sh — Mise à jour + déploiement du HUB depuis le méta-repo POULIDOR

Enchaîne, depuis la racine POULIDOR/ :
  1. git pull --ff-only (méta-repo, refus de merge automatique)
  2. git submodule update --init --recursive  (HUB_base, HUBCSS, etc.)
  3. make build (dans HUB_base)
  4. make up-prod  (défaut)  ou  up -d en mode DEV (--dev)

Usage :
  ./update-hub.sh             # prod : pull + submodules + build + up-prod
  ./update-hub.sh --dev       # idem, déploiement DEV (docker-compose.dev.yml)
  ./update-hub.sh --dry-run   # affiche la séquence sans l'exécuter
  ./update-hub.sh -h          # aide

Note --dev : `make up-dev` est attaché (logs au premier plan) ; ce script
lance le stack DEV détaché (up -d) pour se terminer. Pour suivre les logs :
  cd HUB_base && docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dev) MODE="dev" ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Option inconnue : $1 (voir --help)" ;;
    esac
    shift
done

# ─── Pré-vols ──────────────────────────────────────────────────────────────
[ -d "$HUB" ] || die "HUB_base introuvable sous $ROOT — lance ce script depuis la racine POULIDOR."
[ -f "$HUB/Makefile" ] || die "$HUB n'est pas un checkout HUB_base valide (Makefile manquant)."
if [ "$DRY_RUN" != "1" ]; then
    docker info > /dev/null 2>&1 || die "Docker ne répond pas — démarre-le et relance."
fi

OLD_VERSION="$(cat "$HUB/VERSION" 2>/dev/null || echo 'n/a')"
echo "🚀 Mise à jour du HUB (mode $MODE) — version actuelle : $OLD_VERSION"

# ─── 1-2. Dépôt + submodules ───────────────────────────────────────────────
run git -C "$ROOT" pull --ff-only
run git -C "$ROOT" submodule update --init --recursive

NEW_VERSION="$(cat "$HUB/VERSION" 2>/dev/null || echo 'n/a')"
if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    info "HUB_base déjà à jour (v$NEW_VERSION) — rebuild/déploiement quand même."
else
    ok "HUB_base mis à jour : $OLD_VERSION → $NEW_VERSION"
fi

# ─── 3. Build ──────────────────────────────────────────────────────────────
cd "$HUB"
run make build

# ─── 4. Déploiement ────────────────────────────────────────────────────────
if [ "$MODE" = "dev" ]; then
    # Sémantique de `make up-dev` mais détachée (un script doit se terminer).
    OVERRIDE=""
    [ -f docker-compose.override.yml ] && OVERRIDE="-f docker-compose.override.yml"
    # shellcheck disable=SC2086
    run docker compose -f docker-compose.yml $OVERRIDE -f docker-compose.dev.yml up -d
    ok "Stack DEV déployé. Logs : cd HUB_base && docker compose -f docker-compose.yml $OVERRIDE -f docker-compose.dev.yml logs -f"
else
    run make up-prod
fi

[ "$DRY_RUN" = "1" ] && { ok "Dry-run terminé — aucune commande exécutée."; exit 0; }

# ─── 5. Health check ───────────────────────────────────────────────────────
info "Attente du health de hub-api (http://localhost:8000/api/health, 60 s max)…"
HEALTH_OK=0
for _ in $(seq 1 30); do
    if curl -sf http://localhost:8000/api/health > /dev/null 2>&1; then
        HEALTH_OK=1
        break
    fi
    sleep 2
done

if [ "$MODE" = "prod" ]; then
    [ "$HEALTH_OK" = "1" ] || die "hub-api ne répond pas au health check — regarde : docker logs hub-api"
    RUN_VERSION="$(curl -sf http://localhost:8000/api/health | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    ok "HUB opérationnel — version déployée : ${RUN_VERSION:-inconnue} (attendue : $NEW_VERSION)"
    [ "$RUN_VERSION" = "$NEW_VERSION" ] || info "⚠ Version API ($RUN_VERSION) ≠ VERSION du repo ($NEW_VERSION) — un redémarrage du conteneur est peut-être nécessaire."
else
    if [ "$HEALTH_OK" = "1" ]; then
        ok "hub-api répond (port 8000)."
    else
        info "⚠ hub-api ne répond pas sur :8000 — en mode DEV les ports/mounts peuvent différer (docker-compose.dev.yml). Vérifie les logs du stack DEV."
    fi
fi
