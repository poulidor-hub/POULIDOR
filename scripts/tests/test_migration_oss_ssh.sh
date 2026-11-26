#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_migration_oss_ssh.sh — régression : scripts/migration-oss.sh préserve
# l'authentification SSH des sous-modules.
#
# Open source : le .gitmodules du méta est en HTTPS (clone anonyme). Un
# déploiement par clé de déploiement (origin en git@github.com:…) n'a pas
# d'identifiants HTTPS : la migration surcharge en SSH, dans le .git/config du
# clone neuf, l'URL de chaque sous-module (submodule.<nom>.url, comme
# scripts/fork-remotes.sh) — le .gitmodules reste tel quel. Quand l'URL utilisée
# est en HTTPS, rien n'est surchargé.
#
# Une règle url.<base>.insteadOf posée dans le .git/config du superprojet ne
# convient pas : le clone d'un sous-module est un `git clone` à part, qui ne lit
# que les configurations système, globale et d'environnement (constaté avec git
# 2.43.0) — la règle serait posée sans effet.
#
# Banc, sans réseau : des dépôts locaux nus jouent le méta réécrit et deux de
# ses sous-modules. Des règles insteadOf passées par GIT_CONFIG_COUNT /
# GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n y redirigent les URL :
#   - profil « clé de déploiement » : seules les URL en git@github.com:… aboutissent ;
#     tout HTTPS vers github.com est coupé (proxy vers un port fermé) ;
#   - profil « dépôts publics » : les URL HTTPS aboutissent aussi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/migration-oss.sh"
ORG="POULIDOR-Audit-Developpement"
BASH_BIN="$(command -v bash)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-migration-oss.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

[ -f "$SCRIPT" ] || fail "scripts/migration-oss.sh absent"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
GIT=(git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false)
SOUS_MODULES=(HUB_base HUBsocle)

# ── Banc ──────────────────────────────────────────────────────────────────────
# Deux sous-modules (un commit chacun) et le méta réécrit : gitlinks + .gitmodules
# en HTTPS, comme le dépôt officiel.
mkdir -p "$TMP/src" "$TMP/apres"
for sm in "${SOUS_MODULES[@]}"; do
    "${GIT[@]}" init -q -b main "$TMP/src/$sm"
    echo "contenu de $sm" > "$TMP/src/$sm/fichier"
    "${GIT[@]}" -C "$TMP/src/$sm" add fichier
    "${GIT[@]}" -C "$TMP/src/$sm" commit -qm "$sm"
    "${GIT[@]}" clone -q --bare "$TMP/src/$sm" "$TMP/apres/$sm.git"
done
"${GIT[@]}" init -q -b main "$TMP/src/meta"
: > "$TMP/src/meta/.gitmodules"
for sm in "${SOUS_MODULES[@]}"; do
    printf '[submodule "%s"]\n\tpath = %s\n\turl = https://github.com/%s/%s.git\n' "$sm" "$sm" "$ORG" "$sm" >> "$TMP/src/meta/.gitmodules"
    "${GIT[@]}" -C "$TMP/src/meta" update-index --add --cacheinfo "160000,$("${GIT[@]}" -C "$TMP/src/$sm" rev-parse HEAD),$sm"
done
"${GIT[@]}" -C "$TMP/src/meta" add .gitmodules
"${GIT[@]}" -C "$TMP/src/meta" commit -qm "méta réécrit"
"${GIT[@]}" clone -q --bare "$TMP/src/meta" "$TMP/apres/POULIDOR.git"
grep -q "git@" "$TMP/src/meta/.gitmodules" && fail "banc : le .gitmodules du méta réécrit devrait être en HTTPS seul"

# Un déploiement ancien : clone d'un méta d'avant, .env et APPS/ locaux.
mkdir -p "$TMP/avant"
echo "ancien arbre" > "$TMP/avant/README.md"
"${GIT[@]}" -C "$TMP/avant" init -q -b main .
for sm in "${SOUS_MODULES[@]}"; do
    printf '[submodule "%s"]\n\tpath = %s\n\turl = https://github.com/%s/%s.git\n' "$sm" "$sm" "$ORG" "$sm" >> "$TMP/avant/.gitmodules"
    "${GIT[@]}" -C "$TMP/avant" update-index --add --cacheinfo "160000,$("${GIT[@]}" -C "$TMP/src/$sm" rev-parse HEAD),$sm"
done
"${GIT[@]}" -C "$TMP/avant" add .gitmodules
"${GIT[@]}" -C "$TMP/avant" commit -qm "ancien méta, avec sous-modules"

deployment() {  # deployment <chemin> <URL d'origin> : un déploiement ancien,
    # avec ses sous-modules initialisés (le cas général chez un client : les apps tournent)
    local n=0
    for sm in "${SOUS_MODULES[@]}"; do
        export GIT_CONFIG_KEY_$n="url.$TMP/apres/$sm.git.insteadOf"
        export GIT_CONFIG_VALUE_$n="https://github.com/$ORG/$sm.git"
        n=$((n + 1))
    done
    export GIT_CONFIG_COUNT=$n
    "${GIT[@]}" clone -q "$TMP/avant" "$1"
    "${GIT[@]}" -C "$1" remote set-url origin "$2"
    "${GIT[@]}" -C "$1" submodule update --init --quiet
    # état client authentique : la config locale garde l'URL d'origine (github),
    # pas l'URL résolue du banc
    for sm in "${SOUS_MODULES[@]}"; do
        "${GIT[@]}" -C "$1" config "submodule.$sm.url" "https://github.com/$ORG/$sm.git"
    done
    echo "cle=valeur" > "$1/.env"
    mkdir -p "$1/APPS/mon-app"
    echo "donnee" > "$1/APPS/mon-app/donnee.txt"
}

# Les règles du banc, cumulées pour l'environnement de la migration.
BANC=()          # paires GIT_CONFIG_KEY_n=<clé> / GIT_CONFIG_VALUE_n=<valeur>, pour `env`
banc() {         # banc <clé> <valeur>
    local n=$(( ${#BANC[@]} / 2 ))
    BANC+=("GIT_CONFIG_KEY_$n=$1" "GIT_CONFIG_VALUE_$n=$2")
}

migrer() {  # migrer <déploiement> <clé|public> [options…] : la migration ; renseigne RC et OUT
    local dep="$1" profil="$2" sm; shift 2
    BANC=()
    banc "url.$TMP/apres/POULIDOR.git.insteadOf" "git@github.com:$ORG/POULIDOR.git"
    for sm in "${SOUS_MODULES[@]}"; do
        banc "url.$TMP/apres/$sm.git.insteadOf" "git@github.com:$ORG/$sm.git"
    done
    if [ "$profil" = public ]; then
        banc "url.$TMP/apres/POULIDOR.git.insteadOf" "https://github.com/$ORG/POULIDOR.git"
        for sm in "${SOUS_MODULES[@]}"; do
            banc "url.$TMP/apres/$sm.git.insteadOf" "https://github.com/$ORG/$sm.git"
        done
    fi
    banc "http.proxy" "http://127.0.0.1:9"       # aucun HTTPS vers github.com
    banc "protocol.file.allow" "always"
    set +e
    OUT="$(cd "$dep" && env -i PATH="$PATH" HOME="$TMP" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        GIT_CONFIG_COUNT="$(( ${#BANC[@]} / 2 ))" "${BANC[@]}" \
        "$BASH_BIN" "$SCRIPT" "$@" --yes 2>&1)"
    RC=$?
    set -e
}

attendue() {  # attendue <déploiement> <libellé> : la migration a réussi, sans perte
    local dep="$1" libelle="$2" st
    echo "$OUT" | tail -2
    [ "$RC" -eq 0 ] || fail "$libelle : migration-oss.sh rend $RC — sortie : $OUT"
    st="$("${GIT[@]}" -C "$dep" submodule status)"
    [ "$(echo "$st" | wc -l)" -eq "${#SOUS_MODULES[@]}" ] || fail "$libelle : ${#SOUS_MODULES[@]} sous-modules attendus — sortie : $st"
    if echo "$st" | grep -qE '^[-+]'; then fail "$libelle : un sous-module est non initialisé ou décalé — sortie : $st"; fi
    [ "$(cat "$dep/HUB_base/fichier" "$dep/HUBsocle/fichier")" = "contenu de HUB_base
contenu de HUBsocle" ] || fail "$libelle : sous-modules sans leur contenu"
    [ "$(cat "$dep/.env")" = "cle=valeur" ] || fail "$libelle : .env non préservé"
    [ "$(cat "$dep/APPS/mon-app/donnee.txt")" = "donnee" ] || fail "$libelle : APPS/ non préservé"
    grep -q "url = https://github.com/$ORG/HUB_base.git" "$dep/.gitmodules" \
        || fail "$libelle : le déploiement n'est pas sur l'arbre réécrit"
    ls -d "$dep"/.git.pre-oss-* >/dev/null 2>&1 || fail "$libelle : l'ancien .git n'est pas conservé"
}

# ── 1. origin en SSH, sans accès HTTPS : surcharge en SSH, sous-modules initialisés ──
echo "── 1. origin en SSH (clé de déploiement, aucun accès HTTPS)"
deployment "$TMP/ssh" "git@github.com:$ORG/POULIDOR.git"
migrer "$TMP/ssh" cle
attendue "$TMP/ssh" "origin en SSH"
[ "$("${GIT[@]}" -C "$TMP/ssh" config --get submodule.HUB_base.url)" = "git@github.com:$ORG/HUB_base.git" ] \
    || fail "origin en SSH : l'URL de HUB_base n'est pas surchargée en SSH (« $("${GIT[@]}" -C "$TMP/ssh" config --get submodule.HUB_base.url) »)"
[ "$("${GIT[@]}" -C "$TMP/ssh/HUB_base" remote get-url origin)" = "git@github.com:$ORG/HUB_base.git" ] \
    || fail "origin en SSH : le sous-module cloné ne tire pas en SSH (« $("${GIT[@]}" -C "$TMP/ssh/HUB_base" remote get-url origin) »)"
pass "origin en SSH : URL surchargées, sous-modules clonés par la clé, données préservées"

# ── 2. origin en HTTPS (dépôts publics) : rien n'est surchargé ────────────────
echo ""
echo "── 2. origin en HTTPS (dépôts publics)"
deployment "$TMP/https" "https://github.com/$ORG/POULIDOR.git"
migrer "$TMP/https" public
attendue "$TMP/https" "origin en HTTPS"
[ "$("${GIT[@]}" -C "$TMP/https" config --get submodule.HUB_base.url)" = "https://github.com/$ORG/HUB_base.git" ] \
    || fail "origin en HTTPS : l'URL de HUB_base a été surchargée (« $("${GIT[@]}" -C "$TMP/https" config --get submodule.HUB_base.url) »)"
# En banc, l'insteadOf fait enregistrer l'URL résolue (miroir local) comme origin ;
# chez un client réel ce sera l'URL publique. Ce qui compte : aucune surcharge en SSH.
case "$("${GIT[@]}" -C "$TMP/https/HUB_base" remote get-url origin)" in
    git@*) fail "origin en HTTPS : le sous-module cloné a été surchargé en SSH (« $("${GIT[@]}" -C "$TMP/https/HUB_base" remote get-url origin) »)" ;;
esac
pass "origin en HTTPS : aucune surcharge, sous-modules clonés en HTTPS, données préservées"

# ── 3. --url en SSH sur une origin en HTTPS : l'URL utilisée commande ─────────
echo ""
echo "── 3. --url en SSH (override d'une origin en HTTPS)"
deployment "$TMP/override" "https://github.com/$ORG/POULIDOR.git"
migrer "$TMP/override" cle --url "git@github.com:$ORG/POULIDOR.git"
attendue "$TMP/override" "--url en SSH"
[ "$("${GIT[@]}" -C "$TMP/override/HUB_base" remote get-url origin)" = "git@github.com:$ORG/HUB_base.git" ] \
    || fail "--url en SSH : le sous-module cloné ne tire pas en SSH (« $("${GIT[@]}" -C "$TMP/override/HUB_base" remote get-url origin) »)"
pass "--url en SSH : surcharge posée (c'est l'URL utilisée qui commande)"

echo ""
echo "🎉 Tous les tests passent."
