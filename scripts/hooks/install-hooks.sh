#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -e
ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/.git/hooks/pre-commit"
SRC="$ROOT/scripts/hooks/pre-commit-gitleaks.sh"
if [ -f "$HOOK" ] && ! grep -q "gitleaks" "$HOOK"; then
  { echo ""; echo "# --- gitleaks (install-hooks) ---"; echo "bash \"$SRC\" || exit 1"; } >> "$HOOK"
  chmod +x "$HOOK"; echo "✅ gitleaks chaîné au pre-commit existant"
else
  cp "$SRC" "$HOOK"; chmod +x "$HOOK"; echo "✅ pre-commit gitleaks installé"
fi
