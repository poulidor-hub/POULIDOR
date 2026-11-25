#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_pre_commit_gitleaks.sh — régression : le hook pre-commit gitleaks doit
# REFUSER le commit quand gitleaks est absent du PATH.
#
# Filet de sécurité open source : un hook qui laisse passer en silence n'est
# pas un filet. Avant : « ⚠ gitleaks absent » puis exit 0 — commit autorisé
# sans scan. Après : exit 1 + « gitleaks absent : commit refusé », sauf
# contournement explicite GITLEAKS_SKIP=1. Les deux autres branches sont
# épinglées pour ne pas régresser : secret détecté (rc=1) → refus ; gitleaks
# en échec (rc autre) → avertissement, commit autorisé.
#
# Le hook est appelé avec un PATH réduit — un répertoire ne contenant que git
# et, selon le cas, un faux exécutable gitleaks : l'absence de gitleaks est
# prouvée, pas supposée (indépendant de l'état du poste).
#
# Un dernier cas utilise le VRAI gitleaks quand il est installé : un faux
# exécutable accepte toutes les options, et une option inconnue du vrai binaire
# vaut un code retour 1 — lu « secret détecté » par le hook, qui refusait alors
# tout commit. La règle de détection est fournie par GITLEAKS_CONFIG : le
# résultat ne dépend ni des règles par défaut ni de leur version.
set -euo pipefail

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../hooks" && pwd)/pre-commit-gitleaks.sh"
BASH_BIN="$(command -v bash)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-pre-commit-gitleaks.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# ── Fixture ──────────────────────────────────────────────────────────────────
# PATH réduit : git seul. Les faux gitleaks vivent chacun dans leur répertoire.
BIN="$TMP/bin"
mkdir -p "$BIN"
ln -s "$(command -v git)" "$BIN/git"

faux_gitleaks() {  # faux_gitleaks <répertoire> <code de sortie> — enregistre ses arguments
    mkdir -p "$1"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\nexit %s\n' "$1" "$2" > "$1/gitleaks"
    chmod +x "$1/gitleaks"
}
faux_gitleaks "$TMP/g1" 1
faux_gitleaks "$TMP/g2" 2

# Un dépôt minimal avec un fichier stagé (contexte normal du hook).
nouveau_depot() {
    git init -q -b main "$1"
    git -C "$1" config user.email test@example.org
    git -C "$1" config user.name test
    echo a > "$1/fichier"
    git -C "$1" add fichier
}
nouveau_depot "$TMP/repo"

# Lance le hook depuis <dépôt>, environnement vide, avec le PATH donné ;
# renseigne RC et OUT (sortie combinée).
run() {  # run <dépôt> <PATH> [VAR=valeur …]
    local dir="$1" path="$2"; shift 2
    set +e
    OUT="$(cd "$dir" && env -i PATH="$path" HOME="$TMP" "$@" "$BASH_BIN" "$SCRIPT_UNDER_TEST" 2>&1)"
    RC=$?
    set -e
}

# ── 1. gitleaks absent → commit refusé ───────────────────────────────────────
run "$TMP/repo" "$BIN"
echo "absent : rc=$RC"; echo "$OUT"
[ "$RC" -eq 1 ] || fail "gitleaks absent : le hook rend $RC au lieu de 1 (commit autorisé sans scan)"
echo "$OUT" | grep -q "gitleaks absent" || fail "gitleaks absent : sortie sans « gitleaks absent »"
echo "$OUT" | grep -q "commit refusé" || fail "gitleaks absent : sortie sans « commit refusé »"
echo "$OUT" | grep -q "https://github.com/gitleaks/gitleaks" \
    || fail "gitleaks absent : sortie sans l'adresse d'installation"
echo "$OUT" | grep -q "GITLEAKS_SKIP=1" \
    || fail "gitleaks absent : sortie sans le contournement explicite GITLEAKS_SKIP=1"
pass "gitleaks absent : commit refusé, message complet"

# ── 2. gitleaks absent + GITLEAKS_SKIP=1 → commit autorisé, avec avertissement ─
run "$TMP/repo" "$BIN" GITLEAKS_SKIP=1
echo "absent + GITLEAKS_SKIP=1 : rc=$RC"; echo "$OUT"
[ "$RC" -eq 0 ] || fail "absent + GITLEAKS_SKIP=1 : le hook rend $RC au lieu de 0"
echo "$OUT" | grep -q "⚠" || fail "absent + GITLEAKS_SKIP=1 : contournement silencieux (aucun avertissement)"
pass "gitleaks absent + GITLEAKS_SKIP=1 : commit autorisé, avertissement affiché"

# ── 3. GITLEAKS_SKIP=1 ne coupe pas le scan quand gitleaks est là ────────────
run "$TMP/repo" "$BIN:$TMP/g1" GITLEAKS_SKIP=1
echo "rc=1 + GITLEAKS_SKIP=1 : rc=$RC"; echo "$OUT"
if [ "$RC" -ne 1 ] || ! echo "$OUT" | grep -q "secret détecté"; then
    fail "GITLEAKS_SKIP=1 avec gitleaks présent : le scan doit quand même refuser (rc=$RC)"
fi
pass "GITLEAKS_SKIP=1 ne contourne que l'absence de gitleaks"

# ── 4. faux gitleaks rc=1 → secret détecté, commit refusé ────────────────────
run "$TMP/repo" "$BIN:$TMP/g1"
echo "rc=1 : rc=$RC"; echo "$OUT"
[ "$RC" -eq 1 ] || fail "gitleaks rc=1 : le hook rend $RC au lieu de 1"
echo "$OUT" | grep -q "secret détecté" || fail "gitleaks rc=1 : sortie sans « secret détecté »"
# Le hook scanne le STAGED par le mode git : ni plus (tout l'historique), ni moins.
[ "$(head -n 3 "$TMP/g1/args" | tr '\n' ' ')" = "git --pre-commit --staged " ] \
    || fail "gitleaks est appelé avec : $(tr '\n' ' ' < "$TMP/g1/args") — attendu : git --pre-commit --staged …"
pass "gitleaks rc=1 : commit refusé, appelé sur le staged"

# ── 5. faux gitleaks rc=2 → avertissement, commit autorisé ───────────────────
run "$TMP/repo" "$BIN:$TMP/g2"
echo "rc=2 : rc=$RC"; echo "$OUT"
[ "$RC" -eq 0 ] || fail "gitleaks rc=2 : le hook rend $RC au lieu de 0"
echo "$OUT" | grep -q "a échoué" || fail "gitleaks rc=2 : sortie sans « a échoué »"
pass "gitleaks rc=2 : commit autorisé, avertissement affiché"

# ── 6. Le vrai gitleaks, quand il est installé ───────────────────────────────
REAL_GITLEAKS="$(command -v gitleaks || true)"
if [ -z "$REAL_GITLEAKS" ]; then
    echo "⏭  vrai gitleaks absent du PATH : cas d'intégration sauté"
else
    mkdir -p "$TMP/real"
    ln -s "$REAL_GITLEAKS" "$TMP/real/gitleaks"
    cat > "$TMP/gitleaks.toml" <<'EOF'
[[rules]]
id = "fixture-oss-test"
description = "marqueur de fixture"
regex = '''OSS-FIXTURE-MARQUEUR-INTERDIT'''
keywords = ["OSS-FIXTURE-MARQUEUR"]
EOF
    nouveau_depot "$TMP/repo_real"

    run "$TMP/repo_real" "$BIN:$TMP/real" GITLEAKS_CONFIG="$TMP/gitleaks.toml"
    echo "vrai gitleaks, fichier propre : rc=$RC"; echo "$OUT"
    [ "$RC" -eq 0 ] || fail "vrai gitleaks, fichier propre : le hook rend $RC au lieu de 0 — sortie : $OUT"
    [ -z "$OUT" ] || fail "vrai gitleaks, fichier propre : le hook devrait être silencieux — sortie : $OUT"
    pass "vrai gitleaks : fichier propre → commit autorisé, sortie vide"

    echo "cle = OSS-FIXTURE-MARQUEUR-INTERDIT" > "$TMP/repo_real/interdit.txt"
    git -C "$TMP/repo_real" add interdit.txt
    run "$TMP/repo_real" "$BIN:$TMP/real" GITLEAKS_CONFIG="$TMP/gitleaks.toml"
    echo "vrai gitleaks, marqueur stagé : rc=$RC"; echo "$OUT"
    [ "$RC" -eq 1 ] || fail "vrai gitleaks, marqueur stagé : le hook rend $RC au lieu de 1"
    echo "$OUT" | grep -q "secret détecté" || fail "vrai gitleaks, marqueur stagé : sortie sans « secret détecté »"
    echo "$OUT" | grep -q "OSS-FIXTURE-MARQUEUR-INTERDIT" \
        && fail "vrai gitleaks : la valeur interdite est affichée en clair par le hook"
    pass "vrai gitleaks : marqueur stagé → commit refusé, valeur non affichée"
fi

echo ""
echo "🎉 Tous les tests passent."
