#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# url-scheme.sh — bibliothèque : le schéma d'une URL distante git.
#
# Open source : les sous-modules du méta sont en HTTPS absolu, pour qu'un clone
# anonyme les initialise. Un fork de déploiement accédé par clé SSH doit
# pourtant garder des sous-modules en SSH : un fork privé en HTTPS exigerait des
# identifiants.
#
# À sourcer, ne s'exécute pas seul : source scripts/lib/url-scheme.sh
# Test : scripts/tests/test_to_fork_scheme.sh

# to_fork_scheme <fork_url> <url> : <url> rendue au schéma de <fork_url>.
#   - fork en SSH (git@hôte:chemin ou ssh://[utilisateur@]hôte/chemin) et <url>
#     en HTTPS sur le MÊME hôte : <url> passe en SSH sur cet hôte ;
#   - dans tous les autres cas, <url> est rendue telle quelle : fork en HTTPS,
#     <url> déjà en SSH, <url> d'un autre hôte ou chemin local.
# Rendu sur la sortie standard, sans fin de ligne.
to_fork_scheme() {
    local fork="${1:-}" url="${2:-}" hote autorite
    case "$fork" in
        git@*:*)
            hote="${fork#git@}"; hote="${hote%%:*}"
            case "$url" in
                "https://$hote/"*) printf 'git@%s:%s' "$hote" "${url#"https://$hote/"}" ;;
                *) printf '%s' "$url" ;;
            esac ;;
        ssh://*)
            autorite="${fork#ssh://}"; autorite="${autorite%%/*}"
            hote="${autorite#*@}"
            case "$url" in
                "https://$hote/"*) printf 'ssh://%s/%s' "$autorite" "${url#"https://$hote/"}" ;;
                *) printf '%s' "$url" ;;
            esac ;;
        *) printf '%s' "$url" ;;
    esac
}
