#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# POULIDOR — Installation automatique tout-en-un
# =============================================================================
# Installe les prérequis système (Docker, Python, git, make, openssl, etc.),
# configure les services (Docker daemon, groupe utilisateur), initialise le
# Hub (./hubctl init), et affiche un résumé.
#
# Usage :
#   sudo ./install.sh              # Installation idempotente
#   sudo ./install.sh --force      # Force la réinit du Hub (.env écrasé)
#   sudo ./install.sh --help       # Aide
# =============================================================================

# ── Couleurs & helpers ───────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

say()  { echo -e "$1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# ── Parsing des arguments ────────────────────────────────────────────────────

FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        -h|--help)
            say "Usage : sudo $0 [--force] [--help]"
            say ""
            say "  Installation automatique de POULIDOR (prérequis + Hub)."
            say "  Idempotent : relançable sans risque."
            say ""
            say "  --force    Force la réinitialisation du Hub (.env écrasé)."
            say "  --help     Affiche cette aide."
            exit 0
            ;;
        *)
            err "Argument inconnu : $1 (utilisez --help)"
            ;;
    esac
done

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
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Détecter le codename Ubuntu (Mint est basé sur Ubuntu, on remappe)
    CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    if [ -z "$CODENAME" ]; then
        # Fallback : Linux Mint ne fournit pas toujours UBUNTU_CODENAME
        CODENAME="$(. /etc/os-release && echo "$DEBIAN_CODENAME")"
    fi
    # Linux Mint 22.x = Ubuntu 24.04 = "noble"
    if [ -z "$CODENAME" ]; then
        warn "Codename Ubuntu introuvable, utilisation de 'noble' (Ubuntu 24.04)."
        CODENAME="noble"
    fi

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" > "$DOCKER_REPO_FILE"
    apt-get update -qq
    ok "Dépôt Docker ajouté ($CODENAME)"
else
    ok "Dépôt Docker déjà configuré"
fi

# 1d. Installer les paquets (idempotent)
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
)

INSTALLED=0
SKIPPED=0
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

ok "${PACKAGES[*]}"
say "  ${GREEN}${SKIPPED}${NC} déjà installés, ${GREEN}${INSTALLED}${NC} nouvellement installés"

# 1e. Vérifications critiques
command -v docker &>/dev/null || err "docker CLI introuvable après installation."
command -v git &>/dev/null || err "git introuvable après installation."
command -v python3 &>/dev/null || err "python3 introuvable après installation."
python3 -c "import venv" 2>/dev/null || err "python3-venv non fonctionnel."
ok "Vérifications : docker, git, python3-venv — OK"
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
