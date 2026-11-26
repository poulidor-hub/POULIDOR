#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# publish-public.sh — publie les mains privées du parc vers les dépôts publics.
#
# Open source — la copie publique doit suivre la copie privée, sans oubli et
# sans rebase. Tout le pré-vol passe avant tout push : un refus sur un dépôt,
# aucun push nulle part.
#
# Usage :
#   publish-public.sh [--yes] [--verify] [--only <nom>…] [--root <dir>]
#       sans --yes : dry-run — RIEN n'est poussé, mais tout est vérifié :
#       les pré-vols, et la régénération de l'adaptation du méta dans un
#       worktree jetable, qui prouve qu'elle est faisable.
#       --yes    : publier.
#       --verify : après le push, clone anonyme du méta public et
#                 vérifications — sous-modules résolus, aucune URL ssh,
#                 VERSION affichée.
#       --only   : restreindre aux dépôts nommés — nom interne ou public ;
#                 le méta reste en dernier.
#       --root   : racine du checkout parc (défaut : toplevel du dépôt du
#                 script), lue pour amorcer les clones de publication
#                 manquants.
#
# Clones de publication, $PUBLISH_DIR/<dir> : origin = dépôt privé, public =
# dépôt publique. Un clone absent est créé depuis l'URL privée lue dans le
# checkout parc : git -C <root>/<dir> remote get-url origin (<root> pour le
# méta). Un remote public absent est ajouté ; un remote public différent
# arrête tout.
#
# Publication — composants d'abord, méta EN DERNIER (ses gitlinks
# référencent des commits qui doivent exister publiquement) :
#   composant : public/main = origin/main, et les tags du privé (un tag
#               recréé côté privé remplace celui du public) ;
#   méta      : origin/main + un commit d'adaptation, qui réécrit dans
#               .gitmodules et manifest.json l'URL de chaque composant vers
#               l'org publique. Le nom du dépôt privé est le basename de
#               l'URL origin du clone de publication : aucune organisation
#               privée n'est écrite dans ce script. Ce commit est RÉGÉNÉRÉ à
#               chaque exécution, jamais rebasé ; s'il n'y a rien à
#               réécrire, origin/main est poussé tel quel.
#
# Refus (rien n'est poussé) si :
#   - le public porte des commits étrangers : composant, tout commit absent
#     du privé ; méta, tout commit dont le sujet ne commence pas par
#     « chore: URLs publiques » ;
#   - la garde oss-guard (scripts/oss-guard.sh scan-range, sur la plage à
#     publier) trouve une valeur interdite, ou ne peut pas analyser —
#     fichier de motifs absent, vide ou inutilisable ;
#   - un dépôt est injoignable, un clone ou un remote dérive ;
#   - l'adaptation laisse, dans .gitmodules ou manifest.json, une URL ssh
#     (git@), une ligne « url = » hors de l'org publique, ou une adresse
#     github.com autre que celle de l'org publique.
# En cours de push, un dépôt qui échoue arrête tout : les suivants — le méta
# en particulier — ne sont pas poussés. Le commit d'adaptation d'un dry-run
# reste un objet sans référence du clone de publication du méta (purgé par gc).
#
# Environnement :
#   PUBLISH_DIR         (déf. ~/publish)
#   PUBLIC_SSH_BASE     (déf. git@github.com:poulidor-hub)
#   PUBLIC_HTTPS_BASE   (déf. https://github.com/poulidor-hub)
#   PUBLISH_MAP         lignes « <dir> <nom_public> <role> », role =
#                       component | meta (déf. : les 7 dépôts du parc)
#   OSS_FORBIDDEN_FILE  fichier de motifs de la garde
#                       (déf. ~/.config/poulidor/oss-forbidden.txt)
#
# Codes de sortie : 0 OK ; 1 refus ou anomalie ; 2 usage.
#
# Test : scripts/tests/test_publish_public.sh
set -euo pipefail

export GIT_TERMINAL_PROMPT=0     # jamais d'invite : un dépôt qui réclame un identifiant échoue

# ── Messages ─────────────────────────────────────────────────────────────────
usage() { awk 'NR>3 && /^set /{exit} NR>3{sub(/^# ?/,""); print}' "$0"; }
info()  { echo "→ $*"; }
ok()    { echo "✅ $*"; }
refus() { echo "✗ $*" >&2; }
usage_erreur() {  # usage_erreur <motif> : l'usage et le motif, code 2
    usage >&2
    printf '\npublish-public : %s\n' "$*" >&2
    exit 2
}
# ── Arguments ────────────────────────────────────────────────────────────────
OUI=0; VERIFIER=0; ROOT=""; ONLY=()
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) OUI=1; shift ;;
        --verify) VERIFIER=1; shift ;;
        --root)
            [ $# -ge 2 ] || usage_erreur "--root nécessite un répertoire"
            ROOT="$2"; shift 2 ;;
        --only)
            shift
            while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do ONLY+=("$1"); shift; done     # les noms, jusqu'à l'option suivante
            [ "${#ONLY[@]}" -gt 0 ] || usage_erreur "--only nécessite au moins un nom (interne ou public)" ;;
        -h|--help) usage; exit 0 ;;
        *) usage_erreur "option inconnue : $1" ;;
    esac
done

# ── Environnement ────────────────────────────────────────────────────────────
PUBLISH_DIR="${PUBLISH_DIR:-$HOME/publish}"
PUBLIC_SSH_BASE="${PUBLIC_SSH_BASE:-git@github.com:poulidor-hub}"
PUBLIC_HTTPS_BASE="${PUBLIC_HTTPS_BASE:-https://github.com/poulidor-hub}"
OSS_FORBIDDEN_FILE="${OSS_FORBIDDEN_FILE:-$HOME/.config/poulidor/oss-forbidden.txt}"
PUBLIC_SSH_BASE="${PUBLIC_SSH_BASE%/}"
PUBLIC_HTTPS_BASE="${PUBLIC_HTTPS_BASE%/}"
PUBLISH_MAP="${PUBLISH_MAP:-HUB_base HUB component
HUBsocle HUBsocle component
HUBapp_TEMPLATE_base HUBapp-template component
HUBCSS HUBCSS component
hubctl_src hubctl component
hub-mcp hub-mcp component
POULIDOR POULIDOR meta}"

# ── Racine du checkout parc ──────────────────────────────────────────────────
if [ -z "$ROOT" ]; then
    dossier_script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    ROOT="$(git -C "$dossier_script" rev-parse --show-toplevel 2>/dev/null)" \
        || { refus "hors dépôt git : indiquer la racine du checkout parc (--root <dir>)."; exit 1; }
elif [ ! -d "$ROOT" ]; then
    usage_erreur "--root : répertoire introuvable : $ROOT"
fi
ROOT="$(cd "$ROOT" && pwd)"

# ── La map : <dir> <nom_public> <role> ───────────────────────────────────────
DIRS=() NOMS=() ROLES=()
n=0
while IFS= read -r ligne || [ -n "$ligne" ]; do
    n=$((n + 1))
    ligne="${ligne#"${ligne%%[![:space:]]*}"}"     # blancs de tête
    case "$ligne" in ''|'#'*) continue ;; esac
    read -r dir nom role surplus <<< "$ligne"
    if [ -z "${role:-}" ] || [ -n "${surplus:-}" ]; then
        usage_erreur "PUBLISH_MAP, ligne $n : attendu « <dir> <nom_public> <role> »"
    fi
    case "$role" in
        component|meta) ;;
        *) usage_erreur "PUBLISH_MAP, ligne $n : role « $role » inconnu (component ou meta)" ;;
    esac
    for v in "$dir" "$nom"; do
        printf '%s' "$v" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' \
            || usage_erreur "PUBLISH_MAP, ligne $n : nom « $v » invalide (lettres, chiffres, . _ -)"
    done
    DIRS+=("$dir"); NOMS+=("$nom"); ROLES+=("$role")
done <<< "$PUBLISH_MAP"
[ "${#DIRS[@]}" -gt 0 ] || usage_erreur "PUBLISH_MAP : aucune ligne"

META_RANG=""; META_DIR=""; META_NOM=""     # l'entrée méta (au plus une)
for i in "${!DIRS[@]}"; do
    for j in "${!DIRS[@]}"; do
        if [ "$j" -lt "$i" ]; then
            [ "${DIRS[$j]}" != "${DIRS[$i]}" ] || usage_erreur "PUBLISH_MAP : « ${DIRS[$i]} » apparaît deux fois"
            [ "${NOMS[$j]}" != "${NOMS[$i]}" ] || usage_erreur "PUBLISH_MAP : le nom public « ${NOMS[$i]} » est attribué deux fois"
        fi
    done
    if [ "${ROLES[$i]}" = meta ]; then
        [ -z "$META_DIR" ] || usage_erreur "PUBLISH_MAP : un seul rôle meta"
        META_RANG="$i"; META_DIR="${DIRS[$i]}"; META_NOM="${NOMS[$i]}"
    fi
done
# Ordre de publication : les composants (dans l'ordre de la map), le méta en dernier.
ORDRE=(); N_COMPOSANTS=0
for i in "${!DIRS[@]}"; do
    if [ "${ROLES[$i]}" = component ]; then ORDRE+=("$i"); N_COMPOSANTS=$((N_COMPOSANTS + 1)); fi
done
if [ -n "$META_RANG" ]; then ORDRE+=("$META_RANG"); fi

# ── Sélection (--only : nom interne ou public) ───────────────────────────────
SELECTION=()
if [ "${#ONLY[@]}" -gt 0 ]; then
    declare -A VU=()
    for nom in "${ONLY[@]}"; do
        rang=""
        for i in "${!DIRS[@]}"; do
            if [ "$nom" = "${DIRS[$i]}" ] || [ "$nom" = "${NOMS[$i]}" ]; then rang="$i"; break; fi
        done
        if [ -z "$rang" ]; then
            usage_erreur "--only : « $nom » ne correspond à aucun dépôt de la map (nom interne ou public)"
        fi
        if [ -z "${VU[$rang]:-}" ]; then VU[$rang]=1; SELECTION+=("$rang"); fi
    done
else
    SELECTION=("${ORDRE[@]}")
fi

# ── Préconditions : la garde doit pouvoir analyser, sinon rien ne commence ──
command -v git >/dev/null || { refus "git introuvable."; exit 1; }
if [ ! -f "$OSS_FORBIDDEN_FILE" ]; then
    refus "fichier de motifs absent : $OSS_FORBIDDEN_FILE — la garde OSS ne peut pas analyser ; rien n'est publié."
    exit 1
fi
if [ ! -f "$ROOT/scripts/oss-guard.sh" ]; then
    refus "garde introuvable : $ROOT/scripts/oss-guard.sh — la racine du checkout parc est-elle la bonne (--root) ?"
    exit 1
fi

# ── Répertoire de travail et worktree jetable : toujours retirés en sortant ──
TMP="$(mktemp -d "${TMPDIR:-/tmp}/publish-public.XXXXXX")"
WT=""            # worktree jetable de l'adaptation du méta
META_CHEMIN=""   # clone de publication du méta
# (handler du trap EXIT : shellcheck la croit hors d'atteinte)
# shellcheck disable=SC2317
nettoyage() {
    if [ -n "$WT" ]; then
        rm -rf "$WT"
        if [ -n "$META_CHEMIN" ] && [ -e "$META_CHEMIN" ]; then
            git -C "$META_CHEMIN" worktree prune >/dev/null 2>&1 || true
        fi
    fi
    rm -rf "$TMP"
}
trap nettoyage EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

MESSAGE_ADAPTATION='chore: URLs publiques (open source) — .gitmodules et manifest pointent poulidor-hub'
AVANT=() CIBLE=() NB=() GARDE=()     # par rang de la map : état du public, sha à publier, nombre de commits, pré-vol

# nom_de <rang> : « compA (→ pubA) »
nom_de() { printf '%s' "${DIRS[$1]} (→ ${NOMS[$1]})"; }
# liste <texte>… : les textes séparés par « , »
liste() {
    local sep="" x out=""
    for x in "$@"; do out="$out$sep$x"; sep=", "; done
    printf '%s' "${out:-aucun}"
}

# url_privee <dir> : URL de l'origine privée — celle du clone de publication
# s'il existe, sinon celle du checkout parc (<root> pour le méta).
url_privee() {
    local src="$PUBLISH_DIR/$1"
    if [ ! -e "$src" ]; then
        if [ "$1" = "$META_DIR" ]; then src="$ROOT"; else src="$ROOT/$1"; fi
    fi
    git -C "$src" remote get-url origin
}

# depot_prive <URL> : le nom du dépôt privé — le basename de l'URL, sans
# « .git ». C'est la seule chose que le script retient de l'URL privée.
depot_prive() {
    local u="${1%/}"
    u="${u##*/}"
    printf '%s' "${u%.git}"
}

# tel_quel <texte> : le texte pris à la lettre dans une expression sed
# (motif ou remplacement ; délimiteur #).
tel_quel() { printf '%s' "$1" | sed -e 's/[][\.*^$+?{}|()&#\\]/\\&/g'; }

# ── Pré-vol d'un dépôt ───────────────────────────────────────────────────────
preparer() {  # preparer <rang> : tout le pré-vol d'un dépôt ; 0 s'il est publiable
    local i="$1"
    local dir="${DIRS[$i]}" chemin="$PUBLISH_DIR/${DIRS[$i]}" url_pub="$PUBLIC_SSH_BASE/${NOMS[$i]}.git"
    local lib rc=0 url="" actuelle="" priv="" pub="" pub_vide=0 plage="" lib_plage=""
    local etrangers="" mauvais="" cible
    lib="$(nom_de "$i")"

    # 1. Clone de publication et remote « public ».
    if [ ! -e "$chemin" ]; then
        mkdir -p "$PUBLISH_DIR"
        if url="$(url_privee "$dir")"; then
            info "$lib : clone de publication absent — amorcé depuis $url"
            if ! git clone --quiet "$url" "$chemin"; then
                refus "$lib : clone de $url impossible."
                return 1
            fi
        else
            refus "$lib : clone de publication absent ($chemin) et URL privée illisible dans le checkout parc."
            return 1
        fi
    fi
    if [ "$(git -C "$chemin" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
        refus "$lib : $chemin n'est pas un dépôt git — ni cloné ni modifié."
        return 1
    fi
    if ! git -C "$chemin" remote get-url origin >/dev/null 2>&1; then
        refus "$lib : pas de remote « origin » dans $chemin."
        return 1
    fi
    actuelle="$(git -C "$chemin" remote get-url public 2>/dev/null || true)"
    if [ -z "$actuelle" ]; then
        if ! git -C "$chemin" remote add public "$url_pub"; then
            refus "$lib : impossible d'ajouter le remote « public »."
            return 1
        fi
        info "$lib : remote « public » ajouté → $url_pub"
    elif [ "$actuelle" != "$url_pub" ]; then
        refus "$lib : le remote « public » pointe ailleurs — $actuelle, attendu $url_pub (git -C $chemin remote set-url public …)."
        return 1
    fi

    # 2. Références à jour, en force sur les tags et dans cet ordre : « public »
    #    d'abord, « origin » en dernier — un tag recréé côté privé l'emporte
    #    toujours sur celui du public, y compris après un run refusé qui
    #    l'aurait déjà récupéré. Un fetch de « public » en échec n'est toléré
    #    que si le dépôt répond et est vide.
    if ! git -C "$chemin" fetch --quiet --force --tags --prune public; then
        rc=0; git -C "$chemin" ls-remote --exit-code public >/dev/null 2>&1 || rc=$?
        case "$rc" in
            2) info "$lib : dépôt public vide — première publication." ;;
            0) refus "$lib : fetch de « public » échoué alors que le dépôt public porte des références."; return 1 ;;
            *) refus "$lib : dépôt public injoignable : $url_pub"; return 1 ;;
        esac
        pub_vide=1
    fi
    if ! git -C "$chemin" fetch --quiet --force --tags origin; then
        refus "$lib : fetch de « origin » impossible."
        return 1
    fi
    if ! priv="$(git -C "$chemin" rev-parse --verify --quiet refs/remotes/origin/main)"; then
        refus "$lib : origin/main introuvable dans $chemin — branche main absente du dépôt privé ?"
        return 1
    fi
    pub="$(git -C "$chemin" rev-parse -q --verify refs/remotes/public/main 2>/dev/null || true)"
    if [ "$pub_vide" -eq 1 ]; then pub=""; fi

    # 3. Commits étrangers sur le public : ils seraient écrasés par le push forcé.
    if [ -n "$pub" ]; then
        if ! etrangers="$(git -C "$chemin" rev-list "refs/remotes/origin/main..refs/remotes/public/main")"; then
            refus "$lib : plage origin/main..public/main illisible."
            return 1
        fi
        if [ -n "$etrangers" ]; then
            if [ "${ROLES[$i]}" = component ]; then
                refus "$lib : le public porte des commits étrangers, absents du privé :"
                git -C "$chemin" log --format='      %h %s' refs/remotes/origin/main..refs/remotes/public/main >&2
                return 1
            fi
            # Méta : seuls les commits d'adaptation des publications précédentes sont attendus.
            mauvais="$(git -C "$chemin" log --format='%h %s' refs/remotes/origin/main..refs/remotes/public/main \
                | grep -v -E '^[0-9a-f]+ chore: URLs publiques' || true)"
            if [ -n "$mauvais" ]; then
                refus "$lib : le public du méta porte des commits étrangers — sujet autre que « chore: URLs publiques » :"
                printf '%s\n' "$mauvais" | sed 's/^/      /' >&2
                return 1
            fi
        fi
    fi

    # 4. Garde OSS sur ce que ce push apportera au public. Public vierge : tout
    #    l'historique — « <commit racine>..main » laisserait ce commit de côté.
    if [ -n "$pub" ]; then
        plage="$pub..$priv"; lib_plage="${pub:0:7}..${priv:0:7}"
    else
        plage="$priv"; lib_plage="tout l'historique, ${priv:0:7}"
    fi
    info "$lib : garde oss-guard — plage « $lib_plage »"
    rc=0
    bash "$ROOT/scripts/oss-guard.sh" scan-range "$OSS_FORBIDDEN_FILE" "$plage" "$chemin" || rc=$?
    case "$rc" in
        0) ;;
        1) refus "$lib : la garde oss-guard a trouvé des valeurs interdites dans la plage à publier — publication refusée."; return 1 ;;
        *) refus "$lib : la garde oss-guard n'a pas pu analyser la plage à publier (code $rc) — publication refusée."; return 1 ;;
    esac
    GARDE[i]=✓

    # 5. Ce qui sera poussé : origin/main, ou — pour le méta — origin/main plus
    #    le commit d'adaptation, régénéré dans un worktree jetable.
    if [ "$i" = "$META_RANG" ]; then
        if ! adapter "$chemin" "$priv" "$lib"; then GARDE[i]=✗; return 1; fi
        cible="$SHA_ADAPTATION"
    else
        cible="$priv"
    fi
    if [ -n "$pub" ]; then
        NB[i]="$(git -C "$chemin" rev-list --count "$pub..$cible")" || { refus "$lib : plage à publier illisible."; GARDE[i]=✗; return 1; }
    else
        NB[i]="$(git -C "$chemin" rev-list --count "$cible")" || { refus "$lib : historique illisible."; GARDE[i]=✗; return 1; }
    fi
    AVANT[i]="$pub"; CIBLE[i]="$cible"
    return 0
}

# ── Adaptation du méta ───────────────────────────────────────────────────────
adapter() {  # adapter <clone du méta> <sha d'origin/main> <libellé> : renseigne SHA_ADAPTATION ; le worktree jetable est retiré à la sortie
    local chemin="$1" priv="$2" lib="$3"
    local i url dep motif remplacement f fichiers=() lignes
    META_CHEMIN="$chemin"
    WT="$TMP/adaptation"
    if ! git -C "$chemin" worktree add --quiet --detach "$WT" "$priv"; then
        refus "$lib : worktree jetable impossible."
        return 1
    fi
    for i in "${!DIRS[@]}"; do
        if [ "${ROLES[$i]}" != component ]; then continue; fi
        if ! url="$(url_privee "${DIRS[$i]}")"; then
            refus "$lib : URL privée du composant ${DIRS[$i]} illisible — ni clone de publication ($PUBLISH_DIR/${DIRS[$i]}) ni checkout parc ($ROOT/${DIRS[$i]})."
            return 1
        fi
        dep="$(depot_prive "$url")"
        printf -v motif '(git@github\.com:|https://github\.com/)[^/"\x27]+/%s\.git' "$(tel_quel "$dep")"
        remplacement="$(tel_quel "$PUBLIC_HTTPS_BASE/${NOMS[$i]}.git")"
        for f in .gitmodules manifest.json; do
            if [ -f "$WT/$f" ]; then
                if ! sed -E -i "s#${motif}#${remplacement}#g" "$WT/$f"; then
                    refus "$lib : réécriture de $f impossible."
                    return 1
                fi
            fi
        done
    done

    # Post-contrôles : plus rien de privé ne doit rester dans les deux fichiers.
    for f in .gitmodules manifest.json; do
        if [ -f "$WT/$f" ]; then fichiers+=("$f"); fi
    done
    if [ "${#fichiers[@]}" -gt 0 ]; then
        lignes="$(cd "$WT" || exit 1; grep -n 'git@' "${fichiers[@]}" || true)"
        if [ -n "$lignes" ]; then
            refus "$lib : l'adaptation laisse une URL ssh (git@) — une forme que la réécriture ne connaît pas :"
            printf '%s\n' "$lignes" | sed 's/^/      /' >&2
            return 1
        fi
        if [ -f "$WT/.gitmodules" ]; then
            lignes="$(cd "$WT" && awk -v base="$PUBLIC_HTTPS_BASE/" '
                /^[ \t]*url[ \t]*=/ {
                    v = $0
                    sub(/^[ \t]*url[ \t]*=[ \t]*/, "", v); sub(/^"/, "", v); sub(/"$/, "", v)
                    if (index(v, base) != 1) printf "%s:%d : %s\n", FILENAME, FNR, v
                }' .gitmodules)"
            if [ -n "$lignes" ]; then
                refus "$lib : l'adaptation laisse dans .gitmodules une ligne « url = » qui ne commence pas par l'org publique ($PUBLIC_HTTPS_BASE/) :"
                printf '%s\n' "$lignes" | sed 's/^/      /' >&2
                return 1
            fi
        fi
        # L'org publique retirée, plus aucune adresse github.com ne doit rester :
        # ce serait une URL privée — composant hors map, URL sans .git.
        lignes="$(cd "$WT" && awk -v base="$PUBLIC_HTTPS_BASE/" '
            {
                reste = $0
                while ((k = index(reste, base)) > 0) reste = substr(reste, 1, k - 1) substr(reste, k + length(base))
                if (reste ~ /github\.com/) printf "%s:%d : %s\n", FILENAME, FNR, reste
            }' "${fichiers[@]}")"
        if [ -n "$lignes" ]; then
            refus "$lib : l'adaptation laisse une adresse github.com autre que l'org publique ($PUBLIC_HTTPS_BASE) :"
            printf '%s\n' "$lignes" | sed 's/^/      /' >&2
            return 1
        fi
    fi

    if git -C "$WT" diff --quiet; then
        info "$lib : rien à réécrire — origin/main sera poussé tel quel."
        SHA_ADAPTATION="$priv"
        return 0
    fi
    for f in "${fichiers[@]}"; do
        if ! git -C "$WT" add -- "$f"; then
            refus "$lib : ajout de $f à l'index impossible."
            return 1
        fi
    done
    if ! git -C "$WT" commit --quiet -m "$MESSAGE_ADAPTATION"; then
        refus "$lib : commit d'adaptation impossible — identité git non configurée, ou hook refusé ?"
        return 1
    fi
    if ! SHA_ADAPTATION="$(git -C "$WT" rev-parse HEAD)"; then
        refus "$lib : sha du commit d'adaptation illisible."
        return 1
    fi
    info "$lib : adaptation régénérée — commit ${SHA_ADAPTATION:0:7} « $MESSAGE_ADAPTATION »."
    return 0
}

# ── Plan ─────────────────────────────────────────────────────────────────────
afficher_plan() {
    local i avant apres
    if [ "$OUI" -eq 1 ]; then
        echo "Plan de publication :"
    else
        echo "Plan de publication — DRY-RUN : rien n'est poussé (relancer avec --yes pour publier) :"
    fi
    printf '  %-26s %-30s %8s  %s\n' "dépôt" "public avant → après" "commits" "garde"
    for i in "${SELECTION[@]}"; do
        avant="—"; apres="—"
        if [ -n "${CIBLE[$i]:-}" ]; then
            if [ -z "${AVANT[$i]:-}" ]; then avant="(vide)"; else avant="${AVANT[$i]:0:7}"; fi
            apres="${CIBLE[$i]:0:7}"
            if [ "${CIBLE[$i]}" = "${AVANT[$i]:-}" ]; then apres="$apres (inchangé)"; fi
        fi
        printf '  %-26s %-30s %8s  %s\n' "${DIRS[$i]} → ${NOMS[$i]}" "$avant → $apres" "${NB[$i]:-—}" "${GARDE[$i]:-✗}"
    done
}

# ── Push ─────────────────────────────────────────────────────────────────────
publier() {  # publier <rang> : 0 si le dépôt est poussé et que le distant rend le sha attendu
    local i="$1" chemin="$PUBLISH_DIR/${DIRS[$1]}" cible="${CIBLE[$1]}" lointain lib
    lib="$(nom_de "$i")"
    if ! git -C "$chemin" push --quiet --force public "$cible:refs/heads/main"; then
        refus "$lib : push de la branche main vers « public » refusé ou impossible."
        return 1
    fi
    if ! git -C "$chemin" push --quiet --force public --tags; then
        refus "$lib : push des tags vers « public » refusé ou impossible."
        return 1
    fi
    if ! lointain="$(git -C "$chemin" ls-remote public refs/heads/main | cut -f1)"; then
        refus "$lib : public/main illisible après le push."
        return 1
    fi
    if [ "$lointain" != "$cible" ]; then
        refus "$lib : public/main vaut ${lointain:-rien} après le push, ${cible:0:7} attendu."
        return 1
    fi
    info "$lib : publié — public/main = ${cible:0:7}."
    return 0
}

# ── Vérification (runbook) : le méta public vu d'un utilisateur anonyme ──────
verifier() {
    local v="$TMP/verif" url statut n f fichiers=()
    if [ -z "$META_DIR" ]; then
        info "vérification : pas de méta dans la map — rien à vérifier."
        return 0
    fi
    url="$PUBLIC_HTTPS_BASE/$META_NOM.git"
    info "vérification : clone anonyme de $url, sous-modules compris."
    # credential.helper vidé : un identifiant enregistré ne doit pas masquer un dépôt qui ne serait pas public.
    if ! git -c credential.helper= clone --quiet --recurse-submodules "$url" "$v" </dev/null; then
        refus "vérification : le clone anonyme du méta public a échoué — dépôt ou sous-module inaccessible sans identifiant, ou commit de sous-module absent du public."
        return 1
    fi
    if ! statut="$(git -C "$v" submodule status 2>&1)"; then
        refus "vérification : git submodule status a échoué : $statut"
        return 1
    fi
    n="$(printf '%s' "$statut" | grep -c . || true)"
    if [ "$n" -ne "$N_COMPOSANTS" ]; then
        refus "vérification : $n sous-module(s) initialisé(s), $N_COMPOSANTS attendu(s) :"
        printf '%s\n' "$statut" | sed 's/^/      /' >&2
        return 1
    fi
    if printf '%s\n' "$statut" | grep -q '^[-+U]'; then
        refus "vérification : un sous-module au moins n'est pas au commit attendu (- non initialisé, + décalé, U en conflit) :"
        printf '%s\n' "$statut" | sed 's/^/      /' >&2
        return 1
    fi
    for f in .gitmodules manifest.json; do
        if [ -f "$v/$f" ]; then fichiers+=("$v/$f"); fi
    done
    if [ "${#fichiers[@]}" -gt 0 ] && grep -n 'git@' "${fichiers[@]}"; then
        refus "vérification : une URL ssh (git@) subsiste dans le méta public."
        return 1
    fi
    if [ ! -f "$v/VERSION" ]; then
        refus "vérification : fichier VERSION absent du méta public."
        return 1
    fi
    echo "VERSION du méta public : $(tr -d '[:space:]' < "$v/VERSION")"
    ok "vérification : $N_COMPOSANTS sous-module(s) résolu(s), aucune URL ssh dans .gitmodules ni manifest.json."
    return 0
}

# ── Exécution ────────────────────────────────────────────────────────────────
if [ "$OUI" -eq 1 ]; then
    echo "publish-public : publication des mains privées vers l'org publique ($PUBLIC_SSH_BASE)."
else
    echo "publish-public : DRY-RUN — rien n'est poussé ; ajouter --yes pour publier."
    if [ "$VERIFIER" -eq 1 ]; then info "--verify s'applique après un push : ignoré en dry-run."; fi
fi
info "racine du checkout parc : $ROOT ; clones de publication : $PUBLISH_DIR"

# Tout le pré-vol passe avant tout push : un refus, aucun push nulle part.
REFUSES=0
for i in "${SELECTION[@]}"; do
    set +e; preparer "$i"; RC=$?; set -e     # un pré-vol qui échoue est un refus, pas un arrêt
    if [ "$RC" -ne 0 ]; then REFUSES=$((REFUSES + 1)); GARDE[i]=✗; fi
done

echo ""
afficher_plan

if [ "$REFUSES" -ne 0 ]; then
    refus "$REFUSES dépôt(s) refusé(s) en pré-vol — rien n'a été poussé, nulle part."
    exit 1
fi
if [ "$OUI" -eq 0 ]; then
    ok "dry-run terminé : le plan est publiable, rien n'a été poussé — relancer avec --yes."
    exit 0
fi

# Composants d'abord, méta en dernier. Un push qui échoue arrête tout : ce qui
# suit — le méta en particulier — n'est pas poussé.
PUBLIES=() RESTENT=()
arret=0
for i in "${SELECTION[@]}"; do
    if [ "$arret" -eq 1 ]; then RESTENT+=("$(nom_de "$i")"); continue; fi
    set +e; publier "$i"; RC=$?; set -e
    if [ "$RC" -eq 0 ]; then PUBLIES+=("$(nom_de "$i")"); else arret=1; RESTENT+=("$(nom_de "$i")"); fi
done
if [ "$arret" -eq 1 ]; then
    refus "publication interrompue — publié(s) : $(liste "${PUBLIES[@]}") ; non publié(s) : $(liste "${RESTENT[@]}")."
    exit 1
fi
ok "${#PUBLIES[@]} dépôt(s) publié(s) : $(liste "${PUBLIES[@]}")."

if [ "$VERIFIER" -eq 1 ]; then
    set +e; verifier; RC=$?; set -e
    if [ "$RC" -ne 0 ]; then
        refus "vérification échouée — le méta public est publié, mais ne répond pas au runbook."
        exit 1
    fi
fi
exit 0
