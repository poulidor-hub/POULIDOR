#!/usr/bin/env bash
# install-version-guard — installe le hook pre-push anti-régression de VERSION.
#
# Usage : bash scripts/install-version-guard.sh   (depuis la racine du dépôt)
#
# Crée .git/hooks/pre-push (append si un hook existe déjà — multi-hooks via
# un appel en chaîne). Fonctionne aussi depuis un worktree (hooks du common
# dir partagés entre worktrees — le garde protège alors tous les worktrees).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="${SCRIPT_DIR}/hooks/pre-push-version-guard.sh"
[ -f "$HOOK_SRC" ] || { echo "❌ hook source introuvable: $HOOK_SRC" >&2; exit 1; }

GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
HOOKS_DIR="${GIT_DIR}/hooks"
mkdir -p "$HOOKS_DIR"

install -m 0755 "$HOOK_SRC" "${HOOKS_DIR}/pre-push-version-guard.sh"

HOOK_FILE="${HOOKS_DIR}/pre-push"
if [ -f "$HOOK_FILE" ] && grep -q "pre-push-version-guard.sh" "$HOOK_FILE" 2>/dev/null; then
    echo "✅ hook pre-push déjà câblé vers pre-push-version-guard.sh"
elif [ -f "$HOOK_FILE" ]; then
    # Chaîner : préserver le hook existant, ajouter le nôtre à la suite
    if ! grep -q "pre-push-version-guard.sh" "$HOOK_FILE"; then
        printf '\n# version-guard (install-version-guard.sh)\nbash "%s/pre-push-version-guard.sh" "$@"\n' "$HOOKS_DIR" >> "$HOOK_FILE"
        echo "✅ chaîné au hook pre-push existant"
    fi
else
    printf '#!/usr/bin/env bash\n# installé par scripts/install-version-guard.sh\nbash "%s/pre-push-version-guard.sh" "$@"\n' "$HOOKS_DIR" > "$HOOK_FILE"
    chmod +x "$HOOK_FILE"
    echo "✅ hook pre-push installé (${HOOK_FILE})"
fi
