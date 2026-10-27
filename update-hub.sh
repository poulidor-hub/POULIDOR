#!/usr/bin/env bash
# Alias rétrocompatible : update-hub.sh = hub.sh update
#
# ⚠️  DÉPRÉCIÉ (plan unification updates, oct. 2026) : la mise à jour vit
#     désormais dans hubctl — utilisez `hubctl update hub`.
#     Ce fichier sera supprimé dans une prochaine release.
echo "⚠️  update-hub.sh est déprécié — utilisez : hubctl update hub" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hub.sh" update "$@"
