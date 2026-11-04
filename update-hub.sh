#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# Alias rétrocompatible : update-hub.sh = hub.sh update
#
# ⚠️  DÉPRÉCIÉ (plan unification updates, oct. 2026) : la mise à jour vit
#     désormais dans hubctl — utilisez `hubctl update hub`.
#     Ce fichier sera supprimé dans une prochaine release.
echo "⚠️  update-hub.sh est déprécié — utilisez : hubctl update hub" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hub.sh" update "$@"
