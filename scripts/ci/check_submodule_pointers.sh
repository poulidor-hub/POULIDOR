#!/bin/bash
# check_submodule_pointers.sh — CI méta POULIDOR
# Vérifie que le commit pointé par CHAQUE sous-module est contenu dans
# origin/main du dépôt du sous-module (i.e. poussé ET mergé).
# Échoue (exit 1) si un pointeur est local/non-mergé/inexistant.
set -uo pipefail
FAIL=0
while read -r sha path; do
  [ -z "$sha" ] && continue
  if [ ! -d "$path/.git" ]; then
    echo "❌ $path : submodule non initialisé"; FAIL=1; continue
  fi
  git -C "$path" fetch origin main --quiet 2>/dev/null
  if git -C "$path" merge-base --is-ancestor "$sha" origin/main 2>/dev/null; then
    echo "✅ $path : $sha sur origin/main"
  else
    echo "❌ $path : $sha PAS sur origin/main (non poussé ou non mergé)"; FAIL=1
  fi
done < <(git ls-tree HEAD | awk '$1=="commit" {print $3" "$4}')
[ "$FAIL" = 0 ] && echo "✅ Tous les pointeurs sous-modules sont poussés/mergés" || echo "⛔ ÉCHEC pointeurs"
exit $FAIL
