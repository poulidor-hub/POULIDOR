#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)
#
# FORCE et RUNNER sont positionnés ici et consommés par install.sh (le script
# sudo qui source cette lib) — d'où la directive ci-dessous.
# shellcheck disable=SC2034

# install-lib.sh — fonctions de install.sh (racine du méta-repo), sourcé par le
# script ET par scripts/tests/test_install_sh.sh.
#
# install.sh est un script sudo linéaire (apt, systemctl, usermod) : il ne peut
# pas être chargé dans un test. Les morceaux qui portent un comportement à
# verrouiller vivent ici — parsing des arguments, phase « runner CI », guidance
# de fin d'installation.

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
#
# Le runner CI GitHub est en OPT-IN (plan « installation sans friction », 26/11) :
# par défaut il ne se passait déjà rien de bon — sans PAT, l'install affichait
# un avertissement ; avec TTY elle PROMPTAIT pour un PAT qu'un utilisateur du
# parc public n'a pas. --no-runner reste accepté (compatibilité) et ne fait rien.

install_usage() {
    say "Usage : sudo $0 [--force] [--runner] [--help]"
    say ""
    say "  Installation automatique de POULIDOR (prérequis + Hub)."
    say "  Idempotent : relançable sans risque."
    say ""
    say "  --force    Force la réinitialisation du Hub (.env régénéré)."
    say "  --runner   Installe aussi le runner CI GitHub self-hosted (GH_PAT ou prompt)."
    say "  --help     Affiche cette aide."
}

install_parse_args() {
    FORCE=false
    RUNNER=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) FORCE=true; shift ;;
            --runner) RUNNER=true; shift ;;
            --no-runner) RUNNER=false; shift ;;  # compat : le runner est désormais en opt-in
            -h|--help)
                install_usage
                exit 0
                ;;
            *)
                err "Argument inconnu : $1 (utilisez --help)"
                ;;
        esac
    done
}

# ── Runner CI GitHub (self-hosted) ───────────────────────────────────────────
# Installe un runner GitHub Actions self-hosted en service systemd (User=REAL_USER),
# pour exécuter la CI du méta sans consommer de minutes Actions (org free).
# Sources du PAT (premier trouvé) : DB du hub (app_settings.github_token), variable
# d'environnement GH_PAT, prompt interactif. Idempotent ; en opt-in (--runner).

DRY_RUN="${DRY_RUN:-false}"
run_cmd() {
    if [ "$DRY_RUN" = true ]; then say "  [dry-run] $*"; else "$@"; fi
}

install_github_runner() {
    local repo_owner="$1" repo_name="$2" pat="$3" runner_user="$4"
    local dir="/opt/actions-runner"

    # Idempotence : déjà configuré et le service tourne → skip
    if [ -f "$dir/.credentials" ] && systemctl list-units --type=service 2>/dev/null | grep -q 'actions.runner.*.service'; then
        ok "Runner CI GitHub déjà installé (service actions.runner.* actif)"
        return 0
    fi

    if [ -z "$pat" ]; then
        warn "Aucun PAT GitHub disponible — runner CI non installé."
        warn "Relancez plus tard avec GH_PAT configuré, ou installez manuellement."
        return 0
    fi

    # Dernière version du runner
    local ver
    ver=$(curl -s -m 15 "https://api.github.com/repos/actions/runner/releases/latest" \
          | grep -oP '"tag_name":\s*"v\K[^"]*' || echo "2.337.0")
    ok "Runner CI GitHub : version ${ver}"

    # Téléchargement + extraction dans /opt/actions-runner
    if [ ! -f "$dir/config.sh" ]; then
        run_cmd mkdir -p "$dir"
        run_cmd curl -sL -o /tmp/actions-runner.tar.gz \
            "https://github.com/actions/runner/releases/download/v${ver}/actions-runner-linux-x64-${ver}.tar.gz"
        run_cmd tar xzf /tmp/actions-runner.tar.gz -C "$dir"
        run_cmd rm -f /tmp/actions-runner.tar.gz
    fi

    # Registration token (valable 1 h)
    local reg_token
    if [ "$DRY_RUN" = true ]; then
        reg_token="DRY_RUN_REGISTRATION_TOKEN"
        say "  [dry-run] POST /actions/runners/registration-token"
    else
    reg_token=$(curl -s -m 15 -X POST \
        -H "Authorization: Bearer ${pat}" \
        "https://api.github.com/repos/${repo_owner}/${repo_name}/actions/runners/registration-token" \
        | grep -oP '"token":\s*"\K[^"]*')
    fi
    if [ -z "$reg_token" ]; then
        warn "Registration token indisponible (PAT sans accès admin au repo ?) — runner non installé."
        return 0
    fi

    # Configuration (labels POULIDOR) — sous REAL_USER
    run_cmd chown -R "${runner_user}:${runner_user}" "$dir"
    run_cmd su - "${runner_user}" -c "cd $dir && ./config.sh --url https://github.com/${repo_owner}/${repo_name} --token ${reg_token} --labels POULIDOR --unattended --work _work"

    # Service systemd (User=REAL_USER)
    run_cmd bash -c "cd $dir && ./svc.sh install ${runner_user}"
    run_cmd bash -c "cd $dir && ./svc.sh start"

    if [ "$DRY_RUN" = true ]; then
        ok "(dry-run) service actions.runner.* serait installé et démarré (User=${runner_user})"
    elif systemctl list-units --type=service 2>/dev/null | grep -q 'actions.runner.*.service'; then
        ok "Runner CI GitHub installé et démarré (service actions.runner.*, User=${runner_user})"
    else
        warn "Runner installé mais service introuvable — vérifiez : cd $dir && ./svc.sh status"
    fi
}

resolve_hub_github_pat() {
    # 1) DB du hub (le hub stocke le PAT de liste des repos)
    local pat=""
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^hub-db$'; then
        pat=$(docker exec hub-db psql -U hubadmin -d hub_auth -t -A -c \
              "SELECT value::text FROM app_settings WHERE key='github_token';" 2>/dev/null | tr -d '[:space:]')
    fi
    # 2) Environnement
    [ -z "$pat" ] && pat="${GH_PAT:-}"
    # 3) Prompt interactif (uniquement sur demande explicite : --runner)
    if [ -z "$pat" ]; then
        say ""
        read -r -s -p "PAT GitHub (scopes repo+workflow, entrée pour ignorer le runner CI) : " pat
        say ""
    fi
    echo "$pat"
}

phase_runner_ci() {
    # Sans --runner : ni résolution d'origin, ni prompt, ni téléchargement.
    if ! $RUNNER; then
        ok "Runner CI non demandé (pour l'installer : sudo ./install.sh --runner)"
        return 0
    fi
    say ""
    say "${BOLD}${CYAN}   Runner CI GitHub (self-hosted)${NC}"
    local repo_url repo_path repo_owner repo_name pat
    repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    repo_path=$(echo "$repo_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
    repo_owner="${repo_path%%/*}"
    repo_name="${repo_path##*/}"
    if [ -z "$repo_owner" ] || [ "$repo_owner" = "$repo_path" ]; then
        warn "Repo origin introuvable — runner CI non installé."
    else
        pat=$(resolve_hub_github_pat)
        install_github_runner "$repo_owner" "$repo_name" "$pat" "$REAL_USER"
    fi
}

# ── Guidance de fin d'installation ───────────────────────────────────────────
# Uniquement ce qui existe et fonctionne à la date de livraison (constat VM
# 26/11/2026 : « ./hubctl → Apps → Ajouter une application » n'existe pas, et
# l'assistant IA n'est installé par rien). La CA du Hub est servie sans auth
# par l'API (GET /api/pki/ca.crt) : l'installer sur le poste évite l'avertissement
# de sécurité du navigateur. `hubctl app install` : hubctl ≥ 0.22.0.

print_next_steps() {
    say "${BOLD}Prochaines étapes :${NC}"
    say "  1. Ouvre https://${HOST_IP} dans un navigateur"
    say "  2. Connecte-toi et change le mot de passe admin"
    say "  3. Pour éviter l'avertissement de sécurité du navigateur, installe la CA du Hub"
    say "     sur ton poste : http://${HOST_IP}:${API_PORT}/api/pki/ca.crt"
    say "  4. Installe une application : ${BOLD}./hubctl app install <url-git-du-depot>${NC}"
    say ""
}

# ── Services hôtes (phase 3c de install.sh) ──────────────────────────────────
# Rend et installe l'unit systemd hubctl-<nom>.service (gabarit de
# hubctl_src/packaging/, placeholders @REAL_USER@/@PARC_ROOT@ substitués),
# puis l'active — ou la redémarre si le rendu change. Idempotent, jamais fatal.
#
# L'installeur pose ainsi les DEUX unités (atelier et update) : hubctl-update
# n'était installé par personne — `hubctl init`, lancé sans TTY par
# install.sh, ne faisait qu'afficher ses commandes « à lancer à la main », et
# le cockpit Admin du Hub restait sur « Relance automatique suspendue / état
# inconnu » (constat VM 26/11/2026).
install_host_service() {  # install_host_service <nom> : 0 si le service est posé et activé
    local nom="$1"
    local src="$ROOT_DIR/hubctl_src/packaging/hubctl-$nom.service"
    local dst="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}/hubctl-$nom.service"
    local tmp="" origin="$src"
    if [ ! -f "$src" ]; then
        warn "Gabarit d'unit introuvable ($src) — service $nom ignoré"
        return 1
    fi
    # Source autoritaire : l'unit rendue par `hubctl init` (phase 3b, juste
    # avant) — elle substitue AUSSI @DOCKER_GATEWAY@ (passerelle docker0), que
    # cet installeur ne sait pas calculer. À défaut, rendu minimal ci-dessous.
    local rendered="$ROOT_DIR/hubctl_src/packaging/.rendered/hubctl-$nom.service"
    if [ -s "$rendered" ]; then
        origin="$rendered"
    fi
    if ! tmp="$(mktemp)"; then
        warn "mktemp indisponible — service $nom ignoré (relancer ./install.sh)"
        return 1
    fi
    if ! sed -e "s|@REAL_USER@|$REAL_USER|g" \
             -e "s|@PARC_ROOT@|$ROOT_DIR|g" \
             "$origin" > "$tmp"; then
        rm -f "$tmp"
        warn "Rendu de l'unit impossible — service $nom ignoré (relancer ./install.sh)"
        return 1
    fi
    # Un placeholder non substitué (ex. @DOCKER_GATEWAY@ sans rendu hubctl)
    # donnerait une unit système cassée : on ne pose rien.
    if grep -qE '@[A-Z_]+@' "$tmp"; then
        rm -f "$tmp"
        warn "Rendu de l'unit $nom incomplet (placeholder non substitué) — lancez d'abord ./hubctl init, puis relancez ./install.sh"
        return 1
    fi
    if [ ! -f "$dst" ] || ! cmp -s "$tmp" "$dst"; then
        install -m 644 "$tmp" "$dst"
        systemctl daemon-reload
        if systemctl is-active --quiet "hubctl-$nom.service"; then
            systemctl restart "hubctl-$nom.service"
            ok "Service $nom mis à jour et redémarré"
        else
            systemctl enable --now "hubctl-$nom.service" >/dev/null 2>&1
            ok "Service $nom installé et activé"
        fi
    else
        systemctl enable --now "hubctl-$nom.service" >/dev/null 2>&1
        ok "Service $nom déjà à jour"
    fi
    rm -f "$tmp"
    return 0
}
