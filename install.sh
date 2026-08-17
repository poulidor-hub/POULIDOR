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

    # Détecter la distribution : Debian a son propre dépôt Docker, Ubuntu/Mint le dépôt ubuntu
    DISTRO_ID="$(. /etc/os-release && echo "$ID")"                    # debian | ubuntu | linuxmint
    DISTRO_REPO="$DISTRO_ID"
    [ "$DISTRO_ID" = "linuxmint" ] && DISTRO_REPO="ubuntu"
    CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    if [ -z "$CODENAME" ] && [ "$DISTRO_ID" = "linuxmint" ]; then
        # Fallback : Linux Mint ne fournit pas toujours UBUNTU_CODENAME
        CODENAME="$(. /etc/os-release && echo "$DEBIAN_CODENAME")"
    fi
    if [ -z "$CODENAME" ]; then
        if [ "$DISTRO_ID" = "debian" ]; then
            warn "Codename introuvable, utilisation de 'bookworm' (Debian 12)."
            CODENAME="bookworm"
        else
            # Linux Mint 22.x = Ubuntu 24.04 = "noble"
            warn "Codename Ubuntu introuvable, utilisation de 'noble' (Ubuntu 24.04)."
            CODENAME="noble"
        fi
    fi

    if curl -fsSL "https://download.docker.com/linux/${DISTRO_REPO}/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg 2>/dev/null && \
       chmod a+r /etc/apt/keyrings/docker.gpg && \
       echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_REPO} $CODENAME stable" > "$DOCKER_REPO_FILE" && \
       apt-get update -qq; then
        ok "Dépôt Docker ajouté (${DISTRO_REPO}/${CODENAME})"
    else
        warn "Échec d'ajout du dépôt Docker officiel — utilisation du paquet docker.io système (moins récent)"
        DOCKER_FROM_REPO=false
        rm -f "$DOCKER_REPO_FILE"
    fi
else
    ok "Dépôt Docker déjà configuré"
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
    )
else
    # Fallback paquets système. Debian bookworm n'a pas docker-compose-v2
    # (paquet Ubuntu) — compose v1 (docker-compose) y est le seul recours ;
    # la vérification "docker compose v2" plus bas échouera alors avec un
    # message clair (le fallback est déjà signalé comme dégradé).
    if [ "$(. /etc/os-release && echo "$ID")" = "debian" ]; then
        PACKAGES=(
            "docker.io"
            "docker-compose"
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
        )
    fi
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
                apt-get install -y "$pkg" || err "Impossible d'installer le paquet $pkg (voir messages apt ci-dessus)."
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

# 1f. Initialiser les sous-modules (hubctl_src, hub-mcp, etc.)
say "  Initialisation des sous-modules git…"
if ! sudo -u "$REAL_USER" git submodule update --init --recursive; then
    err "Échec de l'initialisation des sous-modules git. Vérifiez l'accès SSH aux repos GitHub."
fi
ok "Sous-modules initialisés"
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

# 2f. Firewall VPN WireGuard (cloisonnement hub + apps uniquement)
#     Les clients VPN (wg0) ne peuvent atteindre que les ports publiés par
#     Docker (DNAT) — pas le LAN, pas les réseaux internes, pas l'hôte.
#     Script + unit systemd idempotents ; inoffensif si le VPN est désactivé.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/hub-vpn-firewall.sh" ]; then
    install -m 0755 "$SCRIPT_DIR/scripts/hub-vpn-firewall.sh" /usr/local/sbin/hub-vpn-firewall.sh
    install -m 0644 "$SCRIPT_DIR/scripts/systemd/hub-vpn-firewall.service" /etc/systemd/system/hub-vpn-firewall.service
    systemctl daemon-reload
    systemctl enable --now hub-vpn-firewall.service >/dev/null 2>&1
    if systemctl is-active --quiet hub-vpn-firewall.service; then
        ok "Cloisonnement VPN installé et actif (hub-vpn-firewall.service)"
    else
        warn "Cloisonnement VPN installé mais inactif — vérifie : systemctl status hub-vpn-firewall"
    fi
else
    warn "scripts/hub-vpn-firewall.sh introuvable — cloisonnement VPN non installé"
fi
say ""

# ── Phase 3 : Initialisation du Hub ──────────────────────────────────────────

say "${BOLD}Phase 3 — Initialisation du Hub${NC}"
say ""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

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
    warn "Pour forcer la réinit : sudo ./install.sh --force"
else
    say "  Lancement de ./hubctl init..."
    say ""
    INIT_ARGS=""
    if $FORCE; then
        INIT_ARGS="--force"
    fi
    if ! sudo -u "$REAL_USER" ./hubctl init $INIT_ARGS; then
        say ""
        err "L'initialisation du Hub a échoué. Logs : sudo docker compose -f HUB_base/docker-compose.yml logs hub-api"
    fi
fi
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
say "${BOLD}Prochaines étapes :${NC}"
say "  1. Ouvre https://${HOST_IP} dans un navigateur"
say "  2. Connecte-toi et change le mot de passe admin"
say "  3. Lance ${BOLD}./hubctl${NC} → Apps → Ajouter une application"
say "  4. Ou demande à l'IA : « Crée une app mon-outil dans POULIDOR »"
say ""
if ! id -nG "$REAL_USER" 2>/dev/null | grep -qw "docker"; then
    warn "Action requise : lance 'newgrp docker' ou reconnecte-toi pour activer le groupe docker."
    say ""
fi
