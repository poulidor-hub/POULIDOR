#!/usr/bin/env bash
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

echo ""
echo "🎉 Tous les tests passent."
