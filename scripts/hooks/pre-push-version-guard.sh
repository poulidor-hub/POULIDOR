#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# pre-push-version-guard — dernier rempart anti-écrasement croisé (parc POULIDOR).
#
# Refuse tout push qui ferait RÉGRESSER le fichier VERSION par rapport à la
# branche distante (deux sessions releaseant en parallèle : incident 2026-10-04,
# VERSION 0.71.6 poussée après 0.71.7 par une autre session).
#
# Installation : bash scripts/install-version-guard.sh  (depuis la racine du dépôt)
# Comportement : exit 1 et message actionnable si régression détectée ;
#                silencieux si VERSION absent d'un côté (branche sans release).
#
# stdin (contrat git pre-push) : <local_ref> <local_oid> <remote_ref> <remote_oid>

set -euo pipefail

regression_detected=0

while read -r local_ref local_oid remote_ref remote_oid; do
    # Ne concerne que les branches
    case "$local_ref" in refs/heads/*) ;; *) continue ;; esac
    branch="${local_ref#refs/heads/}"

    local_version="$(git show "${local_oid}:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
    remote_version="$(git show "${remote_oid}:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"

    # VERSION absent d'un côté : rien à comparer (branche sans release,
    # suppression de fichier, dépôt neuf)
    [ -z "$local_version" ] && continue
    [ -z "$remote_version" ] && continue

    # Régression ? (le plus petit des deux doit être remote, pas local)
    smallest="$(printf '%s\n%s\n' "$local_version" "$remote_version" | sort -V | head -n1)"
    if [ "$smallest" = "$local_version" ] && [ "$local_version" != "$remote_version" ]; then
        echo "❌ PUSH REFUSÉ — régression de VERSION sur la branche '${branch}' :" >&2
        echo "   local  : ${local_version}" >&2
        echo "   origin : ${remote_version}" >&2
        echo "   Une autre session a poussé une release plus récente pendant votre travail." >&2
        echo "   → git pull origin ${branch} (résolvez VERSION/CHANGELOG si conflit)," >&2
        echo "     re-bumpez si nécessaire, puis re-pushez." >&2
        regression_detected=1
    fi
done

exit "$regression_detected"
