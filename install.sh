#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

set -euo pipefail

# =============================================================================
# POULIDOR — Installation automatique tout-en-un
# =============================================================================
# Installe les prérequis système (Docker, Python, git, make, openssl, etc.),
# configure les services (Docker daemon, groupe utilisateur), initialise le
# Hub (./hubctl init), et affiche un résumé.
#
# Usage :
#   sudo ./install.sh              # Installation idempotente (relançable sans risque)
#   sudo ./install.sh --force      # Force la réinit du Hub (.env régénéré)
#   sudo ./install.sh --runner     # Installe aussi le runner CI GitHub (opt-in)
#   sudo ./install.sh --help       # Aide
#
# Les fonctions (parsing, phase runner CI, guidance de fin) vivent dans
# scripts/lib/install-lib.sh — testées par scripts/tests/test_install_sh.sh.
# =============================================================================

# ── Racine du script, mode non interactif, fonctions ─────────────────────────

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sans TTY (install pipee, VM, CI) debconf cherchait un frontend Dialogue/Readline
# et crachait six lignes de bruit avant apt (constat VM 26/11/2026).
export DEBIAN_FRONTEND=noninteractive

# Couleurs, helpers, parsing des arguments, phase runner CI et guidance de fin.
# shellcheck source=scripts/lib/install-lib.sh
source "$ROOT_DIR/scripts/lib/install-lib.sh"

install_parse_args "$@"
# ── Vérifications préalables ─────────────────────────────────────────────────

say ""
say "${BOLD}${CYAN}══════════════════════════════════════════════════════════${NC}"
say "${BOLD}${CYAN}   POULIDOR — Installation automatique${NC}"
if $FORCE; then
    say "${BOLD}${CYAN}   (mode --force)${NC}"
fi
say "${BOLD}${CYAN}══════════════════════════════════════════════════════════${NC}"
say ""

# sudo obligatoire (apt install, systemctl, usermod)
if [ "$(id -u)" -ne 0 ]; then
    err "Ce script nécessite sudo. Relance avec : sudo $0 $*"
fi

# Debian/Ubuntu/Mint uniquement
if ! command -v apt-get &>/dev/null; then
    err "Distribution non supportée. Debian/Ubuntu/Linux Mint requis (apt-get introuvable)."
fi

# Utilisateur réel (pas root) pour usermod -aG docker
REAL_USER="${SUDO_USER:-$USER}"
# Son home (getent) — pas de /home/<user> en dur : le token hubctl et le
# fichier ~/.bashrc du marqueur vivent sous le home réel.
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
[ -n "$REAL_HOME" ] || REAL_HOME="/home/$REAL_USER"

ok "Utilisateur : ${GREEN}${REAL_USER}${NC}"
ok "Distribution : $(. /etc/os-release && echo "$PRETTY_NAME")"
say ""

# ── Phase 1 : Prérequis système ──────────────────────────────────────────────

say "${BOLD}Phase 1 — Prérequis système${NC}"
say ""

# 1a. apt-get update (une seule fois)
say "  Mise à jour des dépôts apt..."
apt-get update -qq

# 1b. Installer curl et gnupg (requis pour ajouter le repo Docker) s'ils manquent
PACKAGES_BASE=("curl" "ca-certificates" "gnupg")
for pkg in "${PACKAGES_BASE[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        apt-get install -y -qq "$pkg" >/dev/null
    fi
done

# 1c. Ajouter le repo Docker officiel (si pas déjà présent)
DOCKER_REPO_FILE="/etc/apt/sources.list.d/docker.list"
NEED_REPO_UPDATE=false
DOCKER_FROM_REPO=true

if [ ! -f "$DOCKER_REPO_FILE" ]; then
    NEED_REPO_UPDATE=true
else
    # Vérifier que la clé GPG Docker est présente
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        NEED_REPO_UPDATE=true
    fi
fi

if $NEED_REPO_UPDATE; then
    say "  Ajout du dépôt Docker officiel..."
    install -m 0755 -d /etc/apt/keyrings

    # Router vers le dépôt Docker de la bonne distro (Debian ≠ Ubuntu ; Mint/derivés Ubuntu remappés)
    . /etc/os-release
    case "${ID:-debian}" in
        ubuntu|linuxmint|neon|pop)
            DOCKER_DISTRO="ubuntu"
            CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            ;;
        *)
            DOCKER_DISTRO="debian"
            CODENAME="${VERSION_CODENAME}"
            ;;
    esac
    if [ -z "$CODENAME" ]; then
        warn "Codename introuvable, utilisation de 'bookworm' (Debian 12)."
        CODENAME="bookworm"
    fi

    if curl -fsSL "https://download.docker.com/linux/$DOCKER_DISTRO/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg 2>/dev/null && \
       chmod a+r /etc/apt/keyrings/docker.gpg && \
       echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_DISTRO $CODENAME stable" > "$DOCKER_REPO_FILE" && \
       apt-get update -qq; then
        ok "Dépôt Docker ajouté ($DOCKER_DISTRO $CODENAME)"
    else
        warn "Échec d'ajout du dépôt Docker officiel — utilisation du paquet docker.io système (moins récent)"
        DOCKER_FROM_REPO=false
        rm -f "$DOCKER_REPO_FILE"
    fi
else
    ok "Dépôt Docker déjà configuré"
fi

# 1c-bis. GitHub CLI (gh) — paquet distro si disponible, sinon repo officiel GitHub CLI
if apt-cache show gh >/dev/null 2>&1; then
    ok "gh disponible dans les dépôts distro"
else
    say "  gh absent des dépôts — ajout du repo officiel GitHub CLI..."
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
    ok "Repo officiel GitHub CLI configuré"
fi

# 1d. Installer les paquets (idempotent)
if $DOCKER_FROM_REPO; then
    PACKAGES=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-compose-plugin"
        "python3"
        "python3-venv"
        "python3-pip"
        "git"
        "make"
        "openssl"
        "curl"
        "iproute2"
        "rsync"
        "gh"
        "nodejs"
        "npm"
    )
else
    PACKAGES=(
        "docker.io"
        "docker-compose-v2"
        "python3"
        "python3-venv"
        "python3-pip"
        "git"
        "make"
        "openssl"
        "curl"
        "iproute2"
        "rsync"
        "gh"
        "nodejs"
        "npm"
    )
fi

INSTALLED=0
SKIPPED=0
if $FORCE; then
    say "  (mode --force : réinstallation des paquets déjà présents)"
    apt-get install --reinstall -y -qq "${PACKAGES[@]}"
    INSTALLED=${#PACKAGES[@]}
    SKIPPED=0
else
    for pkg in "${PACKAGES[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            SKIPPED=$((SKIPPED + 1))
        else
            apt-get install -y -qq "$pkg" >/dev/null 2>&1 || {
                warn "Échec installation $pkg — tentative sans -qq..."
                apt-get install -y "$pkg" >/dev/null
            }
            INSTALLED=$((INSTALLED + 1))
        fi
    done
fi

ok "${PACKAGES[*]}"
say "  ${GREEN}${SKIPPED}${NC} déjà installés, ${GREEN}${INSTALLED}${NC} nouvellement installés"

# 1e. Vérifications critiques
command -v docker &>/dev/null || err "docker CLI introuvable après installation."
command -v git &>/dev/null || err "git introuvable après installation."
command -v python3 &>/dev/null || err "python3 introuvable après installation."
python3 -c "import venv" 2>/dev/null || err "python3-venv non fonctionnel."
ok "Vérifications : docker, git, python3-venv — OK"
command -v gh &>/dev/null || warn "gh introuvable après installation (non bloquant — debug GitHub)."
command -v node &>/dev/null || warn "node introuvable après installation (non bloquant — MCP zai / build HUBCSS)."
say ""

# 1f. Pools d'adresses Docker (F14) — sans ça, le daemon n'offre que ≈31
# sous-réseaux pour 33 apps × 1 network compose chacune + hub + stacks de
# test → « invalid pool request: Pool overlaps » dès l'installation de la
# flotte. Merge idempotent (dns/runtimes préservés) via python3 (vérifié
# en 1e). Écrit avant le démarrage du daemon : pools actifs dès le boot.
say "${BOLD}Configuration des pools d'adresses Docker${NC}"
if python3 - <<'PYEOF'
import json

path = "/etc/docker/daemon.json"
try:
    with open(path) as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
cfg["default-address-pools"] = [
    {"base": "172.16.0.0/12", "size": 24},
    {"base": "10.200.0.0/14", "size": 24},
]
with open("/tmp/daemon.json.new", "w") as f:
    json.dump(cfg, f, indent=4)
PYEOF
then
    install -m 0644 /tmp/daemon.json.new /etc/docker/daemon.json
    rm -f /tmp/daemon.json.new
    ok "Pools d'adresses configurés (172.16/12 + 10.200/14 en /24 — ~5100 réseaux)"
else
    warn "Échec de la config des pools Docker (non bloquant — hubctl docker check)"
fi
say ""

# ── Phase 2 : Services ───────────────────────────────────────────────────────

say "${BOLD}Phase 2 — Configuration des services${NC}"
say ""

# 2a. Activer Docker au boot
if systemctl is-enabled --quiet docker 2>/dev/null; then
    ok "Docker déjà activé au boot"
else
    systemctl enable docker
    ok "Docker activé au boot"
fi

# 2b-pre. Si apt a (ré)installé un paquet docker en Phase 1, le fichier unit
# docker.socket a pu être écrasé à chaud → socket invalidé par systemd
# ("Socket unit configuration has changed ... not functional until restarted"),
# puis rate-limit au redémarrage → "Failed to start docker.service". On prévient
# ce piège avant de démarrer le service. Commandes idempotentes (inoffensives si
# apt n'a rien réinstallé).
systemctl daemon-reload
systemctl reset-failed docker.socket docker.service 2>/dev/null || true
systemctl start docker.socket 2>/dev/null || true

# 2b. Démarrer Docker
if systemctl is-active --quiet docker 2>/dev/null; then
    ok "Docker déjà actif"
else
    systemctl start docker
    ok "Docker démarré"
fi

# 2c. Ajouter l'utilisateur au groupe docker
if id -nG "$REAL_USER" 2>/dev/null | grep -qw "docker"; then
    ok "${REAL_USER} déjà dans le groupe docker"
else
    usermod -aG docker "$REAL_USER"
    ok "${REAL_USER} ajouté au groupe docker"
    warn "Groupe docker : déconnecte/reconnecte-toi ou lance 'newgrp docker' pour l'activer."
fi

# 2d. Vérifier docker compose (plugin v2)
if docker compose version &>/dev/null; then
    COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "?")
    ok "Docker Compose v2 (${COMPOSE_VER})"
else
    err "Docker Compose v2 (plugin) non fonctionnel. Vérifie docker-compose-plugin."
fi

# 2e. Vérifier l'accès au socket Docker
#     Note : sous sudo, root a accès au socket même si l'utilisateur n'est pas
#     encore dans le groupe (newgrp requis côté utilisateur).
if docker info &>/dev/null; then
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    ok "Docker Engine opérationnel (${DOCKER_VER})"
else
    err "Docker daemon injoignable. Vérifie : systemctl status docker"
fi
say ""

# ── Phase 3 : Initialisation du Hub ──────────────────────────────────────────

say "${BOLD}Phase 3 — Initialisation du Hub${NC}"
say ""

cd "$ROOT_DIR"

# 3a-prec. Synchroniser les submodules (HUB_base, HUBapp_TEMPLATE_base, etc.)
# Un simple `git pull` ne déplace PAS les submodules : sans cette étape, le code
# reste à un ancien pointeur (badge de version absent, commits « manquants »).
if git rev-parse --is-inside-work-tree &>/dev/null; then
    say "  Synchronisation des submodules..."
    if sudo -u "$REAL_USER" git submodule update --init --recursive; then
        ok "Submodules synchronisés"
    else
        warn "Échec de synchro des submodules (droits d'accès aux dépôts ?). Vérifie : git submodule update --init --recursive"
    fi
fi

# 3a. Vérifier si le Hub est déjà opérationnel (idempotence)
API_PORT="$(grep -E '^HUB_API_PORT=' HUB_base/.env 2>/dev/null | cut -d= -f2 || echo "8000")"
HUB_ALREADY_RUNNING=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^hub-api$'; then
    if curl -sf "http://localhost:${API_PORT}/api/health" &>/dev/null; then
        HUB_ALREADY_RUNNING=true
    fi
fi

# 3b. Lancer ./hubctl init (ou skip si déjà running et pas --force)
if $HUB_ALREADY_RUNNING && ! $FORCE; then
    ok "Hub déjà opérationnel — phase init skippée"
    # Le code a pu évoluer depuis le dernier démarrage (git pull) : en prod les
    # fichiers statiques sont cuits dans l'image frontend (COPY public/), un
    # simple restart ne suffit pas → rebuild + relance pour converger.
    say "  Reconvergence du Hub (build + up-prod, cache Docker)..."
    if sudo -u "$REAL_USER" make -C HUB_base build && sudo -u "$REAL_USER" make -C HUB_base up-prod; then
        ok "Hub reconvergé avec le code à jour"
    else
        warn "Reconvergence échouée — le Hub reste sur l'ancienne image. Vérifie : make -C HUB_base build"
    fi
    warn "Pour forcer la réinit : sudo ./install.sh --force"
else
    say "  Lancement de ./hubctl init..."
    say ""
    INIT_ARGS=""
    if $FORCE; then
        INIT_ARGS="--force"
    fi
    # HUBCTL_INSTALLER=1 : l'installeur pose lui-même les unités système en root
    # (phase 3c) — `hubctl init`, lancé sans TTY, ne réclame alors aucune action
    # manuelle pour elles (verdict VM 26/11 : rappel trompeur juste avant).
    if ! sudo -u "$REAL_USER" env HUBCTL_INSTALLER=1 ./hubctl init $INIT_ARGS; then
        say ""
        err "L'initialisation du Hub a échoué. Logs : sudo docker compose -f HUB_base/docker-compose.yml logs hub-api"
    fi
fi

# 3c. Services hôtes : hubctl-atelier (pilotage ateliers + coffre par le Hub)
# et hubctl-update (mises à jour automatiques). L'installeur les rend et les
# pose en root — idempotent, jamais fatal (scripts/lib/install-lib.sh).
# Le token atelier est créé par ./hubctl init (étape _ensure_atelier_service).
say "  Services hôtes hubctl-atelier / hubctl-update..."
if [ ! -s "$REAL_HOME/.config/hubctl/atelier_token" ]; then
    warn "Token atelier absent ($REAL_HOME/.config/hubctl/atelier_token) — ./hubctl init le créera ; activation reportée au prochain init"
else
    install_host_service atelier
fi
install_host_service update
say ""

# ── Phase 3.5 : Runner CI GitHub (self-hosted) — en opt-in (--runner) ────────
# Sans le flag : un seul message, aucune résolution d'origin, aucun prompt.
# (Logique dans scripts/lib/install-lib.sh : phase_runner_ci.)

phase_runner_ci
say ""

# ── Phase 4 : Résumé ─────────────────────────────────────────────────────────

say "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
say "${BOLD}${GREEN}   POULIDOR — Installation terminée !${NC}"
say "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
say ""

# Lire l'IP hôte depuis le .env si présent
HOST_IP="$(grep -E '^HUB_HOST=' HUB_base/.env 2>/dev/null | cut -d= -f2 || echo "localhost")"
API_PORT="$(grep -E '^HUB_API_PORT=' HUB_base/.env 2>/dev/null | cut -d= -f2 || echo "8000")"

DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "?")
COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "?")

say "  ${BOLD}Docker${NC}     ${GREEN}✓${NC} ${DOCKER_VER}   Compose ${GREEN}✓${NC} ${COMPOSE_VER}"
say ""
say "  ${BOLD}Hub${NC}        https://${HOST_IP}"
say "  ${BOLD}API${NC}        http://${HOST_IP}:${API_PORT}/api/health"
say ""
say "  ${BOLD}Login${NC}      admin (voir HUB_base/.env pour le mot de passe généré)"
say ""
say "  ${BOLD}Services${NC}   $(docker ps --format '{{.Names}}' 2>/dev/null | grep '^hub-' | tr '\n' ' ')"
say ""
print_next_steps
if ! id -nG "$REAL_USER" 2>/dev/null | grep -qw "docker"; then
    warn "Action requise : lance 'newgrp docker' ou reconnecte-toi pour activer le groupe docker."
    say ""
fi
