#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# Serveur MCP hub (mode standalone) — lancement autonome depuis le méta-repo.
#
# Utilisé par opencode.json (racine POULIDOR) : ["bash", "mcp-hub.sh"].
# - Chemins résolus depuis la position du script → insensible au cwd d'opencode
#   (IDE, lanceur graphique, sous-dossier…).
# - Source .secrets s'il existe → indépendant du shell appelant (pattern hubctl) :
#   sans ça, HUB_BASE_URL / HUB_ADMIN_USERNAME / HUB_ADMIN_PASSWORD ne sont présents
#   que dans les shells interactifs (~/.bashrc) et CHAQUE appel d'outil MCP échoue.
# .secrets reste gitignoré : aucun secret n'est committé.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$ROOT_DIR/.secrets" ]; then
    set -a
    . "$ROOT_DIR/.secrets"
    set +a
else
    echo "mcp-hub.sh: ATTENTION — $ROOT_DIR/.secrets absent : le mode standalone échouera à chaque appel d'outil." >&2
    echo "mcp-hub.sh: cp .secrets.example .secrets puis éditer (chmod 600)." >&2
fi

cd "$ROOT_DIR/hub-mcp"
exec python3 -m hub_mcp.server
