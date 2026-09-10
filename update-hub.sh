#!/usr/bin/env bash
# Alias rétrocompatible : update-hub.sh = hub.sh update
# (voir ./hub.sh --help pour toutes les commandes d'exploitation du HUB)
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hub.sh" update "$@"
