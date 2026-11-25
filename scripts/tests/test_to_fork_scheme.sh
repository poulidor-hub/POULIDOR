#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_to_fork_scheme.sh — régression : fork-remotes.sh conserve le schéma du
# fork pour les sous-modules (to_fork_scheme, scripts/lib/url-scheme.sh).
#
# Open source : les sous-modules du méta sont en HTTPS absolu, pour qu'un clone
# anonyme les initialise. Un fork de déploiement accédé par clé SSH
# (git@github.com:<org>/<dépôt>.git) doit pourtant garder des sous-modules en
# SSH : un fork privé en HTTPS exigerait des identifiants. Inversement, une URL
# d'un autre hôte que le fork, déjà en SSH, ou un fork donné en HTTPS, reste
# telle quelle.
#
# 1. la fonction, seule, dans un bash neuf ;
# 2. scripts/fork-remotes.sh en --dry-run, sur un méta factice sans sous-module
#    initialisé : la surcharge annoncée pour chacun des sous-modules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/scripts/lib/url-scheme.sh"
FORK="$ROOT/scripts/fork-remotes.sh"
BASH_BIN="$(command -v bash)"

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-fork-scheme.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[ -f "$LIB" ] || fail "scripts/lib/url-scheme.sh absent"
[ -f "$FORK" ] || fail "scripts/fork-remotes.sh absent"
[ -f "$ROOT/.gitmodules" ] || fail ".gitmodules absent à la racine du méta"

# ── 1. to_fork_scheme <fork_url> <url> ────────────────────────────────────────
attend() {  # attend <libellé> <fork_url> <url> <résultat attendu>
    local libelle="$1" fork="$2" url="$3" resultat="$4" out rc
    set +e
    out="$(env -i "$BASH_BIN" -c 'source "$1"; to_fork_scheme "$2" "$3"' _ "$LIB" "$fork" "$url" 2>&1)"
    rc=$?
    set -e
    [ "$rc" -eq 0 ] || fail "$libelle : to_fork_scheme rend $rc — sortie : $out"
    [ "$out" = "$resultat" ] || fail "$libelle : « $out » au lieu de « $resultat »"
    echo "  $libelle : $url → $out"
}

echo "── 1. to_fork_scheme"

# fork en SSH : l'URL HTTPS du même hôte passe en SSH
attend "fork git@, URL https" \
    "git@github.com:o/r.git" "https://github.com/o/r.git" "git@github.com:o/r.git"
attend "fork git@, URL https d'un autre dépôt du même hôte" \
    "git@github.com:exemple-org/POULIDOR.git" "https://github.com/exemple-org/HUB_base.git" \
    "git@github.com:exemple-org/HUB_base.git"
pass "fork en SSH (git@hôte:chemin) : l'URL HTTPS du même hôte passe en SSH"

# fork en HTTPS : URL inchangée
attend "fork https" \
    "https://github.com/o/r.git" "https://github.com/o/r.git" "https://github.com/o/r.git"
pass "fork en HTTPS : URL inchangée"

# URL déjà en SSH : inchangée
attend "URL déjà en git@" \
    "git@github.com:o/r.git" "git@github.com:o/r.git" "git@github.com:o/r.git"
attend "URL déjà en ssh://" \
    "git@github.com:o/r.git" "ssh://git@github.com/o/r.git" "ssh://git@github.com/o/r.git"
pass "URL déjà en SSH : inchangée"

# URL hors de l'hôte du fork : inchangée
attend "autre hôte" \
    "git@github.com:o/r.git" "https://git.example.org/o/r.git" "https://git.example.org/o/r.git"
attend "chemin local" \
    "git@github.com:o/r.git" "/srv/miroirs/o/r.git" "/srv/miroirs/o/r.git"
pass "URL hors de l'hôte du fork : inchangée"

# fork en SSH, forme ssh:// : même règle
attend "fork ssh://" \
    "ssh://git@github.com/o/r.git" "https://github.com/o/r.git" "ssh://git@github.com/o/r.git"
pass "fork en SSH (ssh://git@hôte/chemin) : l'URL HTTPS du même hôte passe en SSH"

# ── 2. fork-remotes.sh --dry-run ──────────────────────────────────────────────
# Un méta factice : branche main, arbre propre, .gitmodules du méta, origin
# officielle, aucun sous-module initialisé (la surcharge est alors annoncée sans
# interroger le réseau).
FIXTURE="$TMP/meta"
git init -q -b main "$FIXTURE"
cp "$ROOT/.gitmodules" "$FIXTURE/.gitmodules"
git -C "$FIXTURE" add .gitmodules
git -C "$FIXTURE" -c user.name=t -c user.email=t@example.invalid commit -qm "méta factice"
git -C "$FIXTURE" remote add origin https://github.com/POULIDOR-Audit-Developpement/POULIDOR.git

surcharges() {  # surcharges <fork_url> : sortie de fork-remotes.sh --dry-run ; renseigne RC et OUT
    set +e
    OUT="$(cd "$FIXTURE" && HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
           "$BASH_BIN" "$FORK" --fork-url "$1" --dry-run 2>&1)"
    RC=$?
    set -e
}

attendues() {  # attendues <schéma> : pour chaque sous-module, la surcharge annoncée est celle attendue
    local prefixe="$1" nom officielle attendue n=0
    while IFS= read -r nom; do
        officielle="$(git -C "$FIXTURE" config --file .gitmodules "submodule.${nom}.url")"
        attendue="${prefixe}exemple-org/${officielle##*/}"
        echo "$OUT" | grep -qF -- "git config submodule.${nom}.url $attendue" \
            || fail "fork ${prefixe}git@ : surcharge de « $nom » différente de « $attendue » — sortie : $OUT"
        n=$((n + 1))
    done < <(git -C "$FIXTURE" config --file .gitmodules --get-regexp '^submodule\.[^.]+\.path$' \
               | while read -r cle _; do nom="${cle#submodule.}"; echo "${nom%.path}"; done)
    [ "$n" -eq 6 ] || fail "6 sous-modules attendus dans .gitmodules, lus : $n"
}

echo ""
echo "── 2. fork-remotes.sh --dry-run"

surcharges "git@github.com:exemple-org/POULIDOR.git"
[ "$RC" -eq 0 ] || fail "fork-remotes.sh --dry-run (fork en SSH) rend $RC — sortie : $OUT"
echo "$OUT" | grep -qF '(org « exemple-org »)' \
    || fail "l'org du fork est mal dérivée d'une URL en git@ — sortie : $OUT"
echo "$OUT" | grep -qF '[dry-run] méta origin → fork : git -C . remote set-url origin git@github.com:exemple-org/POULIDOR.git' \
    || fail "le méta ne bascule pas vers le fork en SSH — sortie : $OUT"
attendues "git@github.com:"
echo "$OUT" | grep -qE 'submodule\.[^.]+\.url https://github\.com/exemple-org/' \
    && fail "un sous-module reste en HTTPS alors que le fork est en SSH — sortie : $OUT"
pass "fork en SSH : les 6 sous-modules prennent l'URL du fork en SSH"

surcharges "https://github.com/exemple-org/POULIDOR.git"
[ "$RC" -eq 0 ] || fail "fork-remotes.sh --dry-run (fork en HTTPS) rend $RC — sortie : $OUT"
attendues "https://github.com/"
echo "$OUT" | grep -qE 'submodule\.[^.]+\.url git@' \
    && fail "un sous-module passe en SSH alors que le fork est en HTTPS — sortie : $OUT"
pass "fork en HTTPS : les 6 sous-modules prennent l'URL du fork en HTTPS"

[ -z "$(git -C "$FIXTURE" status --porcelain)" ] || fail "--dry-run a modifié le méta factice"
[ -z "$(git -C "$FIXTURE" config --get-regexp '^submodule\.')" ] || fail "--dry-run a posé une surcharge dans .git/config"
pass "--dry-run ne modifie rien"

echo ""
echo "🎉 Tous les tests passent."
