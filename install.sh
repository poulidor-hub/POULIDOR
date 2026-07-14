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

# Placeholder pour les phases (remplacé par les tâches suivantes)
say "${BOLD}Phases non encore implémentées.${NC}"
