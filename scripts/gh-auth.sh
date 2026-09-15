#!/usr/bin/env bash
# =============================================================================
# POULIDOR — Authentification gh (GitHub CLI)
# =============================================================================
# Authentifie gh avec le token du parc, fallback interactif sinon. Idempotent.
# Ordre de résolution :
#   1. gh déjà authentifié                       → exit 0
#   2. .secrets du parc (GH_PAT, sinon GITHUB_TOKEN) → gh auth login --with-token
#   3. DB du hub (app_settings 'github_token')   → gh auth login --with-token
#   4. Sinon                                     → gh auth login (device flow)
#
# Usage :
#   ./scripts/gh-auth.sh          # authentifier (fallback interactif si besoin)
#   ./scripts/gh-auth.sh --check  # vérifier sans modifier (exit 0/1)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_NC='\033[0m'
if [ -t 1 ]; then :; else C_GREEN=''; C_YELLOW=''; C_RED=''; C_NC=''; fi
ok()   { echo -e "  ${C_GREEN}✓${C_NC} $1"; }
warn() { echo -e "  ${C_YELLOW}⚠${C_NC} $1"; }
err()  { echo -e "  ${C_RED}✗${C_NC} $1" >&2; }

CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

command -v gh >/dev/null 2>&1 || { err "gh introuvable — apt-get install gh (ou install.sh)"; exit 2; }

# 1) Déjà authentifié ?
if gh auth status >/dev/null 2>&1; then
    ok "gh déjà authentifié ($(gh api user -q .login 2>/dev/null || echo 'OK'))"
    exit 0
fi

if $CHECK_ONLY; then
    warn "gh non authentifié — lance ./scripts/gh-auth.sh"
    exit 1
fi

PAT=""
# 2) .secrets du parc
if [ -f "$PARC_ROOT/.secrets" ]; then
    # shellcheck disable=SC1091
    source "$PARC_ROOT/.secrets"
    PAT="${GH_PAT:-${GITHUB_TOKEN:-}}"
fi
# 3) DB du hub (même mécanique que install.sh resolve_hub_github_pat)
if [ -z "$PAT" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^hub-db$'; then
    PAT=$(docker exec hub-db psql -U hubadmin -d hub_auth -t -A -c \
          "SELECT value::text FROM app_settings WHERE key='github_token';" 2>/dev/null | tr -d '[:space:]')
fi

if [ -n "$PAT" ]; then
    if echo "$PAT" | gh auth login --with-token >/dev/null 2>&1; then
        ok "gh authentifié via le token du parc"
        gh auth status
        exit 0
    fi
    warn "Token du parc refusé (expiré ou scopes insuffisants) — fallback interactif"
fi

# 4) Fallback interactif (device flow)
echo ""
warn "Authentification interactive — suivre les instructions (device flow navigateur)"
gh auth login
if gh auth status >/dev/null 2>&1; then
    ok "gh authentifié"
else
    err "Authentification échouée"
    exit 1
fi
