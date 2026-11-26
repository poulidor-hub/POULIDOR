#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_install_sh.sh — régression install.sh : runner CI en opt-in, guidance
# de fin d'installation vraie.
#
# Plan « installation sans friction » (phase 1, 26/11/2026). Constats VM :
#   - sans --no-runner, l'install cherchait un PAT GitHub (prompt interactif)
#     pour un runner dont un utilisateur du parc public n'a que faire ;
#   - « Prochaines étapes » annonçait « ./hubctl → Apps → Ajouter une
#     application » (menu inexistant) et un assistant IA que rien n'installe.
#
# install.sh est un script sudo linéaire : ses morceaux à tester vivent dans
# scripts/lib/install-lib.sh (sourcé par le script et par ce test).
# shellcheck disable=SC1090
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/scripts/lib/install-lib.sh"

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

[ -f "$LIB" ] || fail "$LIB absent — install.sh doit sourcer sa lib de fonctions testables"

TMP="$(mktemp -d /tmp/install-sh-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. Parsing : le runner CI est en opt-in ─────────────────────────────────
( source "$LIB"; install_parse_args;        [ "$RUNNER" = false ] ) || fail "défaut : RUNNER doit être false"
( source "$LIB"; install_parse_args --runner; [ "$RUNNER" = true ]  ) || fail "--runner → RUNNER=true"
( source "$LIB"; install_parse_args --no-runner; [ "$RUNNER" = false ] ) || fail "--no-runner (compat) → RUNNER=false"
( source "$LIB"; install_parse_args --force; [ "$FORCE" = true ] && [ "$RUNNER" = false ] ) || fail "--force n'installe pas le runner"
usage="$(source "$LIB"; install_parse_args --help)"
grep -q -- "--runner" <<<"$usage" || fail "l'aide doit documenter --runner"
if ( source "$LIB"; install_parse_args --bogus ) >/dev/null 2>&1; then
    fail "argument inconnu → doit sortir en erreur"
fi
pass "parsing : runner en opt-in, --no-runner accepté, --help à jour"

# ── 2. Sans --runner : aucune résolution d'origin, aucun prompt ────────────
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "git appelé" >> "$GIT_MARKER"
exit 99
EOF
chmod +x "$TMP/bin/git"
out="$(GIT_MARKER="$TMP/marker" PATH="$TMP/bin:$PATH" \
       bash -c "source '$LIB'; REAL_USER=test; RUNNER=false; phase_runner_ci" </dev/null)"
grep -q "non demandé" <<<"$out" || fail "sans --runner : message « non demandé » attendu — obtenu : $out"
[ ! -e "$TMP/marker" ] || fail "sans --runner : git ne doit pas être appelé (aucune résolution d'origin)"
pass "sans --runner : rien n'est tenté, un seul message"

# ── 3. Avec --runner : origin résolu, installation tentée avec les bons args ─
out="$(bash -c "
    source '$LIB'
    REAL_USER=test; RUNNER=true
    git() { echo 'git@github.com:acme/mon-parc.git'; }
    resolve_hub_github_pat() { echo pat-test; }
    install_github_runner() { echo \"runner:\$1:\$2:\$3:\$4\" >> '$TMP/calls'; }
    phase_runner_ci" </dev/null)"
grep -q "runner:acme:mon-parc:pat-test:test" "$TMP/calls" 2>/dev/null \
    || fail "--runner : install_github_runner doit être appelé avec owner/name/pat/user — obtenu : $(cat "$TMP/calls" 2>/dev/null)"
pass "--runner : résolution d'origin + installation avec owner/name/pat/user"

# ── 4. Avec --runner mais origin introuvable : avertissement, rien d'installé ─
out="$(bash -c "
    source '$LIB'
    REAL_USER=test; RUNNER=true
    git() { return 1; }
    install_github_runner() { touch '$TMP/called'; }
    phase_runner_ci" </dev/null)"
[ ! -e "$TMP/called" ] || fail "origin introuvable → aucune installation"
grep -q "origin introuvable" <<<"$out" || fail "origin introuvable → avertissement attendu — obtenu : $out"
pass "--runner sans origin : avertissement, rien d'installé"

# ── 5. Guidance de fin : vraie à la date de livraison ──────────────────────
out="$(bash -c "source '$LIB'; HOST_IP=192.0.2.10; API_PORT=8000; print_next_steps")"
grep -q "https://192.0.2.10" <<<"$out"         || fail "guidance : URL du Hub attendue"
grep -q "mot de passe admin" <<<"$out"         || fail "guidance : changement du mot de passe admin attendu"
grep -q "192.0.2.10:8000/api/pki/ca.crt" <<<"$out" || fail "guidance : URL de téléchargement de la CA attendue — obtenu : $out"
grep -q "Ajouter une application" <<<"$out"    && fail "guidance : ne doit plus annoncer un menu hubctl inexistant"
grep -q "demande à l'IA" <<<"$out"             && fail "guidance : ne doit plus annoncer l'assistant IA (rien ne l'installe)"
pass "guidance : URL, mot de passe, CA — ni menu inexistant ni assistant IA"

echo ""
echo "✅ test_install_sh.sh : 5 cas OK"
