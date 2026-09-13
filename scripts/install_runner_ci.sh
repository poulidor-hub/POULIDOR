#!/usr/bin/env bash
# =============================================================================
# POULIDOR — Installation du runner CI GitHub self-hosted (uniquement)
# =============================================================================
# Extrait de install.sh (Phase 3.5). Installe un runner GitHub Actions
# self-hosted en service systemd pour exécuter la CI du méta sans consommer
# de minutes Actions (org free) et permettre le job « Health des hubs ».
#
# Usage :
#   sudo ./scripts/install_runner_ci.sh            # installation idempotente
#   sudo DRY_RUN=true ./scripts/install_runner_ci.sh   # prévisualisation
#   sudo ./scripts/install_runner_ci.sh --help     # aide
#
# PAT GitHub (scopes repo+workflow, accès à tous les repos du parc), résolu
# dans l'ordre : DB du hub (app_settings.github_token) → variable GH_PAT →
# prompt interactif.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
say()  { echo -e "$1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }

DRY_RUN="${DRY_RUN:-false}"
RUNNER_USER="${SUDO_USER:-$USER}"
RUNNER_DIR="/opt/actions-runner"
LABELS="${LABELS:-POULIDOR}"
HUB_DB_CONTAINER="${HUB_DB_CONTAINER:-hub-db}"
REPO_SLUG="${REPO_SLUG:-POULIDOR-Audit-Developpement/POULIDOR}"
FALLBACK_VERSION="2.337.0"

run_cmd() { if [ "$DRY_RUN" = true ]; then say "  [dry-run] $*"; else "$@"; fi; }

usage() {
    say "Usage : sudo $0 [--repo OWNER/NAME] [--user USER] [--help]"
    say ""
    say "  Installe le runner GitHub Actions self-hosted (service systemd) pour"
    say "  exécuter la CI du méta POULIDOR. Idempotent."
    say ""
    say "  --repo OWNER/NAME   Repo ciblé par le runner (défaut : $REPO_SLUG)"
    say "  --user USER         Utilisateur du service (défaut : $RUNNER_USER)"
    say "  --help              Affiche cette aide."
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) REPO_SLUG="$2"; shift 2 ;;
        --user) RUNNER_USER="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) err "Argument inconnu : $1 (utilisez --help)" ;;
    esac
done

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" != true ]; then
    err "Ce script nécessite sudo. Relancez : sudo $0 $* (ou DRY_RUN=true pour la prévisualisation)"
fi

if [ "$DRY_RUN" != true ]; then
    say "${BOLD}${CYAN}   POULIDOR — Runner CI GitHub self-hosted${NC}"
    say ""
fi

# ── 1. Résolution du PAT GitHub ──────────────────────────────────────────────
resolve_pat() {
    local pat=""
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${HUB_DB_CONTAINER}$"; then
        pat=$(docker exec "$HUB_DB_CONTAINER" psql -U hubadmin -d hub_auth -t -A -c \
              "SELECT value::text FROM app_settings WHERE key='github_token';" 2>/dev/null | tr -d '[:space:]')
        [ -n "$pat" ] && ok "PAT lu depuis la DB du hub ($HUB_DB_CONTAINER)"
    fi
    [ -z "$pat" ] && pat="${GH_PAT:-}"
    if [ -z "$pat" ]; then
        read -r -s -p "PAT GitHub (scopes repo+workflow) : " pat
        say ""
    fi
    [ -n "$pat" ] && echo "$pat"
}

# ── 2. Idempotence ───────────────────────────────────────────────────────────
if [ -f "$RUNNER_DIR/.credentials" ] && systemctl list-units --type=service 2>/dev/null | grep -q 'actions.runner.*.service'; then
    ok "Runner déjà installé et le service actions.runner.* est actif — rien à faire."
    exit 0
fi

# ── 3. PAT ───────────────────────────────────────────────────────────────────
PAT=$(resolve_pat || true)
if [ -z "$PAT" ]; then
    warn "Aucun PAT GitHub disponible — installation ignorée."
    warn "Relancez avec la DB du hub accessible, la variable GH_PAT, ou fournissez-le au prompt."
    exit 0
fi

# ── 4. Version du runner ─────────────────────────────────────────────────────
VER=$(curl -s -m 15 "https://api.github.com/repos/actions/runner/releases/latest" \
      | grep -oP '"tag_name":\s*"v\K[^"]*' || echo "$FALLBACK_VERSION")
ok "Runner version : ${VER}"

# ── 5. Téléchargement + extraction ───────────────────────────────────────────
if [ ! -f "$RUNNER_DIR/config.sh" ]; then
    run_cmd mkdir -p "$RUNNER_DIR"
    run_cmd curl -sL -o /tmp/actions-runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz"
    run_cmd tar xzf /tmp/actions-runner.tar.gz -C "$RUNNER_DIR"
    run_cmd rm -f /tmp/actions-runner.tar.gz
fi

# ── 6. Registration token + configuration ────────────────────────────────────
REPO_API="https://api.github.com/repos/${REPO_SLUG}/actions/runners/registration-token"
if [ "$DRY_RUN" = true ]; then
    REG_TOKEN="DRY_RUN_REGISTRATION_TOKEN"
    say "  [dry-run] POST $REPO_API"
else
    REG_TOKEN=$(curl -s -m 15 -X POST -H "Authorization: Bearer $PAT" "$REPO_API" \
                | grep -oP '"token":\s*"\K[^"]*')
fi
[ -z "$REG_TOKEN" ] && err "Registration token indisponible (PAT sans accès admin au repo ?)"

run_cmd chown -R "${RUNNER_USER}:${RUNNER_USER}" "$RUNNER_DIR"
run_cmd su - "$RUNNER_USER" -c "cd $RUNNER_DIR && ./config.sh --url https://github.com/${REPO_SLUG} --token ${REG_TOKEN} --labels ${LABELS} --unattended --work _work"

# ── 7. Service systemd ───────────────────────────────────────────────────────
run_cmd bash -c "cd $RUNNER_DIR && ./svc.sh install ${RUNNER_USER}"
run_cmd bash -c "cd $RUNNER_DIR && ./svc.sh start"

if [ "$DRY_RUN" = true ]; then
    ok "(dry-run) service actions.runner.* serait installé et démarré (User=${RUNNER_USER})"
elif systemctl list-units --type=service 2>/dev/null | grep -q 'actions.runner.*.service'; then
    ok "Runner CI GitHub installé et démarré (service actions.runner.*, User=${RUNNER_USER})"
    say ""
    say "  Vérification : systemctl status actions.runner.*"
    say "  GitHub : Settings → Actions → Runners"
else
    warn "Runner installé mais service introuvable — vérifiez : cd $RUNNER_DIR && ./svc.sh status"
fi
