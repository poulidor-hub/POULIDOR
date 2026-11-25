#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# pre-push-oss-guard.sh — refuse un push qui apporterait une valeur interdite.
#
# Open source — filet de sécurité : la garde des valeurs interdites
# (scripts/oss-guard.sh) appliquée à ce que le push apporte, référence par
# référence.
#
# Entrée standard (contrat git du hook pre-push) :
#   <ref locale> <sha local> <ref distante> <sha distant>
# Pour chaque sha local non nul, la plage examinée est <sha distant>..<sha local>.
# Sha distant nul (référence nouvelle) : <base>..<sha local>, où <base> est le
# plus proche ancêtre commun avec origin/HEAD ; à défaut avec origin/main ; à
# défaut (aucune référence distante connue : premier push), tout l'historique.
#
# Fichier de motifs : OSS_FORBIDDEN_FILE, sinon
# ~/.config/poulidor/oss-forbidden.txt (local, jamais affiché).
# Fichier absent : avertissement et sortie 0. Motif trouvé, ou analyse
# impossible (fichier vide ou inutilisable, plage indéterminable) : sortie 1.
#
# Test : scripts/tests/test_oss_guard.sh
set -euo pipefail

case "${BASH_SOURCE[0]}" in */*) dossier="${BASH_SOURCE[0]%/*}" ;; *) dossier="." ;; esac
GARDE="$dossier/../oss-guard.sh"
FICHIER="${OSS_FORBIDDEN_FILE:-$HOME/.config/poulidor/oss-forbidden.txt}"

# Lance une commande sans que set -e arrête le script ; renseigne RC.
sans_e() { set +e; "$@"; RC=$?; set -e; }
# est_nul <sha> : le sha est absent (que des zéros).
est_nul() { case "$1" in *[!0]*) return 1 ;; esac; return 0; }

if [ ! -f "$FICHIER" ]; then
    echo "⚠ oss-guard : fichier de motifs absent ($FICHIER) — push autorisé sans analyse des valeurs interdites."
    exit 0
fi
if [ ! -f "$GARDE" ]; then
    echo "✗ oss-guard : scripts/oss-guard.sh introuvable ($GARDE) — push refusé."
    exit 1
fi

# plage_nouvelle_ref <sha> : ce qu'apporte une référence encore inconnue du
# dépôt distant ; vide si rien ne permet de le délimiter.
plage_nouvelle_ref() {
    local sha="$1" base="" ref
    if git rev-parse -q --verify origin/HEAD >/dev/null 2>&1; then
        base="$(git merge-base origin/HEAD "$sha" 2>/dev/null || true)"
    fi
    if [ -z "$base" ] && git rev-parse -q --verify origin/main >/dev/null 2>&1; then
        base="$(git merge-base origin/main "$sha" 2>/dev/null || true)"
    fi
    if [ -n "$base" ]; then
        printf '%s..%s' "$base" "$sha"
        return 0
    fi
    ref="$(git for-each-ref --format='%(refname)' refs/remotes/origin)"
    if [ -z "$ref" ]; then printf '%s' "$sha"; fi    # aucune référence distante : tout est apporté
}

refus=0
lues=0
while read -r ref_locale sha_locale ref_distante sha_distante; do
    [ -n "${sha_locale:-}" ] || continue
    lues=$((lues + 1))
    if est_nul "$sha_locale"; then continue; fi      # suppression de référence : rien n'est apporté
    if est_nul "$sha_distante"; then
        plage="$(plage_nouvelle_ref "$sha_locale")"
    else
        plage="$sha_distante..$sha_locale"
    fi
    if [ -z "$plage" ]; then
        echo "✗ oss-guard : $ref_locale vers $ref_distante — impossible de délimiter ce que ce push apporte (aucune référence distante exploitable) ; « git fetch origin » ou « git remote set-head origin -a », puis recommencer."
        refus=1
        continue
    fi
    # L'entrée standard est réservée aux lignes du hook : l'analyse n'en lit rien.
    sans_e bash "$GARDE" scan-range "$FICHIER" "$plage" . < /dev/null
    if [ "$RC" -eq 0 ]; then continue; fi
    refus=1
    if [ "$RC" -eq 1 ]; then
        echo "✗ oss-guard : $ref_locale vers $ref_distante — push refusé pour cette référence."
    else
        echo "✗ oss-guard : $ref_locale vers $ref_distante — analyse impossible (fichier de motifs vide ou inutilisable) ; push refusé."
    fi
done

if [ "$lues" -eq 0 ]; then
    echo "⚠ oss-guard : aucune référence reçue sur l'entrée standard — rien n'a été examiné (push sans mise à jour, ou entrée standard déjà lue par un hook placé avant)."
fi
if [ "$refus" -ne 0 ]; then
    echo "✗ oss-guard : push refusé."
fi
exit "$refus"
