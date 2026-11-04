#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_parc_isolate.sh — régression : parc-isolate doit opérer sur le dépôt du
# répertoire courant, y compris quand ce dépôt est un SUBMODULE.
#
# Bug 02/10/2026 : MAIN_ROOT = dirname(git-common-dir) → pour un submodule
# (<super>/.git/modules/<nom>/.. = <super>/.git/modules), les commandes git -C
# remontaient au SUPERPROJET : branche/worktree/registre/push créés sur le
# mauvais dépôt.
#
# Fixture : superprojet (clone d'un bare) + submodule (clone d'un bare), tout
# local. Exécute le script depuis le submodule et vérifie que la branche, le
# push, le worktree et le registre atterrissent côté SUBMODULE — et jamais sur
# le superprojet. Teste aussi --cleanup sur le même chemin de code (MAIN_ROOT).
set -euo pipefail

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/.." && pwd)/parc-isolate"
BRANCH="test/parc-isolate-sub"
AGENT_ID="jellycode-test0001"

TMP="$(mktemp -d /tmp/parc-isolate-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# ── Fixture ──────────────────────────────────────────────────────────────────
git init --bare -q -b main "$TMP/origin_meta.git"
git init --bare -q -b main "$TMP/origin_sub.git"

git clone -q "$TMP/origin_meta.git" "$TMP/meta"
git -C "$TMP/meta" config user.email test@local && git -C "$TMP/meta" config user.name test
echo meta > "$TMP/meta/README.md"
git -C "$TMP/meta" add README.md && git -C "$TMP/meta" commit -qm "init meta"
git -C "$TMP/meta" push -q origin main

git clone -q "$TMP/origin_sub.git" "$TMP/sub_seed"
git -C "$TMP/sub_seed" config user.email test@local && git -C "$TMP/sub_seed" config user.name test
echo sub > "$TMP/sub_seed/README.md"
git -C "$TMP/sub_seed" add README.md && git -C "$TMP/sub_seed" commit -qm "init sub"
git -C "$TMP/sub_seed" push -q origin main

git -C "$TMP/meta" -c protocol.file.allow=always submodule add -q "$TMP/origin_sub.git" HUB_base
git -C "$TMP/meta" commit -qm "add submodule HUB_base"
git -C "$TMP/meta" push -q origin main

SUB="$TMP/meta/HUB_base"
git -C "$SUB" config user.email test@local && git -C "$SUB" config user.name test

# ── Action : isolate DEPUIS le submodule ─────────────────────────────────────
OUT="$(cd "$SUB" && bash "$SCRIPT_UNDER_TEST" "$BRANCH" "test submodule" --agent-id "$AGENT_ID")"
echo "$OUT"

# ── Assertions : tout doit vivre côté SUBMODULE ──────────────────────────────
# 1. Registre dans le submodule (convention .worktrees/_agents du dépôt)
[ -f "$SUB/.worktrees/_agents/registry.json" ] \
    || fail "registre absent du submodule : $SUB/.worktrees/_agents/registry.json"
pass "registre créé côté submodule"

# 2. Branche créée dans le submodule
git -C "$SUB" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null \
    || fail "branche $BRANCH absente du submodule"
pass "branche créée dans le submodule"

# 3. Branche poussée sur l'ORIGIN DU SUBMODULE
git -C "$TMP/origin_sub.git" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null \
    || fail "branche $BRANCH non poussée sur l'origin du submodule"
pass "branche poussée sur l'origin du submodule"

# 4. Worktree enregistré dans le repo submodule, au chemin conventionnel
git -C "$SUB" worktree list | grep -q "$SUB/.worktrees/_agents/test-parc-isolate-sub" \
    || fail "worktree non enregistré dans le submodule au chemin conventionnel"
[ -d "$SUB/.worktrees/_agents/test-parc-isolate-sub" ] \
    || fail "répertoire worktree absent du submodule"
pass "worktree créé côté submodule"

# 5. LE BUG HISTORIQUE : rien ne doit fuiter vers le superprojet
git -C "$TMP/meta" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null \
    && fail "branche $BRANCH créée sur le SUPERPROJET (bug historique)"
[ ! -d "$TMP/meta/.git/modules/.worktrees" ] \
    || fail "registre/worktree créés dans .git/modules (bug historique)"
pass "aucune fuite vers le superprojet"

# ── Même chemin de code : cleanup depuis le submodule ───────────────────────
OUT="$(cd "$SUB" && bash "$SCRIPT_UNDER_TEST" --cleanup "$BRANCH")"
echo "$OUT"
git -C "$SUB" worktree list | grep -q "test-parc-isolate-sub" \
    && fail "cleanup : worktree toujours présent côté submodule"
python3 -c 'import json,sys; reg=json.load(open(sys.argv[1])); exit(0 if reg["agents"] else 1)' \
    "$SUB/.worktrees/_agents/registry.json" \
    && fail "cleanup : entrée registre toujours active"
pass "cleanup opérationnel depuis le submodule"

# ── Dépôt NORMAL : le fallback dirname ne doit pas régresser (revue 05/10) ──
git clone -q "$TMP/origin_meta.git" "$TMP/plain"
OUT="$(cd "$TMP/plain" && bash "$SCRIPT_UNDER_TEST" test/fallback-normal "tâche" --agent-id "$AGENT_ID")"
git -C "$TMP/plain" rev-parse --verify -q "refs/heads/test/fallback-normal" >/dev/null \
    || fail "fallback dépôt normal : branche non créée"
git -C "$TMP/origin_meta.git" rev-parse --verify -q "refs/heads/test/fallback-normal" >/dev/null \
    || fail "fallback dépôt normal : branche non poussée sur origin"
[ -d "$TMP/plain/.worktrees/_agents/test-fallback-normal" ] \
    || fail "fallback dépôt normal : worktree absent"
(cd "$TMP/plain" && bash "$SCRIPT_UNDER_TEST" --list) | grep -q "test/fallback-normal" \
    || fail "--list n'affiche pas l'agent du dépôt normal"
(cd "$TMP/plain" && bash "$SCRIPT_UNDER_TEST" --cleanup test/fallback-normal) >/dev/null
pass "fallback dépôt normal (isolate + --list + cleanup)"

# ── core.worktree stale : mort PROPRE, jamais un traceback bash brut ─────
# Contrat réel : git rejette lui-même le config stale à la vérification
# is-inside-work-tree (die amont « hors dépôt git »). La garde cd dans le
# script reste en DÉFENSE EN PROFONDEUR (race/TOCTOU, non falsifiable en
# fixture) — ce test épingle qu'un config pourri sort par die, pas par crash.
git init -q -b main "$TMP/stale_repo"
git -C "$TMP/stale_repo" config user.email test@local
git -C "$TMP/stale_repo" config user.name test
echo x > "$TMP/stale_repo/f" && git -C "$TMP/stale_repo" add f && git -C "$TMP/stale_repo" commit -qm init
git -C "$TMP/stale_repo" config core.worktree "/nonexistent/parc-isolate-stale-xyz"
OUT_STALE="$(cd "$TMP/stale_repo" && bash "$SCRIPT_UNDER_TEST" test/stale "tâche" --agent-id "$AGENT_ID" 2>&1)" \
    && fail "core.worktree stale : le script aurait dû échouer"
echo "$OUT_STALE" | grep -q "parc-isolate:" \
    || fail "core.worktree stale : sortie sans die explicite (crash bash brut ?)"
pass "core.worktree stale → die explicite (pas de traceback bash)"

echo ""
echo "🎉 Tous les tests passent."
