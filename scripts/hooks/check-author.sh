#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# check-author.sh — garde d'identité : refuse un commit dont l'auteur ou le
# committer utilise une adresse e-mail absente de allowed-authors.txt.
#
# Open source — filet de sécurité : une adresse personnelle ou celle d'un
# client dans les métadonnées d'un commit recrée une fuite, y compris après
# la réécriture de l'historique.
#
# Adresses lues : GIT_AUTHOR_EMAIL, sinon git config user.email ; et
# GIT_COMMITTER_EMAIL s'il est défini. La liste tient une expression
# rationnelle d'adresse par ligne, comparée sans tenir compte de la casse ;
# les lignes vides et les commentaires (#) sont ignorés. Liste vide ou
# absente : refus. Seul le domaine de l'adresse refusée est affiché.
# Contournement explicite : OSS_AUTHOR_SKIP=1.
#
# Test : scripts/tests/test_check_author.sh
set -euo pipefail

if [ "${OSS_AUTHOR_SKIP:-}" = "1" ]; then
  echo "⚠ OSS_AUTHOR_SKIP=1 : garde d'identité contournée — commit autorisé."
  exit 0
fi

case "${BASH_SOURCE[0]}" in */*) dossier="${BASH_SOURCE[0]%/*}" ;; *) dossier="." ;; esac
liste="$dossier/allowed-authors.txt"

motifs=()
if [ -f "$liste" ]; then
  while IFS= read -r ligne || [ -n "$ligne" ]; do
    ligne="${ligne#"${ligne%%[![:space:]]*}"}"     # blancs de tête
    case "$ligne" in ''|'#'*) continue ;; esac
    motifs+=("$ligne")
  done < "$liste"
fi

refuser() {  # refuser <adresse> : message sans la partie locale de l'adresse
  local domaine="${1##*@}"
  [ -n "$domaine" ] || domaine="(aucune adresse)"
  echo "✗ identité de commit non autorisée : $domaine ; voir scripts/hooks/allowed-authors.txt"
  if [ "${#motifs[@]}" -eq 0 ]; then
    echo "  La liste d'autorisation est vide, ou absente : aucune adresse n'est autorisée."
  else
    echo "  Utilisez une adresse de la liste : git config user.email, ou GIT_AUTHOR_EMAIL et GIT_COMMITTER_EMAIL."
  fi
  exit 1
}

autorisee() {  # autorisee <adresse> : 0 si une expression de la liste correspond
  local addr="$1" args=() m
  [ -n "$addr" ] || return 1
  [ "${#motifs[@]}" -gt 0 ] || return 1
  for m in "${motifs[@]}"; do args+=(-e "$m"); done
  printf '%s\n' "$addr" | grep -qiE "${args[@]}"
}

auteur="${GIT_AUTHOR_EMAIL:-$(git config user.email 2>/dev/null || true)}"
autorisee "$auteur" || refuser "$auteur"
if [ -n "${GIT_COMMITTER_EMAIL:-}" ]; then
  autorisee "$GIT_COMMITTER_EMAIL" || refuser "$GIT_COMMITTER_EMAIL"
fi
