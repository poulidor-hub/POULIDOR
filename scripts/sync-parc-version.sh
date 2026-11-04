#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# sync-parc-version — resynchronise la version AFFICHÉE du parc sur VERSION.
#
# Contexte : la version affichée (badge README, guide.js, footers des pages
# guide-hub) était resynchronisée à la main à chaque release et a dérivé de
# 14 versions (0.66.9 affiché pour un parc en 0.80.x — constaté le 2026-11-04).
# Ce script fait le resync au moment du bump (skill release-on-main, cas 4 du
# méta-repo) et sait aussi vérifier l'absence de drift.
#
# Usage :
#   bash scripts/sync-parc-version.sh <version>          # écrit <version> partout
#   bash scripts/sync-parc-version.sh --check            # compare à VERSION
#   bash scripts/sync-parc-version.sh --check <version>  # compare à <version>
#
# Fichiers cibles (méta-repo uniquement ; absent → ignoré avec info) :
#   - README.md                        badge img.shields.io/badge/version-…
#   - docs/guide-hub/assets/guide.js   var PARC_VERSION = "…"
#   - docs/guide-hub/*.html            <span data-parc-version>…</span>
#
# Sortie : 0 = OK (synchronisé ou sain), 1 = drift détecté (--check),
#          2 = usage. Idempotent : resynchroniser ne change rien si déjà bon.

set -euo pipefail

MODE="${1:-}"
VERSION="${2:-}"

info() { echo "   ℹ️  $*"; }
ok()   { echo "✅ $*"; }

usage() {
    cat >&2 << 'EOF'
usage: bash scripts/sync-parc-version.sh <version>
       bash scripts/sync-parc-version.sh --check [<version>]

<version> : MAJOR.MINOR.PATCH (ex. 0.80.8)
Sans --check : écrit <version> dans le badge README, guide.js et les footers
des pages docs/guide-hub/. Avec --check : compare à <version> ou au fichier
VERSION (exit 1 si drift).
EOF
    exit 2
}

is_semver() { printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }

case "$MODE" in
    --check) CHECK=1 ;;
    "") usage ;;
    *) CHECK=0 ; VERSION="$MODE" ; [ -n "$VERSION" ] || usage ;;
esac

if [ "$CHECK" -eq 0 ]; then
    is_semver "$VERSION" || { echo "❌ version invalide : '$VERSION' (attendu MAJOR.MINOR.PATCH)" >&2; exit 2; }
else
    if [ -z "$VERSION" ]; then
        [ -f VERSION ] || { info "pas de fichier VERSION — rien à vérifier"; exit 0; }
        VERSION="$(tr -d '[:space:]' < VERSION)"
        is_semver "$VERSION" || { echo "❌ VERSION invalide : '$VERSION'" >&2; exit 2; }
    else
        is_semver "$VERSION" || usage
    fi
fi

# ── collecte des cibles ──────────────────────────────────────────────
guide_js="docs/guide-hub/assets/guide.js"
readme="README.md"
targets=()
[ -f "$readme" ] && targets+=("$readme")
[ -f "$guide_js" ] && targets+=("$guide_js")
if [ -d docs/guide-hub ]; then
    while IFS= read -r f; do targets+=("$f"); done < <(grep -rl 'data-parc-version' docs/guide-hub --include='*.html' 2>/dev/null | sort)
fi

if [ "${#targets[@]}" -eq 0 ]; then
    info "aucun fichier cible trouvé (hors méta-repo ?) — rien à faire"
    exit 0
fi

# ── --check : comparaison sans écriture ──────────────────────────────
if [ "$CHECK" -eq 1 ]; then
    drift=0
    for f in "${targets[@]}"; do
        if grep -q -- "data-parc-version>${VERSION}<" "$f" 2>/dev/null \
           || grep -q -- "PARC_VERSION = \"${VERSION}\"" "$f" 2>/dev/null \
           || grep -q -- "badge/version-${VERSION}-blue" "$f" 2>/dev/null; then
            ok "${f} → ${VERSION}"
        else
            shown="$(grep -o -- 'data-parc-version>[^<]*<\|PARC_VERSION = "[^"]*"\|badge/version-[0-9.]*-blue' "$f" 2>/dev/null | head -n1 | sed 's/<$//; s/^data-parc-version>//; s/<$//' || true)"
            echo "❌ ${f} — en retard : affiche '${shown:-?}' au lieu de '${VERSION}'" >&2
            drift=1
        fi
    done
    if [ "$drift" -eq 0 ]; then
        ok "version affichée en phase avec VERSION (${VERSION})"
    else
        echo "❌ drift de la version affichée — lancez : bash scripts/sync-parc-version.sh ${VERSION}" >&2
    fi
    exit "$drift"
fi

# ── sync : écriture ──────────────────────────────────────────────────
changed=0
for f in "${targets[@]}"; do
    before="$(md5sum "$f" | cut -d' ' -f1)"
    sed -i \
        -e "s|data-parc-version>[^<]*<|data-parc-version>${VERSION}<|g" \
        -e "s|var PARC_VERSION = \"[^\"]*\";|var PARC_VERSION = \"${VERSION}\";|g" \
        -e "s|badge/version-[0-9.]*-blue|badge/version-${VERSION}-blue|g" \
        "$f"
    if [ "$(md5sum "$f" | cut -d' ' -f1)" != "$before" ]; then
        echo "   ✏️  ${f} → ${VERSION}"
        changed=$((changed + 1))
    fi
done

if [ "$changed" -eq 0 ]; then
    ok "rien à faire — version affichée déjà en ${VERSION}"
else
    ok "${changed} fichier(s) resynchronisé(s) sur ${VERSION} — à inclure au commit de release"
fi
exit 0
