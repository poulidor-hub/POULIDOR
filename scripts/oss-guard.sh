#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# oss-guard.sh — refuse les valeurs interdites (données client, IP, hôtes,
# identités) dans les arbres et dans ce que des commits apportent.
#
# Open source — filet de sécurité.
#
# Usage :
#   oss-guard.sh scan-tree  <fichier-motifs> [<racine>]
#       cherche les motifs dans les fichiers suivis de <racine> (défaut : .) :
#       leur contenu et leurs chemins — le nom d'un fichier ou d'un dossier
#       suffit à identifier un client ou un outil privé.
#   oss-guard.sh scan-range <fichier-motifs> <plage> [<racine>]
#       cherche les motifs dans les commits de <plage> — toute plage que
#       `git log` comprend ; `<commit>^!` pour un seul commit —, limité à ce
#       qu'ils apportent : lignes ajoutées des correctifs, messages de commit,
#       chemins ajoutés ou renommés. Les lignes retirées et de contexte ne sont
#       pas examinées : un commit de nettoyage ne doit pas être bloqué par les
#       valeurs qu'il retire.
#
# Le fichier de motifs tient une expression rationnelle étendue par ligne ;
# lignes vides et commentaires (#) ignorés. Il reste local : son contenu n'est
# jamais affiché. Aucune ligne correspondante n'est affichée en entier : seul
# un extrait masqué l'est (toutes les valeurs interdites y sont masquées, de
# même que les adresses IP et les adresses e-mail).
#
# Codes de sortie : 0 rien ; 1 au moins une correspondance ; 2 fichier de
# motifs absent, vide ou inutilisable.
#
# Test : scripts/tests/test_oss_guard.sh
set -euo pipefail

usage() { awk 'NR>3 && /^set /{exit} NR>3{sub(/^# ?/,""); print}' "$0"; }
sortir2() { echo "oss-guard : $*" >&2; exit 2; }
# Lance une commande sans que set -e arrête le script ; renseigne RC.
sans_e() { set +e; "$@"; RC=$?; set -e; }
# valide <motif> : 0 si le motif accepte la chaîne vide (il correspondrait à
# tout), 2 si l'expression est incorrecte, 1 sinon.
# (appelée à travers sans_e : shellcheck la croit hors d'atteinte)
# shellcheck disable=SC2317
valide() { printf '\n' | grep -qE -e "$1"; }

MAX_RAPPORTS=50      # au-delà, les correspondances sont comptées, pas listées

# ── Arguments ────────────────────────────────────────────────────────────────
mode="${1:-}"
fichier="${2:-}"
racine="."
case "$mode" in
    scan-tree)
        if [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; then usage >&2; sortir2 "usage : oss-guard.sh scan-tree <fichier-motifs> [<racine>]"; fi
        if [ "$#" -eq 3 ]; then racine="$3"; fi ;;
    scan-range)
        if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then usage >&2; sortir2 "usage : oss-guard.sh scan-range <fichier-motifs> <plage> [<racine>]"; fi
        if [ "$#" -eq 4 ]; then racine="$4"; fi ;;
    *)
        usage >&2; sortir2 "mode inconnu ou absent : « ${mode} »" ;;
esac

tmp="$(mktemp -d "${TMPDIR:-/tmp}/oss-guard.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# ── Le fichier de motifs : une expression rationnelle par ligne ──────────────
# NUMS : ligne du fichier (jamais le motif, qui reste local) ; MOTIFS : expression.
[ -f "$fichier" ] || sortir2 "fichier de motifs absent : $fichier"
NUMS=() MOTIFS=() TOUS=()
n=0
while IFS= read -r ligne || [ -n "$ligne" ]; do
    n=$((n + 1))
    ligne="${ligne#"${ligne%%[![:space:]]*}"}"     # blancs de tête
    case "$ligne" in
        '') ;;
        '#'*) ;;
        *) NUMS+=("$n"); MOTIFS+=("$ligne") ;;
    esac
done < "$fichier"
[ "${#MOTIFS[@]}" -gt 0 ] || sortir2 "fichier de motifs sans aucune expression : $fichier"
for i in "${!MOTIFS[@]}"; do
    TOUS+=(-e "${MOTIFS[$i]}")
    sans_e valide "${MOTIFS[$i]}"
    if [ "$RC" -gt 1 ]; then sortir2 "motif n°${NUMS[$i]} invalide (expression rationnelle incorrecte) — $fichier"; fi
    if [ "$RC" -eq 0 ]; then sortir2 "motif n°${NUMS[$i]} accepte la chaîne vide : il correspondrait à tout — $fichier"; fi
done

# ── Extraits masqués ─────────────────────────────────────────────────────────
# delimiteur <motif> : un délimiteur d'expression sed absent du motif.
delimiteur() {
    local d
    for d in '|' '#' '~' '%' '!' ';' ',' '@' '^' '&'; do
        case "$1" in *"$d"*) ;; *) printf '%s' "$d"; return 0 ;; esac
    done
    printf '/'
}
# expr_sed <motif> <remplacement> : l'expression sed qui remplace toutes les
# occurrences du motif.
expr_sed() {
    local d; d="$(delimiteur "$1")"
    if [ "$d" = / ]; then printf 's/(%s)/%s/g' "${1//\//\\/}" "$2"
    else printf 's%s(%s)%s%s%sg' "$d" "$1" "$d" "$2" "$d"; fi
}
# ecrire_masques <fichier> [rang d'un motif épargné] : le script sed qui
# masque toutes les valeurs interdites (le motif épargné devient MARQUE), puis
# les adresses IP et les adresses e-mail.
MARQUE='⟪⟪⟪'
ecrire_masques() {
    local f="$1" i="${2:-}" j
    : > "$f"
    for j in "${!MOTIFS[@]}"; do
        if [ -n "$i" ] && [ "$j" -eq "$i" ]; then
            printf '%s\n' "$(expr_sed "${MOTIFS[$j]}" "$MARQUE")" >> "$f"
        else
            printf '%s\n' "$(expr_sed "${MOTIFS[$j]}" '██')" >> "$f"
        fi
    done
    printf '%s\n' 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/██/g' 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/██/g' >> "$f"
}
# masquer <texte> : le texte où toute valeur interdite est masquée (les chemins
# affichés passent par ici : un nom de fichier peut en contenir une).
masquer() { printf '%s\n' "$1" | sed -E -f "$tmp/masques.tous"; }
ecrire_masques "$tmp/masques.tous"
# extraire <ligne> <rang du motif> [avant] [après] : un extrait borné de la
# ligne, où le motif en cause apparaît comme « ⟨motif n⟩ » et où toute autre
# valeur interdite est masquée — de même que les adresses IP et les adresses
# e-mail, qui peuvent ne pas figurer au fichier de motifs.
extraire() {
    local ligne="$1" i="$2" avant="${3:-30}" apres="${4:-40}" masquee debut fin extrait avant_marque
    if [ ! -f "$tmp/masques.$i" ]; then ecrire_masques "$tmp/masques.$i" "$i"; fi
    masquee="$(printf '%s\n' "$ligne" | sed -E -f "$tmp/masques.$i")"
    debut=0
    fin=$((avant + apres))
    if [ "${masquee#*"$MARQUE"}" != "$masquee" ]; then
        avant_marque="${masquee%%"$MARQUE"*}"
        debut=$(( ${#avant_marque} - avant ))
        [ "$debut" -ge 0 ] || debut=0
        fin=$((debut + avant + ${#MARQUE} + apres))
    fi
    [ "$fin" -le "${#masquee}" ] || fin="${#masquee}"
    extrait="${masquee:debut:fin-debut}"
    extrait="${extrait//"$MARQUE"/⟨motif ${NUMS[$i]}⟩}"
    [ "$debut" -eq 0 ] || extrait="…$extrait"
    [ "$fin" -eq "${#masquee}" ] || extrait="$extrait…"
    printf '%s' "$extrait"
}

# ── scan-tree : les fichiers suivis, contenu et chemins ───────────────────────
# chemin_de <chemin:numero:ligne> : le chemin d'une ligne de `git grep -n`.
# Un chemin peut contenir « : » : le numéro de ligne est le premier segment
# numérique suivi de « : ».
chemin_de() {
    local chemin="${1%%:*}" reste="${1#*:}"
    while ! [[ "$reste" =~ ^[0-9]+: ]] && [[ "$reste" == *:* ]]; do
        chemin="$chemin:${reste%%:*}"; reste="${reste#*:}"
    done
    printf '%s' "$chemin"
}

# rapporter_arbre <chemin:numero:ligne> <rang du motif> : une ligne de `git grep -n`.
rapporter_arbre() {
    local brut="$1" i="$2" chemin reste numero
    chemin="$(chemin_de "$brut")"; reste="${brut#"$chemin":}"
    numero="${reste%%:*}"
    printf '  %s:%s — motif n°%s — extrait : %s\n' "$(masquer "$chemin")" "$numero" "${NUMS[$i]}" \
        "$(extraire "${reste#*:}" "$i")"
}

# rapporter_chemin <chemin> <rang du motif> : un chemin suivi qui contient une
# valeur interdite.
rapporter_chemin() {
    printf '  %s — chemin suivi — motif n°%s\n' "$(extraire "$1" "$2")" "${NUMS[$2]}"
}

scan_tree() {
    local i trouve chemin total=0 rapide_contenu
    sans_e git -C "$racine" -c core.quotePath=false ls-files > "$tmp/chemins"
    [ "$RC" -eq 0 ] || sortir2 "impossible de lire les chemins suivis de « $racine » (git ls-files, code $RC)"
    # Passe rapide : rien dans le contenu ni dans les chemins → terminé.
    sans_e git -C "$racine" grep -q -I -E "${TOUS[@]}" -- .
    case "$RC" in
        0|1) rapide_contenu="$RC" ;;
        *) sortir2 "impossible de lire les fichiers suivis de « $racine » (git grep, code $RC)" ;;
    esac
    sans_e grep -q -E "${TOUS[@]}" "$tmp/chemins"
    [ "$RC" -le 1 ] || sortir2 "lecture impossible (grep, code $RC)"
    if [ "$rapide_contenu" -eq 1 ] && [ "$RC" -eq 1 ]; then
        echo "✅ oss-guard : aucune valeur interdite dans les fichiers suivis (${#MOTIFS[@]} motifs)."
        return 0
    fi
    for i in "${!MOTIFS[@]}"; do
        sans_e git -C "$racine" -c core.quotePath=false grep -n -I -E -e "${MOTIFS[$i]}" -- . > "$tmp/arbre"
        [ "$RC" -le 1 ] || sortir2 "impossible de lire les fichiers suivis de « $racine » (git grep, code $RC)"
        while IFS= read -r trouve; do
            total=$((total + 1))
            [ "$total" -gt "$MAX_RAPPORTS" ] || rapporter_arbre "$trouve" "$i"
        done < "$tmp/arbre"
        sans_e grep -E -e "${MOTIFS[$i]}" "$tmp/chemins" > "$tmp/chemins.trouves"
        [ "$RC" -le 1 ] || sortir2 "lecture impossible (grep, code $RC)"
        while IFS= read -r chemin; do
            total=$((total + 1))
            [ "$total" -gt "$MAX_RAPPORTS" ] || rapporter_chemin "$chemin" "$i"
        done < "$tmp/chemins.trouves"
    done
    if [ "$total" -gt "$MAX_RAPPORTS" ]; then echo "  … et $((total - MAX_RAPPORTS)) autres, non listées."; fi
    if [ "$total" -eq 0 ]; then
        echo "✅ oss-guard : aucune valeur interdite dans les fichiers suivis (${#MOTIFS[@]} motifs)."
        return 0
    fi
    echo "✗ oss-guard : $total correspondance(s) de valeurs interdites dans les fichiers suivis."
    return 1
}

# ── scan-range : ce que les commits apportent ────────────────────────────────
# rapporter <contenu> <métadonnées> <rang du motif>. Métadonnées, séparées par
# des tabulations : M (message), A (ligne ajoutée) — commit, chemin, numéro de
# ligne ; CA, CR (chemin ajouté, renommé) — commit.
rapporter() {
    local contenu="$1" meta="$2" i="$3"
    local genre commit chemin numero
    IFS=$'\t' read -r genre commit chemin numero <<< "$meta"
    case "$genre" in
        M)  printf '  commit %s — message de commit (ligne %s) — motif n°%s — extrait : %s\n' \
                "${commit:0:7}" "$numero" "${NUMS[$i]}" "$(extraire "$contenu" "$i")" ;;
        A)  printf '  commit %s — %s:%s — motif n°%s — extrait : %s\n' \
                "${commit:0:7}" "$(masquer "$chemin")" "$numero" "${NUMS[$i]}" "$(extraire "$contenu" "$i")" ;;
        CA) printf '  commit %s — chemin ajouté : %s — motif n°%s\n' \
                "${commit:0:7}" "$(extraire "$contenu" "$i" 80 100)" "${NUMS[$i]}" ;;
        CR) printf '  commit %s — chemin renommé : %s — motif n°%s\n' \
                "${commit:0:7}" "$(extraire "$contenu" "$i" 80 100)" "${NUMS[$i]}" ;;
    esac
}

# commits_concernes : nombre de commits distincts qui ont une correspondance.
# numeros.<fichier> tient les numéros des lignes trouvées ; la métadonnée (et
# donc le commit) est à la ligne précédente du fichier de paires.
commits_concernes() {
    local paires
    for paires in lignes chemins; do
        awk 'NR == FNR { voulu[$1] = 1; next } (FNR + 1) in voulu { print $2 }' \
            "$tmp/numeros.$paires" "$tmp/$paires"
    done | sort -u | wc -l
}

scan_range() {
    local plage="$1" i paires trouve n total=0 nb
    : > "$tmp/lignes"; : > "$tmp/chemins"
    : > "$tmp/numeros.lignes"; : > "$tmp/numeros.chemins"

    # 1. Un seul `git log` produit le flux brut : par commit, son message
    #    encadré par deux marqueurs, puis son correctif (sans contexte ; pour
    #    une fusion, l'écart à son premier parent : ce qu'elle amène elle-même).
    sans_e git -C "$racine" -c core.quotePath=false log --reverse --no-color --no-ext-diff --unified=0 \
        --diff-merges=first-parent -M --output="$tmp/brut" \
        --format=$'@@OSS-COMMIT %H\n@@OSS-MESSAGE\n%B@@OSS-FIN-MESSAGE' --patch "$plage"
    [ "$RC" -eq 0 ] || sortir2 "plage illisible : « $plage » (git log, code $RC)"
    sans_e git -C "$racine" -c core.quotePath=false log --reverse --no-color --name-status -M \
        --diff-merges=first-parent --output="$tmp/noms" --format='@@OSS-COMMIT %H' "$plage"
    [ "$RC" -eq 0 ] || sortir2 "plage illisible : « $plage » (git log, code $RC)"
    nb="$(grep -c '^@@OSS-COMMIT ' "$tmp/brut" || true)"

    # 2. awk — qui ne connaît pas les motifs — ne garde, par paires
    #    « métadonnées / contenu », que ce qui est examiné : lignes ajoutées,
    #    messages, chemins ajoutés ou renommés. Le contenu est seul sur sa
    #    ligne : une expression ancrée y garde le même sens que dans un fichier.
    awk -v lignes="$tmp/lignes" '
        { avant = precedent; precedent = $0 }
        /^@@OSS-COMMIT /      { commit = substr($0, 14); etat = "r"; next }
        /^@@OSS-MESSAGE$/     { etat = "m"; numero = 0; next }
        /^@@OSS-FIN-MESSAGE$/ { etat = "r"; next }
        {
            if (etat == "m") {
                if ($0 == "") next
                numero++
                printf "M\t%s\t-\t%d\n%s\n", commit, numero, $0 > lignes
                next
            }
            # En-tête « +++ » : seulement après une ligne « --- » ou « diff --git ».
            # Une ligne ajoutée dont le contenu commence par « ++ » reste une ligne.
            if ($0 ~ /^\+\+\+ / && avant ~ /^(--- |diff --git )/) {
                chemin = $0; sub(/^\+\+\+ [ab]\//, "", chemin); next
            }
            if ($0 ~ /^@@ /) {
                if (match($0, /\+[0-9]+/)) numero = substr($0, RSTART + 1, RLENGTH - 1) + 0
                next
            }
            if ($0 ~ /^\+/) {
                printf "A\t%s\t%s\t%d\n%s\n", commit, chemin, numero, substr($0, 2) > lignes
                numero++
                next
            }
        }
    ' "$tmp/brut"
    awk -F '\t' -v chemins="$tmp/chemins" '
        /^@@OSS-COMMIT / { commit = substr($0, 14); next }
        /^R/ { printf "CR\t%s\t-\t-\n%s\n", commit, $3 > chemins; next }
        /^A/ { printf "CA\t%s\t-\t-\n%s\n", commit, $2 > chemins; next }
    ' "$tmp/noms"

    # 3. Une passe rapide, puis motif par motif — pour le numéro de motif.
    sans_e grep -q -E "${TOUS[@]}" "$tmp/lignes"
    local rapide_l=$RC
    sans_e grep -q -E "${TOUS[@]}" "$tmp/chemins"
    local rapide_c=$RC
    if [ "$rapide_l" -eq 1 ] && [ "$rapide_c" -eq 1 ]; then
        echo "✅ oss-guard : rien d'interdit dans $nb commit(s) examiné(s) (plage « $plage »)."
        return 0
    fi
    for i in "${!MOTIFS[@]}"; do
        for paires in lignes chemins; do
            sans_e grep -n -E -e "${MOTIFS[$i]}" "$tmp/$paires" > "$tmp/trouves"
            [ "$RC" -le 1 ] || sortir2 "lecture impossible (grep, code $RC)"
            while IFS= read -r trouve; do
                n="${trouve%%:*}"
                [ $((n % 2)) -eq 0 ] || continue     # ligne impaire : métadonnées
                total=$((total + 1))
                echo "$n" >> "$tmp/numeros.$paires"
                [ "$total" -le "$MAX_RAPPORTS" ] || continue
                rapporter "${trouve#*:}" "$(sed -n "$((n - 1))p" "$tmp/$paires")" "$i"
            done < "$tmp/trouves"
        done
    done
    if [ "$total" -eq 0 ]; then     # la passe rapide avait vu des métadonnées
        echo "✅ oss-guard : rien d'interdit dans $nb commit(s) examiné(s) (plage « $plage »)."
        return 0
    fi
    if [ "$total" -gt "$MAX_RAPPORTS" ]; then echo "  … et $((total - MAX_RAPPORTS)) autres, non listées."; fi
    # Commits distincts concernés, sur TOUTES les correspondances (une passe par fichier).
    nb="$(commits_concernes)"
    echo "✗ oss-guard : $total correspondance(s) de valeurs interdites dans $nb commit(s) (plage « $plage »)."
    return 1
}

# ── Exécution ────────────────────────────────────────────────────────────────
if [ "$mode" = scan-tree ]; then
    if scan_tree; then exit 0; else exit 1; fi
else
    if scan_range "$3"; then exit 0; else exit 1; fi
fi
