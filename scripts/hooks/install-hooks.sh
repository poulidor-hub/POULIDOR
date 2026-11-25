#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# install-hooks.sh — installe le pare-feu open source (pre-commit, pre-push) de
# façon idempotente, sans jamais écraser un hook existant.
#
# Usage : bash scripts/hooks/install-hooks.sh [--all]
#   sans option : ce dépôt (le méta) ;
#   --all       : le méta et chacun des sous-modules de .gitmodules.
#
# Pour chaque dépôt, le dossier de hooks est celui de git
# (`git rev-parse --git-path hooks`). Pour pre-commit et pre-push : si le hook
# contient déjà la ligne de marque, rien ne change ; sinon le fichier est créé
# s'il manque et rendu exécutable. Les scripts sont appelés par le chemin
# absolu du méta, relevé à l'installation.
#
# Devant un hook existant, le bloc du pare-feu est placé EN TÊTE, juste après
# le shebang, et les lignes existantes ne sont pas modifiées. En fin de fichier,
# il serait sauté dès que le hook d'origine se termine par « exit » — et le
# pre-push lirait une entrée standard déjà consommée par le hook d'origine.
# Pour pre-push, l'entrée standard est donc mise de côté : la garde la lit, le
# hook d'origine la retrouve ensuite, intacte.
#
# Tout est contrôlé avant toute écriture : en cas de refus, rien n'est écrit,
# dans aucun dépôt. L'installateur refuse : depuis un worktree lié (les hooks
# sont partagés avec le checkout principal, et le bloc mémorise un chemin
# absolu) ; si le dossier de hooks est hors du dépôt (core.hooksPath) ; si un
# sous-module n'est pas initialisé ; devant un hook existant qui n'est pas un
# script shell, ou qui est un lien symbolique ; devant le pare-feu déjà
# installé depuis un autre emplacement du méta ; devant la copie d'une
# ancienne version d'un script du pare-feu (l'ancien installateur recopiait le
# script gitleaks dans .git/hooks).
#
# Test : scripts/tests/test_install_hooks.sh
set -euo pipefail

MARQUEUR='# --- pare-feu open source (install-hooks) ---'
HOOKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$HOOKS_SRC/../.." && pwd -P)"

# Depuis un hook git, GIT_DIR et consorts sont exportés : chaque cible serait
# résolue vers le dépôt de l'appelant.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

die() { echo "❌ install-hooks.sh : $*" >&2; exit 1; }
# Usage : l'en-tête, sans le shebang ni les deux lignes de licence.
usage() { awk 'NR>3 && /^set /{exit} NR>3{sub(/^# ?/,""); print}' "$0"; }
echapper() { local s="$1"; s="${s//\'/\'\\\'\'}"; printf '%s' "$s"; }   # contenu d'une chaîne entre apostrophes
citer() { printf "'%s'" "$(echapper "$1")"; }

[ "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" = "$ROOT" ] \
    || die "lancé hors d'un checkout git : $ROOT"
for s in pre-commit-gitleaks.sh check-author.sh pre-push-oss-guard.sh; do
    [ -f "$HOOKS_SRC/$s" ] || die "script du pare-feu absent : $HOOKS_SRC/$s"
done

cibles=("$ROOT")
if [ "${1:-}" = "--all" ]; then
    [ -f "$ROOT/.gitmodules" ] || die "--all : $ROOT/.gitmodules absent"
    while IFS= read -r chemin; do
        [ -n "$chemin" ] && cibles+=("$ROOT/$chemin")
    done < <(git -C "$ROOT" config -f .gitmodules --get-regexp '^submodule\..*\.path$' \
             | sed -E 's/^[^[:space:]]+[[:space:]]//')
elif [ $# -gt 0 ]; then
    usage >&2; die "option inconnue : $1"
fi

# ── Contrôles (aucune écriture) ──────────────────────────────────────────────
# dossier_hooks <chemin> <nom> : le dossier de hooks du dépôt, en chemin absolu.
dossier_hooks() {
    local chemin nom git_dir commun h
    chemin="$(cd "$1" && pwd -P)" || die "$2 : répertoire introuvable ($1)"
    nom="$2"
    # Racine d'un dépôt, pas seulement « quelque part dans » un dépôt : un
    # sous-module non initialisé est un dossier vide dans l'arbre du superprojet.
    [ "$(git -C "$chemin" rev-parse --show-toplevel 2>/dev/null)" = "$chemin" ] \
        || die "$nom : pas un dépôt git initialisé, racine attendue : $chemin"
    git_dir="$(git -C "$chemin" rev-parse --absolute-git-dir)"
    commun="$(cd "$chemin" && git rev-parse --git-common-dir)"
    case "$commun" in /*) ;; *) commun="$chemin/$commun" ;; esac
    [ "$git_dir" = "$commun" ] || die "$nom : worktree lié ($chemin). Les hooks sont partagés avec le checkout principal et le bloc mémorise un chemin absolu : lancez l'installateur depuis le checkout principal."
    h="$(git -C "$chemin" rev-parse --git-path hooks)"
    case "$h" in /*) ;; *) h="$chemin/$h" ;; esac
    case "$h/" in
        "$commun/"*) ;;
        *) die "$nom : dossier de hooks hors du dépôt ($h ; core.hooksPath ?). Le bloc mémorise un chemin absolu, à ne pas faire suivre par git : installation manuelle." ;;
    esac
    printf '%s\n' "$h"
}

# interpreteur <fichier> : interpréteur nommé par le shebang (vide à défaut).
interpreteur() {
    local ligne mots=() i=0
    ligne="$(head -n 1 "$1")" || return 0
    case "$ligne" in '#!'*) ;; *) return 0 ;; esac
    read -r -a mots <<< "${ligne#\#!}"
    [ "${#mots[@]}" -gt 0 ] || return 0
    if [ "$(basename "${mots[0]}")" = "env" ]; then
        i=1
        while [ "$i" -lt "${#mots[@]}" ]; do
            case "${mots[$i]}" in -*) i=$((i + 1)) ;; *) break ;; esac
        done
    fi
    [ "$i" -lt "${#mots[@]}" ] || return 0
    basename "${mots[$i]}"
}

# copie_ancien_script <fichier> : le hook est-il la copie d'une version suivie
# d'un script du pare-feu (l'ancien installateur recopiait le script gitleaks
# dans .git/hooks) ? Affiche ce script le cas échéant.
copie_ancien_script() {
    local f="$1" empreinte script blob
    empreinte="$(git hash-object "$f")" || return 0
    for script in pre-commit-gitleaks.sh check-author.sh pre-push-oss-guard.sh; do
        while IFS= read -r blob; do
            if [ "$blob" = "$empreinte" ]; then echo "$script"; return 0; fi
        done < <(git -C "$ROOT" log --all --format=%H -- "scripts/hooks/$script" \
                 | while IFS= read -r commit; do
                       git -C "$ROOT" rev-parse -q --verify "$commit:scripts/hooks/$script" 2>/dev/null || true
                   done | sort -u)
    done
    return 0
}

# valider_hook <fichier> <nom> <hook> : un hook existant peut recevoir le bloc.
valider_hook() {
    local f="$1" nom="$2" hook="$3" interp copie
    [ ! -L "$f" ] || die "$nom : $hook est un lien symbolique — le bloc serait écrit dans sa cible ; chaînage manuel ($f)"
    [ -s "$f" ] || return 0
    if grep -qxF "$MARQUEUR" "$f"; then
        # Le bloc appelle '<dossier des scripts>/…' : si ce chemin a changé, il est mort.
        grep -qF -- "'$(echapper "$HOOKS_SRC")/" "$f" \
            || die "$nom : $hook contient déjà le pare-feu, mais installé depuis un autre emplacement du méta (méta déplacé ?) ; retirez l'ancien bloc à la main ($f)"
        return 0
    fi
    copie="$(copie_ancien_script "$f")"
    [ -z "$copie" ] || die "$nom : $hook est la copie d'une ancienne version de scripts/hooks/$copie ; supprimez-le puis relancez l'installateur, qui le recréera proprement ($f)"
    interp="$(interpreteur "$f")"
    case "$interp" in
        ''|sh|bash|dash|ash|zsh|ksh|ksh93|mksh|oksh|yash) ;;
        *) die "$nom : $hook existant est écrit pour « $interp » — le bloc du pare-feu est du shell ; chaînage manuel ($f)" ;;
    esac
}

FICS=() STATUTS=() LIGNES=()
for cible in "${cibles[@]}"; do
    nom="${cible#"$ROOT"}"; nom="${nom#/}"; [ -n "$nom" ] || nom="méta"
    h="$(dossier_hooks "$cible" "$nom")"
    for hook in pre-commit pre-push; do
        f="$h/$hook"
        statut="installé"
        if [ -e "$f" ]; then
            valider_hook "$f" "$nom" "$hook"
            [ ! -s "$f" ] || statut="chaîné après un hook existant"
            { [ ! -s "$f" ] || ! grep -qxF "$MARQUEUR" "$f"; } || statut="déjà présent"
        fi
        FICS+=("$f") STATUTS+=("$statut") LIGNES+=("  $nom : $hook $statut")
    done
done

# ── Les blocs ajoutés aux hooks ──────────────────────────────────────────────
bloc_pre_commit() {
    printf '%s\n' "$MARQUEUR" \
        "bash $(citer "$HOOKS_SRC/pre-commit-gitleaks.sh") || exit 1" \
        "bash $(citer "$HOOKS_SRC/check-author.sh") || exit 1"
}
bloc_pre_push() {
    printf '%s\n' "$MARQUEUR" \
        "bash $(citer "$HOOKS_SRC/pre-push-oss-guard.sh") || exit 1"
}
# Variante quand un hook existe déjà : il lira peut-être l'entrée standard
# après nous. Elle est mise de côté pour la garde, puis rendue au hook.
# Les lignes entre apostrophes sont du code écrit tel quel dans le hook.
# shellcheck disable=SC2016
bloc_pre_push_chaine() {
    printf '%s\n' "$MARQUEUR" \
        "# L'entrée standard est mise de côté : la garde la lit, puis le hook existant la retrouve." \
        '__oss_stdin="$(mktemp "${TMPDIR:-/tmp}/oss-guard.XXXXXX")" && cat > "$__oss_stdin" || exit 1' \
        "bash $(citer "$HOOKS_SRC/pre-push-oss-guard.sh") < \"\$__oss_stdin\" || { rm -f \"\$__oss_stdin\"; exit 1; }" \
        'exec 0< "$__oss_stdin"' \
        'rm -f "$__oss_stdin"'
}

# ecrire_hook <fichier> <bloc> : crée le hook, ou insère le bloc en tête du
# hook existant (après son shebang), sans toucher à ses lignes.
ecrire_hook() {
    local f="$1" bloc="$2" premiere tmp="$1.install-hooks.tmp"
    if [ -s "$f" ]; then
        premiere="$(head -n 1 "$f")"
        {
            case "$premiere" in '#!'*) printf '%s\n' "$premiere" ;; esac
            printf '%s\n' "$bloc"
            echo
            case "$premiere" in '#!'*) tail -n +2 "$f" ;; *) cat "$f" ;; esac
        } > "$tmp"
        chmod --reference="$f" "$tmp" 2>/dev/null || chmod 755 "$tmp"
    else
        { echo '#!/usr/bin/env bash'; printf '%s\n' "$bloc"; } > "$tmp"
        chmod 755 "$tmp"
    fi
    mv -f "$tmp" "$f"
    chmod +x "$f"
}

# ── Écriture ─────────────────────────────────────────────────────────────────
for k in "${!FICS[@]}"; do
    [ "${STATUTS[$k]}" != "déjà présent" ] || continue
    f="${FICS[$k]}"
    if [ "${STATUTS[$k]}" = "chaîné après un hook existant" ] && [ "${f##*/}" = pre-push ]; then
        bloc="$(bloc_pre_push_chaine)"
    elif [ "${f##*/}" = pre-push ]; then
        bloc="$(bloc_pre_push)"
    else
        bloc="$(bloc_pre_commit)"
    fi
    mkdir -p "$(dirname "$f")"
    ecrire_hook "$f" "$bloc"
done

printf '%s\n' "${LIGNES[@]}"
echo "✅ pare-feu installé : ${#FICS[@]} hooks"
