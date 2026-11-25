#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_check_author.sh — régression : la garde d'identité refuse un commit dont
# l'auteur ou le committer utilise une adresse non listée dans allowed-authors.txt.
#
# Open source — filet de sécurité : après la réécriture de l'historique, un
# commit signé d'une adresse personnelle ou de celle du client recréerait une
# fuite. La garde n'affiche que le DOMAINE de l'adresse refusée.
#
# Le script et sa liste d'autorisation sont copiés tels quels dans un dossier
# temporaire (la liste y est vidée pour un cas). Chaque appel se fait sous
# environnement vide, depuis un dépôt, avec un PATH réduit aux outils requis.
set -euo pipefail

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
BASH_BIN="$(command -v bash)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-check-author.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# ── Fixture ──────────────────────────────────────────────────────────────────
if [ ! -f "$HOOKS/check-author.sh" ] || [ ! -f "$HOOKS/allowed-authors.txt" ]; then
    fail "scripts/hooks/check-author.sh ou allowed-authors.txt absent"
fi
cp "$HOOKS/check-author.sh" "$HOOKS/allowed-authors.txt" "$TMP/"

BIN="$TMP/bin"          # PATH réduit : git (config) et grep (correspondance)
mkdir -p "$BIN"
for outil in git grep; do ln -s "$(command -v "$outil")" "$BIN/$outil"; done

git init -q -b main "$TMP/repo"

MAINTENEUR='117841560+Poutchouli@users.noreply.github.com'
AGENT='dev@poulidor.fr'
PERSONNELLE='jean.dupont@example.org'      # adresse factice, jamais autorisée

run() {  # run [VAR=valeur …] : la garde, depuis le dépôt ; renseigne RC et OUT
    set +e
    OUT="$(cd "$TMP/repo" && env -i PATH="$BIN" HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null "$@" \
          "$BASH_BIN" "$TMP/check-author.sh" 2>&1)"
    RC=$?
    set -e
}
config_email() { git -C "$TMP/repo" config user.email "$1"; }
doit_refuser() {  # doit_refuser <libellé> <domaine attendu>
    echo "$1 : rc=$RC"; echo "$OUT"
    [ "$RC" -eq 1 ] || fail "$1 : la garde rend $RC au lieu de 1"
    echo "$OUT" | grep -q "non autorisée" || fail "$1 : sortie sans « non autorisée »"
    echo "$OUT" | grep -q "scripts/hooks/allowed-authors.txt" || fail "$1 : sortie sans le chemin de la liste d'autorisation"
    echo "$OUT" | grep -qF -- "$2" || fail "$1 : le domaine « $2 » n'apparaît pas — sortie : $OUT"
}
doit_accepter() {  # doit_accepter <libellé>
    echo "$1 : rc=$RC"; echo "$OUT"
    [ "$RC" -eq 0 ] || fail "$1 : la garde rend $RC au lieu de 0 — sortie : $OUT"
}

# ── 1. identité autorisée (config git) → 0, en silence ───────────────────────
config_email "$MAINTENEUR"; run; doit_accepter "mainteneur"
[ -z "$OUT" ] || fail "identité autorisée : la garde devrait être silencieuse — sortie : $OUT"
config_email "$AGENT"; run; doit_accepter "agent"
pass "identités autorisées : commit autorisé, en silence"

# ── 2. identité personnelle → 1, domaine seul affiché ────────────────────────
config_email "$PERSONNELLE"; run; doit_refuser "personnelle" "example.org"
echo "$OUT" | grep -qF "jean.dupont" && fail "identité personnelle : la partie locale de l'adresse est affichée — sortie : $OUT"
pass "identité personnelle : commit refusé, seul le domaine est affiché"

# ── 3. GIT_AUTHOR_EMAIL prime sur la config (dans les deux sens) ─────────────
config_email "$PERSONNELLE"; run GIT_AUTHOR_EMAIL="$AGENT"; doit_accepter "GIT_AUTHOR_EMAIL autorisé, config refusée"
config_email "$MAINTENEUR"; run GIT_AUTHOR_EMAIL="$PERSONNELLE"; doit_refuser "GIT_AUTHOR_EMAIL refusé, config autorisée" "example.org"
pass "GIT_AUTHOR_EMAIL prime sur la config git"

# ── 4. le committer est contrôlé comme l'auteur ──────────────────────────────
run GIT_COMMITTER_EMAIL="$PERSONNELLE"; doit_refuser "committer refusé" "example.org"
run GIT_COMMITTER_EMAIL="$AGENT"; doit_accepter "committer autorisé"
run GIT_COMMITTER_EMAIL="$MAINTENEUR" GIT_AUTHOR_EMAIL="$AGENT"; doit_accepter "auteur et committer autorisés"
pass "le committer est contrôlé comme l'auteur"

# ── 5. insensible à la casse ; expressions ancrées ───────────────────────────
run GIT_AUTHOR_EMAIL="DEV@POULIDOR.FR"; doit_accepter "casse différente"
run GIT_AUTHOR_EMAIL="117841560+POUTCHOULI@USERS.NOREPLY.GITHUB.COM"; doit_accepter "casse différente (mainteneur)"
# Les expressions sont ancrées : une adresse qui prolonge ou devance une adresse
# autorisée reste refusée — pour chacune des deux expressions de la liste,
# et pour chacune de ses deux bornes.
voisines=(
    'dev@poulidor.fr.autre.example.org|example.org'
    'prefixe-dev@poulidor.fr|poulidor.fr'
    '117841560+Poutchouli@users.noreply.github.com.autre.example.org|example.org'
    'x117841560+Poutchouli@users.noreply.github.com|users.noreply.github.com'
)
for voisine in "${voisines[@]}"; do
    run GIT_AUTHOR_EMAIL="${voisine%%|*}"; doit_refuser "adresse voisine d'une adresse autorisée" "${voisine##*|}"
done
pass "correspondance insensible à la casse, et ancrée (deux bornes, deux expressions)"

# ── 6. OSS_AUTHOR_SKIP=1 : avertissement et commit autorisé ──────────────────
config_email "$PERSONNELLE"          # refusée sans le contournement
run
[ "$RC" -eq 1 ] || fail "identité personnelle sans OSS_AUTHOR_SKIP : la garde rend $RC au lieu de 1"
run OSS_AUTHOR_SKIP=1
echo "OSS_AUTHOR_SKIP=1 : rc=$RC"; echo "$OUT"
[ "$RC" -eq 0 ] || fail "OSS_AUTHOR_SKIP=1 : la garde rend $RC au lieu de 0"
echo "$OUT" | grep -q "⚠" || fail "OSS_AUTHOR_SKIP=1 : contournement silencieux (aucun avertissement)"
pass "OSS_AUTHOR_SKIP=1 : commit autorisé, avertissement affiché"

# ── 7. seule la valeur 1 contourne ───────────────────────────────────────────
run OSS_AUTHOR_SKIP=0;     [ "$RC" -eq 1 ] || fail "OSS_AUTHOR_SKIP=0 : la garde rend $RC au lieu de 1"
run OSS_AUTHOR_SKIP=oui;   [ "$RC" -eq 1 ] || fail "OSS_AUTHOR_SKIP=oui : la garde rend $RC au lieu de 1"
run OSS_AUTHOR_SKIP=;      [ "$RC" -eq 1 ] || fail "OSS_AUTHOR_SKIP vide : la garde rend $RC au lieu de 1"
pass "seule la valeur 1 de OSS_AUTHOR_SKIP contourne la garde"

# ── 8. liste d'autorisation vide, réduite à des commentaires, ou absente → 1 ─
config_email "$MAINTENEUR"            # identité qui serait autorisée
: > "$TMP/allowed-authors.txt"; run; doit_refuser "liste vide" "github.com"
printf '# uniquement un commentaire\n\n   \n# et un autre\n' > "$TMP/allowed-authors.txt"; run; doit_refuser "liste sans expression" "github.com"
rm "$TMP/allowed-authors.txt"; run; doit_refuser "liste absente" "github.com"
pass "liste d'autorisation vide, sans expression ou absente : commit refusé"

# ── 9. commentaires et lignes vides de la vraie liste sont ignorés ───────────
cp "$HOOKS/allowed-authors.txt" "$TMP/"
config_email "$PERSONNELLE"; run; doit_refuser "vraie liste, identité personnelle" "example.org"
pass "vraie liste : les commentaires et lignes vides n'autorisent rien"

# ── 10. aucune identité configurée → refus net ───────────────────────────────
git -C "$TMP/repo" config --unset user.email
run
echo "sans identité : rc=$RC"; echo "$OUT"
[ "$RC" -eq 1 ] || fail "sans identité configurée : la garde rend $RC au lieu de 1"
echo "$OUT" | grep -q "non autorisée" || fail "sans identité configurée : sortie sans « non autorisée » — sortie : $OUT"
pass "aucune identité configurée : commit refusé, sans erreur de script"

# ── 11. une liste permissive n'autorise pas un commit sans identité ─────────
printf '# liste de fixture, qui accepte la chaîne vide\n^$\n.*\n' > "$TMP/allowed-authors.txt"
run; doit_refuser "sans identité, liste permissive" "aucune adresse"
pass "liste permissive : un commit sans identité reste refusé"

echo ""
echo "🎉 Tous les tests passent."
