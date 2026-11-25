#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# =============================================================================
# POULIDOR — Diagnostic d'import (scripts/check-import.sh)
# =============================================================================
# Vérifie, SECTION PAR SECTION, l'état d'une machine pour faire tourner
# POULIDOR. 100 % READ-ONLY : ne modifie rien (ne crée même pas le venv hubctl,
# le check S3 se contente d'une analyse statique du lanceur).
#
# Usage :
#   ./scripts/check-import.sh               # Diagnostic complet S1 → S10
#   ./scripts/check-import.sh --section S3  # Une seule section
#   ./scripts/check-import.sh --verbose     # Sortie détaillée
#   ./scripts/check-import.sh --no-color    # Sans couleurs (pipe / log)
#
# Sortie : rapport PASS / WARN / FAIL par section + résumé final.
# Code de sortie : 0 si aucun FAIL, 1 sinon.
#
# Sections :
#   S1 — Clone + sous-modules git
#   S2 — Prérequis système (OS, Docker, Python, utilitaires)
#   S3 — Lanceur hubctl (wrapper + venv + résolution PARC_ROOT)
#   S4 — Init Hub (.env, clés JWT, Fernet, PKI, override)
#   S5 — Démarrage conteneurs Hub (daemon, hub-db/api/frontend, health)
#   S6 — Environnement IA (.secrets, bashrc, MCP hub, opencode)
#   S7 — Apps & atelier (cohérence doc/code, create_app, artefacts parasites)
#   S8 — GitHub CLI (gh : présence, authentification)
#   S9 — Node.js (MCP zai, plugin opencode, build HUBCSS)
#   S10 — QEMU/KVM (labo vm-lab, optionnel)
# =============================================================================

set -uo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────────────
USE_COLOR=true
VERBOSE=false
ONLY_SECTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --section) ONLY_SECTION="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        --help|-h)
            sed -n '3,28p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Argument inconnu : $1 (essaie --help)" >&2; exit 2 ;;
    esac
done

if [[ "$USE_COLOR" == true && -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
    C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'; C_NC=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_NC=''
fi

# ── Compteurs et helpers ─────────────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0

pass() { echo "  ${C_GREEN}✓${C_NC} $1"; PASS=$((PASS+1)); }
warn() { echo "  ${C_YELLOW}⚠${C_NC} $1"; WARN=$((WARN+1)); }
fail() { echo "  ${C_RED}✗${C_NC} $1"; FAIL=$((FAIL+1)); }
info() { $VERBOSE && echo "  ${C_CYAN}·${C_NC} $1" || true; }

# Section courante (pour filtrage --section)
CUR_SECTION=""
should_skip() { [[ -n "$ONLY_SECTION" && "$CUR_SECTION" != "$ONLY_SECTION" ]]; }

begin_section() {
    CUR_SECTION="$1"
    if should_skip; then return; fi
    echo ""
    echo "${C_BOLD}${C_CYAN}═══ $1 — $2 ═══${C_NC}"
}

# ── Racine du parc ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PARC_ROOT" || { echo "PARC_ROOT injoignable : $PARC_ROOT" >&2; exit 2; }

echo "${C_BOLD}${C_CYAN}POULIDOR — Diagnostic d'import${C_NC} ($(date '+%Y-%m-%d %H:%M:%S'))"
info "PARC_ROOT = $PARC_ROOT"

# =============================================================================
# S1 — Clone + sous-modules git
# =============================================================================
section_s1() {
    begin_section "S1" "Clone + sous-modules git"
    should_skip && return

    if [ -f .gitmodules ]; then pass ".gitmodules présent"; else fail ".gitmodules absent"; fi

    local -a sous_modules=(HUB_base HUBCSS hub-mcp HUBapp_TEMPLATE_base hubctl_src HUBsocle)
    local sm
    for sm in "${sous_modules[@]}"; do
        if [ -d "$sm" ] && [ -n "$(ls -A "$sm" 2>/dev/null)" ]; then
            pass "sous-module '$sm' initialisé"
        else
            fail "sous-module '$sm' MANQUANT ou vide (lance : git submodule update --init $sm)"
        fi
    done

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local n_uninit n_shifted
        n_uninit=$(git submodule status 2>/dev/null | grep -c "^-") || n_uninit=0
        n_shifted=$(git submodule status 2>/dev/null | grep -c "^+") || n_shifted=0
        if [ "$n_uninit" -gt 0 ]; then
            fail "$n_uninit sous-module(s) NON initialisé(s) — git submodule update --init --recursive"
        elif [ "$n_shifted" -gt 0 ]; then
            warn "$n_shifted sous-module(s) décalé(s) du commit pointé"
        else
            pass "git submodule status : les ${#sous_modules[@]} sous-modules sont alignés"
        fi
    else
        warn "git indisponible ou pas un dépôt — skip git submodule status"
    fi

    # B1 : manifest.json vs .gitmodules (tous les sous-modules n'y sont pas listés)
    if [ -f manifest.json ] && command -v python3 >/dev/null 2>&1; then
        local n_manifest absents=""
        n_manifest=$(python3 -c "import json; print(len(json.load(open('manifest.json'))))" 2>/dev/null || echo 0)
        if [ "$n_manifest" -lt "${#sous_modules[@]}" ]; then
            for sm in "${sous_modules[@]}"; do
                python3 -c 'import json, sys; sys.exit(0 if sys.argv[1] in json.load(open("manifest.json")) else 1)' "$sm" 2>/dev/null \
                    || absents="${absents:+$absents, }$sm"
            done
            warn "B1 : manifest.json ne liste que $n_manifest sous-module(s) sur ${#sous_modules[@]} — absent(s) : $absents. Les outils qui s'appuient sur manifest.json les ignorent (dont le lanceur hubctl si hubctl_src est absent)."
        else
            pass "manifest.json cohérent avec .gitmodules"
        fi
    fi

    # Accès GitHub (SSH ou HTTPS) : les sous-modules sont en HTTPS ; un déploiement
    # par clé de déploiement garde l'accès SSH. Tant que les dépôts sont privés,
    # l'HTTPS exige un gestionnaire d'identifiants configuré sur le poste.
    local acces_ssh=0 acces_https=0
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -T git@github.com 2>&1 | grep -qi "successfully authenticated"; then
        acces_ssh=1
    fi
    if GIT_TERMINAL_PROMPT=0 timeout 15 git ls-remote --exit-code \
            https://github.com/POULIDOR-Audit-Developpement/POULIDOR.git HEAD >/dev/null 2>&1; then
        acces_https=1
    fi
    if [ "$acces_ssh" -eq 1 ] && [ "$acces_https" -eq 1 ]; then
        pass "accès GitHub fonctionnel (SSH et HTTPS)"
    elif [ "$acces_ssh" -eq 1 ] || [ "$acces_https" -eq 1 ]; then
        pass "accès GitHub fonctionnel ($([ "$acces_ssh" -eq 1 ] && printf SSH || printf HTTPS))"
    else
        warn "accès GitHub non vérifié (ni SSH ni HTTPS) — clone/fetch des sous-modules impossible sans ça"
    fi
}

# =============================================================================
# S2 — Prérequis système
# =============================================================================
section_s2() {
    begin_section "S2" "Prérequis système (OS, Docker, Python, utils)"
    should_skip && return

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}:${ID_LIKE:-}" in
            *debian*|*ubuntu*|*linuxmint*) pass "OS Debian/Ubuntu/Mint détecté : ${PRETTY_NAME:-$ID}" ;;
            *) warn "OS non Debian-like (${PRETTY_NAME:-$ID}) — install.sh (apt-get) non supporté" ;;
        esac
    else
        warn "/etc/os-release absent — OS non identifié"
    fi

    if command -v apt-get >/dev/null 2>&1; then pass "apt-get présent"; else warn "apt-get absent (installeur auto KO)"; fi
    if command -v git >/dev/null 2>&1; then pass "git présent"; else fail "git MANQUANT"; fi

    if command -v docker >/dev/null 2>&1; then
        pass "docker CLI présent"
    else
        fail "docker MANQUANT — installe via install.sh ou apt-get install docker-ce"
    fi

    if docker compose version >/dev/null 2>&1; then
        pass "docker compose v2 présent ($(docker compose version --short 2>/dev/null || echo '?'))"
    else
        fail "docker compose v2 (plugin) MANQUANT — apt-get install docker-compose-plugin"
    fi

    if docker info >/dev/null 2>&1; then
        pass "docker daemon accessible"
    else
        fail "docker daemon injoignable — systemctl start docker (ou ajoute l'utilisateur au groupe docker)"
    fi

    if command -v python3 >/dev/null 2>&1; then
        pass "python3 présent ($(python3 --version 2>&1))"
    else
        fail "python3 MANQUANT"
    fi

    if python3 -c "import venv" 2>/dev/null; then
        pass "python3-venv fonctionnel"
    else
        fail "python3-venv MANQUANT — apt-get install python3-venv (requis pour hubctl)"
    fi

    local tool
    for tool in make openssl curl rsync; do
        if command -v "$tool" >/dev/null 2>&1; then
            pass "$tool présent"
        else
            warn "$tool absent (peut casser certains scripts)"
        fi
    done

    # B4 : GID docker hardcodé à 128 pour hub-api dans docker-compose.yml
    if [ -f HUB_base/docker-compose.yml ]; then
        local compose_gid host_docker_gid
        # Détecte soit un numérique littéral ("128") soit une var (${HOST_DOCKER_GID:-128})
        local compose_block
        compose_block=$(grep -A5 "^    group_add:" HUB_base/docker-compose.yml | head -6)
        if echo "$compose_block" | grep -qE "HOST_DOCKER_GID"; then
            compose_gid="var:HOST_DOCKER_GID"
        else
            compose_gid=$(echo "$compose_block" | grep -oE "\"[0-9]+\"" | head -1 | tr -d "\"") || compose_gid=""
        fi
        host_docker_gid=$(getent group docker 2>/dev/null | cut -d: -f3) || host_docker_gid=""
        if [ -z "$compose_gid" ]; then
            warn "impossible de lire le group_add dans HUB_base/docker-compose.yml"
        elif [ "$compose_gid" = "var:HOST_DOCKER_GID" ]; then
            # Vérifier que la var est définie dans .env et match le GID hôte
            local env_gid
            env_gid=$(grep -E "^(export )?HOST_DOCKER_GID=" HUB_base/.env 2>/dev/null | head -1 | cut -d= -f2 | tr -d "\"'") || env_gid=""
            if [ -z "$env_gid" ]; then
                warn "B4 : compose utilise \${HOST_DOCKER_GID} mais var absente du .env — fallback 128 utilisé"
            elif [ -z "$host_docker_gid" ]; then
                warn "groupe 'docker' absent sur l'hôte — scanner Docker du Hub sans accès au socket"
            elif [ "$env_gid" != "$host_docker_gid" ]; then
                fail "B4 : .env HOST_DOCKER_GID=$env_gid mais GID docker hôte=$host_docker_gid — docker_scanner sans accès au socket"
            else
                pass "group_add paramétré (\${HOST_DOCKER_GID}=$env_gid) == GID docker hôte ($host_docker_gid)"
            fi
        elif [ -z "$host_docker_gid" ]; then
            warn "groupe 'docker' absent sur l'hôte — scanner Docker du Hub sans accès au socket"
        elif [ "$compose_gid" != "$host_docker_gid" ]; then
            fail "B4 : GID docker hôte=$host_docker_gid mais compose hardcode group_add=\"$compose_gid\" pour hub-api → docker_scanner sans accès au socket"
        else
            pass "GID docker ($host_docker_gid) == group_add compose ($compose_gid)"
        fi
    fi
}

# =============================================================================
# S3 — Lanceur hubctl
# =============================================================================
section_s3() {
    begin_section "S3" "Lanceur hubctl (wrapper + venv + PARC_ROOT)"
    should_skip && return

    if [ -x ./hubctl ]; then pass "./hubctl exécutable"; else fail "./hubctl MANQUANT ou non exécutable"; fi

    if [ -f hubctl_src/hubctl ]; then
        pass "hubctl_src/hubctl présent (sous-module OK)"
    else
        fail "hubctl_src/hubctl MANQUANT — sous-module hubctl_src non initialisé"
    fi

    if bash -n hubctl_src/hubctl 2>/dev/null; then
        pass "syntaxe hubctl_src/hubctl OK"
    else
        fail "hubctl_src/hubctl a une erreur de syntaxe bash"
    fi

    if [ -L hubctl_cli ] && [ -d hubctl_cli/ ]; then
        pass "symlink hubctl_cli valide → $(readlink -f hubctl_cli)"
    elif [ -L hubctl_cli ]; then
        fail "symlink hubctl_cli CASSÉ (cible absente)"
    elif [ -d hubctl_cli ]; then
        warn "hubctl_cli est un dossier (pas un symlink) — configuration non standard"
    else
        fail "hubctl_cli MANQUANT (ni symlink ni dossier)"
    fi

    if [ -d hubctl_cli/.venv ] && [ -x hubctl_cli/.venv/bin/python ]; then
        pass "venv hubctl_cli/.venv présent"
    else
        warn "venv hubctl_cli/.venv absent — sera créé au 1er ./hubctl (nécessite réseau PyPI)"
    fi

    # Résolution PARC_ROOT : manifest.json doit être atteignable en remontant
    # depuis hubctl_src/hubctl_cli/ (c'est ce que fait _find_parc_root).
    local d found
    d="$(cd hubctl_src/hubctl_cli 2>/dev/null && pwd)" || d=""
    found=""
    if [ -n "$d" ]; then
        local i
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if [ -f "$d/manifest.json" ]; then found="$d"; break; fi
            d="$(dirname "$d")"
            [ "$d" = "/" ] && break
        done
    fi
    if [ -n "$found" ]; then
        pass "PARC_ROOT résolu depuis hubctl_src/hubctl_cli → $found"
    else
        fail "manifest.json introuvable en remontant depuis hubctl_src/hubctl_cli — _find_parc_root va échouer"
    fi
}

# =============================================================================
# S4 — Init Hub (.env, JWT, Fernet, PKI)
# =============================================================================
section_s4() {
    begin_section "S4" "Init Hub (.env, clés JWT, Fernet, PKI, override)"
    should_skip && return

    if [ -f HUB_base/.env ]; then
        pass "HUB_base/.env présent"
    else
        fail "HUB_base/.env MANQUANT — lance ./hubctl init pour le générer"
    fi

    local v
    for v in POSTGRES_PASSWORD ADMIN_USERNAME ADMIN_PASSWORD SECRETS_ENCRYPTION_KEY DATABASE_URL; do
        if grep -qE "^(export )?${v}=." HUB_base/.env 2>/dev/null; then
            pass ".env : $v défini (non vide)"
        else
            fail ".env : $v MANQUANT ou vide — Hub refusera de démarrer"
        fi
    done

    local k
    for k in jwt_private_key.pem jwt_public_key.pem; do
        if [ ! -s "HUB_base/secrets/$k" ]; then
            fail "HUB_base/secrets/$k MANQUANT ou vide — Hub ne pourra pas signer/vérifier les tokens JWT"
        fi
    done
    [ -s HUB_base/secrets/jwt_private_key.pem ] && [ -s HUB_base/secrets/jwt_public_key.pem ] \
        && pass "clés JWT RSA présentes (privée + publique)"

    if [ -s HUB_base/secrets/backup_private_key.pem ] && [ -s HUB_base/secrets/backup_public_key.pem ]; then
        pass "clés backup (park-export) présentes"
    else
        warn "clés backup manquantes — park-export chiffré ne fonctionnera pas"
    fi

    if [ -d HUB_base/certs/ca ] && [ -d HUB_base/certs/server ]; then
        pass "PKI présente (certs/ca + certs/server)"
    else
        warn "PKI absente — HTTPS désactivé ou à générer (docker compose exec hub-api python pki.py init)"
    fi

    if [ -f HUB_base/docker-compose.override.yml ]; then
        pass "docker-compose.override.yml présent"
    else
        warn "docker-compose.override.yml absent — généré normalement par le Hub après 1er démarrage"
    fi
}

# =============================================================================
# S5 — Démarrage conteneurs Hub
# =============================================================================
section_s5() {
    begin_section "S5" "Démarrage conteneurs Hub"
    should_skip && return

    if docker info >/dev/null 2>&1; then
        pass "docker daemon actif"
    else
        fail "docker daemon injoignable — reste de S5 ignoré"
        return
    fi

    local c status
    for c in hub-db hub-api hub-frontend; do
        status=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
        case "$status" in
            running) pass "conteneur $c : running" ;;
            missing) fail "conteneur $c ABSENT (lance : make -C HUB_base up-prod)" ;;
            *)       warn "conteneur $c : $status" ;;
        esac
    done

    local h
    h=$(docker inspect -f '{{.State.Health.Status}}' hub-api 2>/dev/null || echo "?")
    case "$h" in
        healthy)   pass "hub-api healthcheck : healthy" ;;
        unhealthy) fail "hub-api healthcheck : UNHEALTHY — docker logs hub-api" ;;
        starting)  warn "hub-api healthcheck : starting (démarrage en cours)" ;;
        *)         warn "hub-api healthcheck : $h" ;;
    esac

    local port
    port=$(grep -E "^(export )?HUB_API_PORT=" HUB_base/.env 2>/dev/null | head -1 | cut -d= -f2 | tr -d "\"'") || port=""
    port=${port:-8000}
    if curl -sf -m 3 "http://localhost:${port}/api/health" >/dev/null 2>&1; then
        pass "API répond sur http://localhost:${port}/api/health"
    else
        fail "API INJOIGNABLE sur le port $port (HUB_API_PORT du .env)"
    fi

    local code
    code=$(curl -sf -m 3 -o /dev/null -w "%{http_code}" http://localhost:80/ 2>/dev/null || echo "000")
    case "$code" in
        200|301|302) pass "frontend répond sur port 80 (HTTP $code)" ;;
        000)
            code=$(curl -sf -m 3 -o /dev/null -w "%{http_code}" http://localhost:443/ 2>/dev/null || echo "000")
            case "$code" in
                200|301|302) pass "frontend répond sur port 443 (HTTP $code)" ;;
                *) warn "frontend injoignable sur 80/443" ;;
            esac
            ;;
        *) warn "frontend port 80 : HTTP $code" ;;
    esac
}

# =============================================================================
# S6 — Environnement IA (.secrets, bashrc, MCP hub, opencode)
# =============================================================================
section_s6() {
    begin_section "S6" "Environnement IA (.secrets, bashrc, MCP hub)"
    should_skip && return

    if [ -f .secrets ]; then
        pass ".secrets présent ($(wc -l < .secrets) lignes)"
    else
        fail ".secrets MANQUANT — cp .secrets.example .secrets puis édite (droit 600)"
    fi

    local v
    for v in HUB_BASE_URL HUB_ADMIN_USERNAME HUB_ADMIN_PASSWORD; do
        if grep -qE "^(export )?${v}=." .secrets 2>/dev/null; then
            pass ".secrets : $v défini"
        else
            fail ".secrets : $v MANQUANT — le serveur MCP hub (mode standalone) plantera à chaque appel d'outil"
        fi
        if grep -qE "^(export )?${v}=" .secrets.example 2>/dev/null; then
            pass ".secrets.example documente $v"
        else
            warn "B2 : .secrets.example NE documente PAS $v — un nouvel importeur ne saura pas qu'il doit la fournir"
        fi
    done

    # B3 : bashrc source .secrets pour ce PARC_ROOT (via marker portable OU chemin direct).
    #      Nouveau mécanisme (recommandé) : bashrc → ~/.config/poulidor/parc.sh → <PARC_ROOT>/.secrets
    #      Mécanisme legacy : bashrc → <chemin hardcodé>/.secrets
    local rc="${HOME}/.bashrc"
    local marker="${HOME}/.config/poulidor/parc.sh"
    local b3_resolved=false

    # (1) Nouveau mécanisme : marker portable
    if [ -f "$marker" ]; then
        if grep -q "poulidor/parc.sh" "$rc" 2>/dev/null; then
            # Le bashrc source le marker ; vérifier que le marker pointe vers ce PARC_ROOT
            if grep -qE "\. ${PARC_ROOT}/\.secrets|\. \"${PARC_ROOT}/\.secrets\"" "$marker" 2>/dev/null; then
                pass "marker portable ~/.config/poulidor/parc.sh → ce PARC_ROOT (sourcing OK)"
                b3_resolved=true
            else
                local pointed
                pointed=$(grep -oE "/[^ ]*POULIDOR/\.secrets|/[^ ]*\.secrets" "$marker" 2>/dev/null | head -1)
                fail "B3 : marker parc.sh présent mais pointe vers '$pointed' (≠ PARC_ROOT=$PARC_ROOT) — relance ./hubctl init"
            fi
        else
            warn "B3 : marker ~/.config/poulidor/parc.sh existe mais ~/.bashrc ne le source pas — relance ./hubctl init ou ajoute : [ -f ~/.config/poulidor/parc.sh ] && source ~/.config/poulidor/parc.sh"
        fi
    fi

    # (2) Mécanisme legacy : chemin direct dans bashrc (valide si match PARC_ROOT)
    if [ "$b3_resolved" = "false" ] && [ -f "$rc" ] && grep -q "POULIDOR/.secrets" "$rc" 2>/dev/null; then
        local parc_tilde
        parc_tilde=$(echo "$PARC_ROOT" | sed "s|^${HOME}|~|")
        if grep -qE "source.*${parc_tilde}/\.secrets|source.*${PARC_ROOT}/\.secrets" "$rc" 2>/dev/null; then
            pass "~/.bashrc source .secrets pour ce PARC_ROOT (mécanisme legacy — migrer vers hubctl init marker)"
            b3_resolved=true
        else
            local referenced
            referenced=$(grep -oE "[^ ]*POULIDOR/.secrets" "$rc" | head -1)
            fail "B3 : ~/.bashrc source '$referenced' mais PARC_ROOT=$PARC_ROOT — chemin hardcodé. Relance ./hubctl init pour installer le marker portable."
        fi
    fi

    if [ "$b3_resolved" = "false" ]; then
        warn "B3 : ni marker portable ni chemin direct — les vars HUB_* ne seront pas dans le shell (lance ./hubctl init)"
    fi

    local n
    n=$(env | grep -cE "^HUB_(BASE_URL|ADMIN_USERNAME|ADMIN_PASSWORD)=" || true)
    if [ "$n" -eq 3 ]; then
        pass "vars HUB_* chargées dans le shell courant"
    elif [ "$n" -gt 0 ]; then
        warn "$n/3 vars HUB_* chargées — recharge le shell (source ~/.bashrc) ou ouvre un nouveau terminal"
    else
        warn "aucune var HUB_* dans le shell — MCP hub standalone échouera (source ~/.bashrc)"
    fi

    if [ -d .opencode/node_modules ]; then
        pass ".opencode/node_modules présent (plugin TS hub.ts typé)"
    else
        warn "B5 : .opencode/node_modules absent — cd .opencode && npm install (non documenté pour les nouveaux importeurs)"
    fi

    if [ -f opencode.json ] && grep -q '"your_api_key"' opencode.json 2>/dev/null; then
        warn "opencode.json contient encore le placeholder \"your_api_key\" — la vraie clé vient de .secrets via env"
    else
        pass "opencode.json : pas de placeholder visible"
    fi

    local base_url="${HUB_BASE_URL:-http://localhost:8000}"
    if curl -sf -m 3 "${base_url}/api/health" >/dev/null 2>&1; then
        pass "Hub reachable depuis HUB_BASE_URL=$base_url"
    else
        warn "Hub injoignable sur HUB_BASE_URL=$base_url — le MCP hub (mode standalone) échouera"
    fi
}

# =============================================================================
# S7 — Apps & atelier (cohérence doc/code)
# =============================================================================
section_s7() {
    begin_section "S7" "Apps & atelier (cohérence doc/code)"
    should_skip && return

    if [ -f APPS/.gitkeep ]; then
        pass "APPS/.gitkeep présent (dossier APPS/ garanti sur fresh clone)"
    else
        fail "APPS/.gitkeep MANQUANT"
    fi

    if [ -d APPS ] && [ -n "$(ls -A APPS 2>/dev/null | grep -vE '^\.gitkeep$|^README\.md$')" ]; then
        local n
        n=$(ls -A APPS 2>/dev/null | grep -vE '^\.gitkeep$|^README\.md$' | wc -l)
        pass "APPS/ contient $n app(s) déployée(s)"
    else
        info "APPS/ vide — normal sur un fresh clone (apps déployées via ./hubctl)"
    fi

    # B6 : work/ship/deploy documentés mais pas dans le parser
    local parser=hubctl_src/hubctl_cli/__main__.py
    if [ -f "$parser" ]; then
        local missing="" cmd
        for cmd in work ship deploy; do
            if ! grep -qE "add_parser\(\"$cmd\"" "$parser" 2>/dev/null; then
                missing="$missing $cmd"
            fi
        done
        if [ -n "$missing" ]; then
            local zombie_refs
            # On exclut les archives historiques (specs/plans) — références légitimes
            zombie_refs=$(grep -rEoh "hubctl (work|ship|deploy)" --include="*.md" \
                            .opencode/skills/ docs/guide-hub/ docs/hub/ README.md AGENTS.md \
                            hubctl_src/hubctl_cli/README.md 2>/dev/null | sort -u | wc -l)
            if [ "$zombie_refs" -gt 0 ]; then
                warn "B6 : commandes$missing absentes du parser hubctl MAIS référencées dans la doc live ($zombie_refs patterns). L'équivalent réel est : ./hubctl atelier <app>"
            else
                pass "parser hubctl : pas de commande zombie dans la doc live (archives specs/plans exclues)"
            fi
        else
            pass "commandes work/ship/deploy présentes dans le parser"
        fi
    else
        warn "$parser absent — sous-module hubctl_src non initialisé (voir S1)"
    fi

    # B7 : APP_Workshop/ référencé alors que le dossier n'existe plus
    if [ ! -d APP_Workshop ]; then
        # On exclut les archives historiques (docs/superpowers/specs|plans) —
        # références légitimes au schéma legacy à des fins d'historique de design.
        local refs
        refs=$(grep -rln "APP_Workshop" \
                --include="*.py" --include="*.md" --include="*.sh" \
                hubctl_src/hubctl_cli/ HUB_base/hub/ .opencode/skills/ scripts/ \
                docs/guide-hub/ docs/hub/ \
                README.md AGENTS.md 2>/dev/null \
                | grep -v "_trash" | grep -v "scripts/check-import.sh" | wc -l)
        if [ "$refs" -gt 0 ]; then
            warn "B7 : dossier APP_Workshop/ absent mais $refs fichier(s) live y font encore référence (migration vers APPS/X/.workshop.env incomplète). Archives specs/plans exclues."
        else
            pass "aucune référence orpheline à APP_Workshop/ dans le code/doc live"
        fi
    else
        info "APP_Workshop/ existe — ancien schéma datelier toujours en place"
    fi

    if [ -x scripts/create_app.sh ] && [ -f HUBapp_TEMPLATE_base/Makefile ] && [ -d HUBapp_TEMPLATE_base/backend ]; then
        pass "scripts/create_app.sh + template canonique initialisé (création d'app possible)"
    else
        fail "scripts/create_app.sh ou HUBapp_TEMPLATE_base/{Makefile,backend/} MANQUANT — création d'app cassée"
    fi

    # B11 : frontend/ parasite à la racine (propriétaire root)
    if [ -d frontend ] && [ "$(stat -c %U frontend 2>/dev/null)" = "root" ]; then
        warn "B11 : frontend/ à la racine appartient à root — artefact parasite (différent du frontend du HUB qui est dans HUB_base/frontend/)"
    else
        info "pas de frontend/ parasite à la racine"
    fi
}

# =============================================================================
# S8 — GitHub CLI (gh)
# =============================================================================
section_s8() {
    begin_section "S8" "GitHub CLI (gh)"
    should_skip && return
    if ! command -v gh >/dev/null 2>&1; then
        warn "gh MANQUANT — install.sh (Phase 1) ou apt-get install gh ; debug GitHub (PR, runs CI, API)"
        return 0
    fi
    pass "gh présent ($(gh --version 2>/dev/null | head -1 | awk '{print $3}'))"
    if gh auth status >/dev/null 2>&1; then
        pass "gh authentifié ($(gh api user -q .login 2>/dev/null || echo 'compte OK'))"
    else
        warn "gh non authentifié — lance ./scripts/gh-auth.sh (token du parc, fallback interactif)"
    fi
}

# =============================================================================
# S9 — Node.js
# =============================================================================
section_s9() {
    begin_section "S9" "Node.js (MCP zai, plugin opencode, build HUBCSS)"
    should_skip && return
    if ! command -v node >/dev/null 2>&1; then
        warn "node MANQUANT — install.sh (Phase 1) ou apt-get install nodejs npm"
        return 0
    fi
    local major
    major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
    if [ "$major" -ge 18 ]; then
        pass "node présent ($(node --version))"
    else
        warn "node $(node --version) < 18 (Vite 5 requiert 18+) — remédie : NodeSource 20 (docs/outillage.md)"
    fi
    if command -v npx >/dev/null 2>&1; then
        pass "npx présent"
    else
        warn "npx MANQUANT — apt-get install npm"
    fi
}

# =============================================================================
# S10 — QEMU/KVM (labo vm-lab, optionnel)
# =============================================================================
section_s10() {
    begin_section "S10" "QEMU/KVM (labo vm-lab — optionnel)"
    should_skip && return
    local missing="" tool
    for tool in qemu-system-x86_64 qemu-img cloud-localds; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        warn "QEMU incomplet — manque:$missing (optionnel — requis uniquement par le labo vm-lab : apt-get install qemu-kvm qemu-utils cloud-image-utils)"
    else
        pass "outils QEMU présents"
    fi
    if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
        pass "/dev/kvm accessible"
    else
        warn "/dev/kvm absent ou non accessible (optionnel — VM labo sans accélération KVM)"
    fi
}

# =============================================================================
# Exécution
# =============================================================================
section_s1
section_s2
section_s3
section_s4
section_s5
section_s6
section_s7
section_s8
section_s9
section_s10

# =============================================================================
# Résumé
# =============================================================================
echo ""
echo "${C_BOLD}${C_CYAN}════════════════════════════════════════════${C_NC}"
if [ "$FAIL" -gt 0 ]; then
    echo "${C_BOLD}${C_RED}  ✗ $FAIL échec(s)   ⚠ $WARN avertissement(s)   ✓ $PASS OK${C_NC}"
    echo "${C_BOLD}${C_RED}  → Machine NON opérationnelle pour POULIDOR${C_NC}"
    rc=1
else
    echo "${C_BOLD}${C_GREEN}  ✓ $PASS OK   ⚠ $WARN avertissement(s)   ✗ 0 échec${C_NC}"
    if [ "$WARN" -gt 0 ]; then
        echo "${C_BOLD}${C_YELLOW}  → Machine opérationnelle, mais $WARN point(s) à surveiller${C_NC}"
    else
        echo "${C_BOLD}${C_GREEN}  → Machine 100 % opérationnelle pour POULIDOR${C_NC}"
    fi
    rc=0
fi
echo "${C_BOLD}${C_CYAN}════════════════════════════════════════════${C_NC}"
exit $rc
