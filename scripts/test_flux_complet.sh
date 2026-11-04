#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# =============================================================================
# test_flux_complet.sh — Test d'intégration Hub + App en isolation totale
# =============================================================================
# Usage :
#   bash scripts/test_flux_complet.sh
#
# Ce script :
#   1. Génère .env.test et démarre un Hub de test isolé (ports +18000)
#   2. Crée une app depuis le template, la configure pour le Hub de test
#   3. Démarre l'app et vérifie qu'elle s'enregistre sur le Hub de test
#   4. Affiche un résumé et propose le cleanup
#
# Toutes les ressources (conteneurs, réseaux, volumes) sont préfixées
# "pouly-test" — zéro collision avec le Hub de production.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HUB_DIR="$ROOT_DIR/HUB_base"
APPS_DIR="$ROOT_DIR/APPS"
TEST_APP="test-app"
COMPOSE_PROJECT="pouly-test"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# HELPERS
# =============================================================================
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }

check_deps() {
    command -v docker &>/dev/null || fail "docker introuvable"
    docker compose version &>/dev/null || fail "docker compose introuvable"
    command -v python3 &>/dev/null || fail "python3 introuvable"
}

warn_if_prod_running() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^hub-api$|^hub-db$|^hub-frontend$'; then
        warn "Hub de production détecté (conteneurs hub-api/hub-db/hub-frontend)."
        warn "Le test sera isolé — pas d'impact sur la production."
    fi
}

# =============================================================================
# ÉTAPE 1 : Générer .env.test
# =============================================================================
generate_env_test() {
    step "1/6 — Génération de HUB_base/.env.test"

    local env_test="$HUB_DIR/.env.test"
    local env_example="$HUB_DIR/.env.example"

    if [ ! -f "$env_example" ]; then
        fail "$env_example introuvable"
    fi

    # Générer une clé Fernet de test (valide uniquement pour ce test éphémère)
    local fernet_key
    fernet_key=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null) || {
        warn "Impossible de générer une clé Fernet via Python — clé factice utilisée"
        fernet_key="dGVzdF9rZXlfZm9yX3Rlc3Rpbmdfb25seV8zMi1ieXRlcw=="
    }

    cp "$env_example" "$env_test"

    # Remplacements des valeurs pour le test isolé
    sed -i 's/^APP_ENV=.*/APP_ENV=development/' "$env_test"
    sed -i 's/^AUTO_GENERATE_KEYS=.*/AUTO_GENERATE_KEYS=true/' "$env_test"
    sed -i 's/^FORCE_REPLACE_APP=.*/FORCE_REPLACE_APP=true/' "$env_test"
    sed -i 's/^HUB_API_PORT=.*/HUB_API_PORT=18000/' "$env_test"
    sed -i 's/^HUB_FRONTEND_PORT=.*/HUB_FRONTEND_PORT=18080/' "$env_test"
    sed -i 's/^HUB_HTTPS_PORT=.*/HUB_HTTPS_PORT=18443/' "$env_test"
    sed -i 's/^HUB_HTTPS_ENABLED=.*/HUB_HTTPS_ENABLED=false/' "$env_test"
    sed -i 's/^DOCKER_SYNC_INTERVAL=.*/DOCKER_SYNC_INTERVAL=0/' "$env_test"
    sed -i 's/^DOCKER_SCAN_ENABLED=.*/DOCKER_SCAN_ENABLED=false/' "$env_test"
    sed -i 's/^SKIP_PASSWORD_CHECK=.*/SKIP_PASSWORD_CHECK=true/' "$env_test"
    sed -i 's#^SECRETS_ENCRYPTION_KEY=.*#SECRETS_ENCRYPTION_KEY='"$fernet_key"'#' "$env_test"
    sed -i 's/^ALLOW_PLAINTEXT_SECRETS=.*/ALLOW_PLAINTEXT_SECRETS=true/' "$env_test"
    sed -i 's/^ALLOWED_ORIGINS=.*/ALLOWED_ORIGINS=/' "$env_test"
    sed -i 's#^APP_WHITELIST_NETWORKS=.*#APP_WHITELIST_NETWORKS=203.0.113.14/16,172.16.0.0/12#' "$env_test"
    sed -i 's/^APP_PORT_API_START=.*/APP_PORT_API_START=19000/' "$env_test"
    sed -i 's/^APP_PORT_API_END=.*/APP_PORT_API_END=19499/' "$env_test"
    sed -i 's/^APP_PORT_FRONTEND_START=.*/APP_PORT_FRONTEND_START=14200/' "$env_test"
    sed -i 's/^APP_PORT_FRONTEND_END=.*/APP_PORT_FRONTEND_END=14699/' "$env_test"
    sed -i 's/^PORT_SCAN_DOCKER_ENABLED=.*/PORT_SCAN_DOCKER_ENABLED=false/' "$env_test"
    sed -i 's/^HOST_UID=.*/HOST_UID='"$(id -u)"'/' "$env_test"

    # Exporter les variables critiques pour docker compose
    # (le source direct échoue car .env contient des espaces non quotés)
    export HUB_API_PORT=18000
    export HUB_FRONTEND_PORT=18080
    export HUB_HTTPS_PORT=18443
    export APP_ENV=development
    export AUTO_GENERATE_KEYS=true
    export FORCE_REPLACE_APP=true
    export SECRETS_ENCRYPTION_KEY="$fernet_key"
    export ALLOWED_ORIGINS=""
    export APP_WHITELIST_NETWORKS="203.0.113.14/16,172.16.0.0/12"
    export HUB_HTTPS_ENABLED=false
    export SKIP_PASSWORD_CHECK=true
    export ALLOW_PLAINTEXT_SECRETS=true
    export DOCKER_SYNC_INTERVAL=0
    export DOCKER_SCAN_ENABLED=false
    export APP_PORT_API_START=19000
    export APP_PORT_API_END=19499
    export APP_PORT_FRONTEND_START=14200
    export APP_PORT_FRONTEND_END=14699
    export PORT_SCAN_DOCKER_ENABLED=false
    export HOST_UID="$(id -u)"
    export ADMIN_USERNAME=admin
    export ADMIN_PASSWORD=CHANGEZ_MOI_admin_password
    export ADMIN_EMAIL=admin@local.lan
    export POSTGRES_USER=hubadmin
    export POSTGRES_PASSWORD=CHANGEZ_MOI_mot_de_passe_securise
    export POSTGRES_DB=hub_auth

    ok ".env.test généré (ports Hub: 18000/18080/18443, dev mode, fernet key éphémère)"
}

# =============================================================================
# ÉTAPE 2 : Démarrer le Hub de test
# =============================================================================
start_test_hub() {
    step "2/6 — Démarrage du Hub de test (projet Docker: $COMPOSE_PROJECT)"

    cd "$HUB_DIR"

    # Nettoyage préalable si un test précédent a mal fini
    docker compose -p "$COMPOSE_PROJECT" \
        -f docker-compose.yml -f docker-compose.test.yml \
        down -v &>/dev/null || true

    log "Build + up des conteneurs Hub (API=${HUB_API_PORT}, frontend=${HUB_FRONTEND_PORT})..."
    docker compose -p "$COMPOSE_PROJECT" \
        -f docker-compose.yml -f docker-compose.test.yml \
        up -d --build 2>&1 | tail -5

    ok "Hub de test démarré"
}

# =============================================================================
# ÉTAPE 3 : Attendre que le Hub soit healthy
# =============================================================================
wait_hub_healthy() {
    step "3/6 — Attente du health check Hub (timeout: 180s)"

    local max_attempts=60
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -sf http://localhost:18000/health &>/dev/null; then
            ok "Hub healthy après ${attempt}s"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    # Afficher les logs pour debug
    warn "Timeout — logs des 30 dernières lignes du hub-api :"
    docker compose -p "$COMPOSE_PROJECT" \
        -f "$HUB_DIR/docker-compose.yml" -f "$HUB_DIR/docker-compose.test.yml" \
        logs hub-api --tail=30 2>&1 || true
    fail "Le Hub de test n'est pas devenu healthy après ${max_attempts}s"
}

# =============================================================================
# ÉTAPE 4 : Créer l'app test
# =============================================================================
create_test_app() {
    step "4/6 — Création de l'application '$TEST_APP'"

    if [ -d "$APPS_DIR/$TEST_APP" ]; then
        warn "$APPS_DIR/$TEST_APP existe déjà — suppression"
        if docker compose -f "$APPS_DIR/$TEST_APP/docker-compose.yml" ps -q 2>/dev/null | grep -q .; then
            docker compose -f "$APPS_DIR/$TEST_APP/docker-compose.yml" down -v 2>&1 || true
        fi
        rm -rf "$APPS_DIR/$TEST_APP"
    fi

    bash "$ROOT_DIR/scripts/create_app.sh" "$TEST_APP" || fail "create_app.sh a échoué"

    cd "$APPS_DIR/$TEST_APP"

    # Le template n'a que .env.example, pas de .env.
    # create_app.sh crée un .env minimal avec juste les APPS overrides.
    # On reconstruit un .env complet à partir de .env.example + overrides.
    local env_overrides
    env_overrides=$(cat .env 2>/dev/null || true)
    cp .env.example .env
    if [ -n "$env_overrides" ]; then
        echo "" >> .env
        echo "$env_overrides" >> .env
    fi

    # Configurer le .env pour pointer vers le Hub de test
    # HUB_HOST=localhost       → pour les scripts hôtes (allocate_ports.py, curl, etc.)
    # HUB_INTERNAL_HOST=...    → pour les conteneurs Docker (via host.docker.internal)
    sed -i 's/^APP_SLUG=.*/APP_SLUG=test-app/' .env
    sed -i 's/^APP_NAME=.*/APP_NAME=Test App/' .env
    sed -i 's/^HUB_HOST=.*/HUB_HOST=localhost/' .env
    sed -i 's/^HUB_API_PORT=.*/HUB_API_PORT=18000/' .env
    sed -i 's/^HUB_FRONTEND_PORT=.*/HUB_FRONTEND_PORT=18080/' .env
    sed -i 's/^HUB_INTERNAL_HOST=.*/HUB_INTERNAL_HOST=host.docker.internal/' .env
    sed -i 's/^API_PORT=.*/API_PORT=/' .env
    sed -i 's/^FRONTEND_PORT=.*/FRONTEND_PORT=/' .env
    sed -i 's/^FRONTEND_HTTPS_PORT=.*/FRONTEND_HTTPS_PORT=/' .env
    sed -i 's/^APP_HOST=.*/APP_HOST=/' .env

    # HUB_INTERNAL_HOST est déjà dans .env.example, on le modifie ci-dessus
    # (pas besoin de l'ajouter manuellement)

    ok "App '$TEST_APP' créée et configurée dans $APPS_DIR/$TEST_APP"
}

# =============================================================================
# ÉTAPE 5 : Démarrer l'app test
# =============================================================================
start_test_app() {
    step "5/6 — Démarrage de l'application '$TEST_APP'"

    cd "$APPS_DIR/$TEST_APP"

    log "Allocation des ports via le Hub de test..."
    if python3 ACTIONS/PYTHON/allocate_ports.py; then
        ok "Ports alloués par le Hub de test"
    else
        warn "Allocation échouée — ports par défaut utilisés"
        # Fallback: utiliser des ports manuels
        sed -i 's/^API_PORT=.*/API_PORT=19010/' .env
        sed -i 's/^FRONTEND_PORT=.*/FRONTEND_PORT=14210/' .env
        echo "FRONTEND_HTTPS_PORT=14211" >> .env
    fi

    log "Build et démarrage des conteneurs app..."
    docker compose up --build -d 2>&1 | tail -5

    ok "App '$TEST_APP' démarrée"
}

# =============================================================================
# ÉTAPE 6 : Vérifications
# =============================================================================
verify() {
    step "6/6 — Vérifications"

    local hub_ok=false
    local app_ok=false
    local app_registered=false

    echo ""
    log "--- Hub de test ---"

    # Health Hub
    if curl -sf http://localhost:18000/health &>/dev/null; then
        local hub_health
        hub_health=$(curl -sf http://localhost:18000/health 2>/dev/null)
        ok "Hub API healthy : $hub_health"
        hub_ok=true
    else
        fail "Hub API inaccessible"
    fi

    echo ""
    log "--- App '$TEST_APP' ---"

    # Récupérer les ports de l'app
    local app_api_port
    app_api_port=$(grep -E '^API_PORT=' "$APPS_DIR/$TEST_APP/.env" | tail -1 | cut -d= -f2 | tr -d ' ')

    if [ -n "$app_api_port" ]; then
        local app_health
        app_health=$(curl -sf "http://localhost:${app_api_port}/api/health" 2>/dev/null || echo "")
        if [ -n "$app_health" ]; then
            ok "App API healthy : $app_health"
            app_ok=true

            # Vérifier hub_connected dans le health check
            if echo "$app_health" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('hub_connected') else 1)" 2>/dev/null; then
                ok "App connectée au Hub (hub_connected: true)"
                app_registered=true
            else
                warn "App non connectée au Hub (hub_connected: false)"
            fi
        else
            warn "App API pas accessible — logs (20 dernières lignes) :"
            cd "$APPS_DIR/$TEST_APP" && docker compose logs api --tail=20 2>&1 || true
        fi
    else
        warn "API_PORT non trouvé dans .env"
    fi

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "  Hub test :  ${GREEN}http://localhost:18000${NC}  (API)"
    echo -e "              ${GREEN}http://localhost:18080${NC}  (frontend)"
    if [ -n "$app_api_port" ]; then
        echo -e "  App test :  ${GREEN}http://localhost:${app_api_port}${NC}  (API)"
    fi
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"

    if $hub_ok && $app_ok && $app_registered; then
        echo -e "\n${GREEN}${BOLD}✅ SUCCÈS — Le flux complet fonctionne !${NC}\n"
    else
        echo -e "\n${YELLOW}${BOLD}⚠️  Vérifications partielles — voir les logs ci-dessus.${NC}\n"
    fi
}

# =============================================================================
# CLEANUP
# =============================================================================
cleanup() {
    step "Nettoyage"

    # Arrêter et supprimer l'app test
    if [ -f "$APPS_DIR/$TEST_APP/docker-compose.yml" ]; then
        log "Arrêt de l'app '$TEST_APP'..."
        docker compose -f "$APPS_DIR/$TEST_APP/docker-compose.yml" down -v 2>&1 || true
        rm -rf "$APPS_DIR/$TEST_APP"
    fi

    # Arrêter et supprimer le Hub test
    log "Arrêt du Hub de test (projet: $COMPOSE_PROJECT)..."
    docker compose -p "$COMPOSE_PROJECT" \
        -f "$HUB_DIR/docker-compose.yml" -f "$HUB_DIR/docker-compose.test.yml" \
        down -v 2>&1 || true

    # Supprimer .env.test
    if [ -f "$HUB_DIR/.env.test" ]; then
        rm "$HUB_DIR/.env.test"
    fi

    ok "Nettoyage terminé — toutes les ressources de test sont supprimées"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║     Test du flux complet Hub + App (isolé)             ║"
    echo "  ║     Projet Docker : pouly-test                         ║"
    echo "  ║     Date : $TIMESTAMP                   ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_deps
    warn_if_prod_running

    generate_env_test
    start_test_hub
    wait_hub_healthy
    create_test_app
    start_test_app

    # Attendre un peu que l'app s'enregistre
    log "Attente de l'enregistrement de l'app (10s)..."
    sleep 10

    # Vérifier à nouveau que le Hub est healthy avant de vérifier
    wait_hub_healthy

    verify

    # Proposer le cleanup
    echo ""
    read -r -p "$(echo -e "${YELLOW}Nettoyer les ressources de test ? [O/n] ${NC}")" answer
    if [ -z "$answer" ] || [[ "$answer" =~ ^[OoYy] ]]; then
        cleanup
    else
        echo -e "\n${CYAN}Pour nettoyer manuellement :${NC}"
        echo "  rm $HUB_DIR/.env.test"
        echo "  docker compose -p $COMPOSE_PROJECT -f $HUB_DIR/docker-compose.yml -f $HUB_DIR/docker-compose.test.yml down -v"
        echo "  rm -rf $APPS_DIR/$TEST_APP"
    fi
}

main
