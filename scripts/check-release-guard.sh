#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# check-release-guard — garde-fou de release pour le méta-repo POULIDOR
# (bump manuel : pas de sync_version.py ici — même gardes que
# sync_version.py du HUB_base, incident 2026-10-04).
#
# Usage : bash scripts/check-release-guard.sh <nouvelle_version>
#   ex : bash scripts/check-release-guard.sh 0.71.9
#
# Vérifie AVANT d'écrire VERSION/CHANGELOG :
#   1. origin/main n'est pas strictement en avance sur le local (fetch +
#      comparaison) — sinon abort : pull d'abord ;
#   2. le numéro cible n'existe pas déjà dans CHANGELOG.md (double bump
#      parallèle — 0.71.6 en double le 2026-10-04).
# Sortie : 0 = OK, 1 = collision (ne pas releaser), 2 = usage.
# Dégradation silencieuse hors-ligne (origin indéterminable → OK).

set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <nouvelle_version>" >&2; exit 2; }
NEW_VERSION="$1"

info() { echo "   ℹ️  $*"; }
abort() { echo "❌ COLLISION DE RELEASE : $*" >&2; exit 1; }

# 1. origin pas en avance
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    info "branche indéterminable — garde origin en silencieux"
else
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name "${branch}@{u}" 2>/dev/null || true)"
    if [ -z "$upstream" ]; then
        info "pas d'upstream — garde origin en silencieux"
    else
        remote_name="${upstream%%/*}"
        if git fetch "$remote_name" "$branch" --quiet 2>/dev/null; then
            origin_version="$(git show "${upstream}:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
            local_version="$(tr -d '[:space:]' < VERSION 2>/dev/null || true)"
            if [ -n "$origin_version" ] && [ -n "$local_version" ]; then
                smallest="$(printf '%s\n%s\n' "$local_version" "$origin_version" | sort -V | head -n1)"
                if [ "$smallest" = "$origin_version" ] && [ "$local_version" != "$origin_version" ]; then
                    abort "origin est en version ${origin_version}, le dépôt local est en ${local_version}.
   Une autre session a poussé une release pendant votre travail.
   → git pull origin ${branch} (résolvez VERSION/CHANGELOG si conflit), puis re-bump."
                fi
                [ "$local_version" != "$origin_version" ] && info "local en avance sur origin (${local_version} > ${origin_version}) — commits non poussés"
            fi
        else
            info "fetch impossible (hors-ligne ?) — garde origin en silencieux"
        fi
    fi
fi

# 2. numéro cible non déjà pris
if [ -f CHANGELOG.md ] && grep -q "^## \[${NEW_VERSION}\]" CHANGELOG.md; then
    abort "l'entrée [${NEW_VERSION}] existe déjà dans CHANGELOG.md.
   Une autre session a probablement pris ce numéro en parallèle.
   → git pull, résolvez, puis re-bump (le numéro suivant sera alloué)."
fi

echo "✅ check-release-guard : OK pour ${NEW_VERSION}"
