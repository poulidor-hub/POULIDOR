#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_oss_guard.sh — régression : oss-guard.sh (scan-tree, scan-range) et le
# hook pre-push refusent toute valeur interdite, sans jamais l'afficher.
#
# Open source — filet de sécurité : une valeur du client qui reparaît dans un
# fichier suivi, un chemin ou un message de commit recrée une fuite.
#
# scan-tree examine les fichiers suivis, contenu et chemins ; scan-range n'examine
# que ce que les commits apportent (lignes ajoutées, messages, chemins ajoutés ou
# renommés) : un commit qui se contente de RETIRER une valeur ne doit pas être
# bloqué. Aucune ligne correspondante n'est jamais affichée en entier.
#
# Toutes les valeurs interdites de ce test sont factices.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
GARDE="$SCRIPTS/oss-guard.sh"
HOOK="$SCRIPTS/hooks/pre-push-oss-guard.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-oss-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

if [ ! -f "$GARDE" ] || [ ! -f "$HOOK" ]; then
    fail "scripts/oss-guard.sh ou scripts/hooks/pre-push-oss-guard.sh absent"
fi

# ── Valeurs interdites et fichier de motifs (tout est factice) ───────────────
LITTERAL='INTERDIT-CLIENT-FICTIF-7F3A'
REGEX_VALEUR='interdit_hote_fictif42'          # acceptée par le motif de la ligne 6
MOTIFS="$TMP/motifs.txt"
cat > "$MOTIFS" <<EOF
# Motifs de test : une expression rationnelle étendue par ligne.
$LITTERAL
   # commentaire indenté ; les lignes vides et les commentaires sont ignorés


interdit[-_]hote[-_]fictif[0-9]{2}
EOF
: > "$TMP/vide.txt"                            # fichier de motifs vide
ABSENT="$TMP/jamais-cree.txt"                  # fichier de motifs absent
NUL="0000000000000000000000000000000000000000"

# ── Dépôt de fixture ─────────────────────────────────────────────────────────
R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" config user.email test@example.org
git -C "$R" config user.name test
commit() {  # commit <message> : commit de tout le répertoire de travail ; CIBLE reçoit le sha
    git -C "$R" add -A
    git -C "$R" commit -q -m "$1"
    CIBLE="$(git -C "$R" rev-parse HEAD)"
}

run_garde() {  # run_garde <mode> <motifs> [arguments…] : depuis le dépôt ; renseigne RC et OUT
    set +e
    OUT="$(cd "$R" && bash "$GARDE" "$@" 2>&1)"; RC=$?
    set -e
}
run_hook() {  # run_hook <fichier de motifs> <lignes de l'entrée standard…> : RC et OUT
    local motifs="$1"; shift
    set +e
    OUT="$(cd "$R" && printf '%s\n' "$@" | OSS_FORBIDDEN_FILE="$motifs" bash "$HOOK" 2>&1)"; RC=$?
    set -e
}
rien_fuit() {  # rien_fuit <libellé> : ni la valeur interdite ni sa variante n'apparaissent dans la sortie
    local v
    for v in "$LITTERAL" "$REGEX_VALEUR"; do
        if printf '%s\n' "$OUT" | grep -qF -- "$v"; then fail "$1 : la valeur interdite apparaît en clair dans la sortie"; fi
    done
}
doit_refuser() {  # doit_refuser <libellé> [fragment attendu…] : code 1, rien ne fuit
    local libelle="$1" f; shift
    echo "$libelle : rc=$RC"; echo "$OUT"
    [ "$RC" -eq 1 ] || fail "$libelle : la garde rend $RC au lieu de 1"
    rien_fuit "$libelle"
    for f in "$@"; do
        printf '%s\n' "$OUT" | grep -qF -- "$f" || fail "$libelle : sortie sans « $f »"
    done
}
doit_accepter() {  # doit_accepter <libellé>
    echo "$1 : rc=$RC"; echo "$OUT"
    [ "$RC" -eq 0 ] || fail "$1 : la garde rend $RC au lieu de 0"
    rien_fuit "$1"
}

echo propre > "$R/base.txt"
commit "init"

# ══ scan-tree et scan-range, commit par commit ════════════════════════════════

# ── 1. un littéral interdit dans un fichier ──────────────────────────────────
printf 'hote = %s ; port = 443\n' "$LITTERAL" > "$R/serveur.txt"
commit "ajout serveur"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "1 scan-range, commit fautif" "serveur.txt:1" "motif n°2" "hote ="
run_garde scan-tree "$MOTIFS"
doit_refuser "1 scan-tree" "serveur.txt:1" "motif n°2" "hote ="
pass "1 littéral interdit dans un fichier : scan-range et scan-tree refusent (fichier, ligne, motif, extrait masqué)"

# ── 2. un commit propre ──────────────────────────────────────────────────────
echo propre > "$R/propre.txt"
commit "propre"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_accepter "2 scan-range, commit propre"
pass "2 commit propre : scan-range accepte"

# ── 3. un littéral dans le seul message de commit ────────────────────────────
echo Encore >> "$R/base.txt"
commit "message qui cite $LITTERAL"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "3 scan-range, message fautif" "message de commit" "motif n°2"
pass "3 littéral dans le seul message de commit : scan-range refuse"

# ── 4. un commit qui se contente de retirer le littéral ──────────────────────
printf 'hote = exemple.invalid ; port = 443\n' > "$R/serveur.txt"
commit "retrait"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_accepter "4 scan-range, retrait"
run_garde scan-tree "$MOTIFS"
doit_accepter "4 scan-tree après correction"
run_garde scan-range "$MOTIFS" HEAD~4..HEAD
doit_refuser "4 scan-range sur les quatre commits" "message de commit" "serveur.txt:1"
pass "4 retrait du littéral : scan-range accepte, scan-tree rend 0 après correction ; une plage de plusieurs commits rend 1"

# ── 5. chemins ajoutés ou renommés ; un chemin préexistant n'est pas reproché ─
mkdir "$R/dossiers"
git -C "$R" mv propre.txt "dossiers/$LITTERAL.txt"
commit "renommage"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "5 chemin renommé" "chemin renommé" "motif n°2"
echo y >> "$R/dossiers/$LITTERAL.txt"
commit "modification du fichier au chemin interdit"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_accepter "5 chemin préexistant, contenu propre"
echo x > "$R/notes-$LITTERAL.md"
commit "ajout d'un chemin interdit"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "5 chemin ajouté" "chemin ajouté" "motif n°2"
git -C "$R" rm -q -r dossiers "notes-$LITTERAL.md"
commit "nettoyage"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_accepter "5 retrait des chemins interdits"
pass "5 chemins ajoutés ou renommés refusés ; un commit de nettoyage (retraits seuls) accepté"

# ── 6. le second motif : expression rationnelle, commentaires et lignes vides ignorés ─
printf 'hote = %s\n' "$REGEX_VALEUR" > "$R/serveur.txt"
commit "variante rationnelle"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "6 expression rationnelle" "serveur.txt:1" "motif n°6"
git -C "$R" rm -q serveur.txt
commit "retrait serveur"
pass "6 second motif : expression rationnelle reconnue, numéro = ligne du fichier (commentaires et lignes vides sautés)"

# ── 6 bis. la casse ne protège pas : un motif minuscule attrape ses variantes ─
# Un nom s'écrit en slug, en CamelCase ou en majuscules : la comparaison ne tient
# pas compte de la casse, et le rapport masque la variante elle-même.
VARIANTE='Interdit-Hote-Fictif42'
printf 'hote = %s\n' "$VARIANTE" > "$R/serveur.txt"
mkdir "$R/dossier-$VARIANTE"
echo propre > "$R/dossier-$VARIANTE/notes.md"
commit "variante majuscule"
run_garde scan-tree "$MOTIFS"
doit_refuser "6 bis scan-tree" "serveur.txt:1" "motif n°6" "chemin suivi"
printf '%s\n' "$OUT" | grep -qF -- "$VARIANTE" && fail "6 bis scan-tree : la variante est affichée en clair — sortie : $OUT"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "6 bis scan-range" "serveur.txt:1" "chemin ajouté" "motif n°6"
printf '%s\n' "$OUT" | grep -qF -- "$VARIANTE" && fail "6 bis scan-range : la variante est affichée en clair — sortie : $OUT"
echo x >> "$R/serveur.txt"
commit "message en majuscules : $VARIANTE"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "6 bis message" "message de commit" "motif n°6"
printf '%s\n' "$OUT" | grep -qF -- "$VARIANTE" && fail "6 bis message : la variante est affichée en clair — sortie : $OUT"
git -C "$R" rm -q -r serveur.txt "dossier-$VARIANTE"
commit "nettoyage"
pass "6 bis comparaison sans casse : une variante majuscule d'un motif minuscule est refusée, et masquée"

# ── 7. une ligne ajoutée dont le contenu commence par « ++ » n'est pas un en-tête ─
printf '++ %s\n' "$LITTERAL" >> "$R/base.txt"
commit "ligne qui ressemble à un en-tête"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "7 ligne ajoutée en « ++ »" "base.txt:" "motif n°2"
git -C "$R" checkout -q HEAD~1 -- base.txt
commit "retrait de la ligne"
pass "7 ligne ajoutée commençant par « ++ » : examinée comme une ligne, pas comme un en-tête"

# ── 8. aucune ligne correspondante n'est affichée en entier ──────────────────
LONGUE="$(head -c 300 /dev/zero | tr '\0' 'a')"
printf '%s %s %s TEMOIN-DE-FIN-DE-LIGNE\n' "$LONGUE" "$LITTERAL" "$LONGUE" > "$R/longue.txt"
commit "ligne longue"
run_garde scan-tree "$MOTIFS"
doit_refuser "8 ligne longue" "longue.txt:1" "motif n°2"
printf '%s\n' "$OUT" | grep -qF "TEMOIN-DE-FIN-DE-LIGNE" && fail "8 ligne longue : la fin de la ligne est affichée — la ligne est donc montrée en entier"
EXTRAIT="$(printf '%s\n' "$OUT" | grep -F -- "longue.txt:1" | head -n 1)"
[ "${#EXTRAIT}" -le 200 ] || fail "8 ligne longue : l'extrait affiché dépasse 200 caractères (${#EXTRAIT})"
git -C "$R" rm -q longue.txt
commit "retrait longue"
pass "8 ligne correspondante : seul un extrait masqué, borné, est affiché"

# ── 8 bis. un chemin qui contient lui-même une valeur interdite est affiché masqué ─
mkdir "$R/dossier-$LITTERAL"
printf 'note %s\n' "$LITTERAL" > "$R/dossier-$LITTERAL/notes.md"
commit "fichier sous un chemin interdit"
run_garde scan-tree "$MOTIFS"
doit_refuser "8 bis scan-tree" "notes.md:1" "motif n°2" "chemin suivi"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "8 bis scan-range" "notes.md:1" "motif n°2"
git -C "$R" rm -q -r "dossier-$LITTERAL"
commit "nettoyage du chemin interdit"
pass "8 bis chemin contenant une valeur interdite : masqué dans le rapport (scan-tree et scan-range)"

# ── 8 ter. un chemin suivi qui contient une valeur interdite, contenu sain ────
# Le nom d'un fichier ou d'un dossier suffit à identifier un client ou un outil
# privé : scan-tree examine les chemins suivis, pas seulement leur contenu.
mkdir "$R/archive-$LITTERAL"
echo propre > "$R/archive-$LITTERAL/notes.md"
commit "chemin interdit, contenu sain"
run_garde scan-tree "$MOTIFS"
doit_refuser "8 ter scan-tree" "chemin suivi" "motif n°2"
[ "$(printf '%s\n' "$OUT" | grep -c -- '— chemin suivi —')" -eq 1 ] || fail "8 ter : un seul chemin suivi est fautif — sortie : $OUT"
printf '%s\n' "$OUT" | grep -qF "notes.md" || fail "8 ter : le fichier au chemin fautif n'est pas nommé — sortie : $OUT"
EXTRAIT="$(printf '%s\n' "$OUT" | grep -F -- '— chemin suivi —' | head -n 1)"
[ "${#EXTRAIT}" -le 200 ] || fail "8 ter : la ligne du chemin fautif dépasse 200 caractères (${#EXTRAIT})"
# Le second motif (expression rationnelle) vaut aussi pour un chemin ; et pour
# scan-range, ce renommage est un chemin renommé.
git -C "$R" mv "archive-$LITTERAL" "archive-$REGEX_VALEUR"
commit "renommage vers un chemin interdit, seconde orthographe"
run_garde scan-tree "$MOTIFS"
doit_refuser "8 ter scan-tree, second motif" "chemin suivi" "motif n°6"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "8 ter scan-range, renommage" "chemin renommé" "motif n°6"
git -C "$R" rm -q -r "archive-$REGEX_VALEUR"
commit "nettoyage du chemin interdit"
run_garde scan-tree "$MOTIFS"
doit_accepter "8 ter scan-tree après nettoyage"
pass "8 ter chemin suivi contenant une valeur interdite : signalé par scan-tree, même à contenu sain"

# ── 9. ce qu'un commit de fusion amène lui-même (résolution de conflit) ──────
git -C "$R" checkout -q -b gauche
echo gauche > "$R/conflit.txt"
commit "côté gauche"
git -C "$R" checkout -q main
echo droite > "$R/conflit.txt"
commit "côté droit"
if git -C "$R" merge -q --no-edit gauche 2>/dev/null; then
    fail "9 fixture : la fusion aurait dû être en conflit"
fi
printf 'resolution %s\n' "$LITTERAL" > "$R/conflit.txt"
commit "fusion"
FUSION="$CIBLE"
run_garde scan-range "$MOTIFS" "$FUSION^!"
doit_refuser "9 fusion qui introduit le littéral" "conflit.txt:1" "motif n°2"
echo "resolution propre" > "$R/conflit.txt"
commit "résolution corrigée"
run_garde scan-range "$MOTIFS" "$FUSION..HEAD"
doit_accepter "9 correction de la résolution"
pass "9 un commit de fusion est examiné pour ce qu'il amène lui-même"

# ── 10. fichier de motifs vide, absent ou inutilisable → code 2 ──────────────
run_garde scan-tree "$TMP/vide.txt"
[ "$RC" -eq 2 ] || fail "10 scan-tree, motifs vides : rend $RC au lieu de 2"
run_garde scan-range "$TMP/vide.txt" HEAD~1..HEAD
[ "$RC" -eq 2 ] || fail "10 scan-range, motifs vides : rend $RC au lieu de 2"
run_garde scan-tree "$ABSENT"
[ "$RC" -eq 2 ] || fail "10 scan-tree, motifs absents : rend $RC au lieu de 2"
printf '# seulement des commentaires\n\n' > "$TMP/commentaires.txt"
run_garde scan-tree "$TMP/commentaires.txt"
[ "$RC" -eq 2 ] || fail "10 scan-tree, motifs réduits à des commentaires : rend $RC au lieu de 2"
printf 'ok\npremiere[crochet\n' > "$TMP/invalide.txt"
run_garde scan-tree "$TMP/invalide.txt"
[ "$RC" -eq 2 ] || fail "10 motif invalide : rend $RC au lieu de 2"
echo "$OUT" | grep -q "motif n°2" || fail "10 motif invalide : le motif en cause n'est pas nommé par son numéro — sortie : $OUT"
printf '%s\n' "$OUT" | grep -qF "premiere" && fail "10 motif invalide : le motif lui-même est affiché"
printf 'valeur|\n' > "$TMP/tout.txt"               # accepte la chaîne vide : rien ne serait épargné
run_garde scan-tree "$TMP/tout.txt"
[ "$RC" -eq 2 ] || fail "10 motif qui accepte la chaîne vide : rend $RC au lieu de 2"
pass "10 fichier de motifs vide, absent, réduit à des commentaires, ou inutilisable : code 2"

# ── 11. <racine> en argument, depuis un autre répertoire ─────────────────────
set +e
OUT="$(cd "$TMP" && bash "$GARDE" scan-tree "$MOTIFS" "$R" 2>&1)"; RC=$?
set -e
[ "$RC" -eq 0 ] || fail "11 scan-tree <racine> depuis ailleurs : rend $RC — sortie : $OUT"
run_garde scan-tree "$MOTIFS" "$R"
[ "$RC" -eq 0 ] || fail "11 scan-tree <racine> depuis le dépôt : rend $RC — sortie : $OUT"
pass "11 scan-tree accepte une racine en argument"

# ── 11 bis. au-delà de 50 correspondances : tronçonnage de la liste, comptes exacts ─
DEPART="$CIBLE"
: > "$R/nombreux.txt"
for k in $(seq 60); do printf 'ligne %d : %s\n' "$k" "$LITTERAL" >> "$R/nombreux.txt"; done
commit "soixante lignes fautives"
printf 'encore %s\n' "$LITTERAL" > "$R/une.txt"
commit "une ligne fautive de plus"
run_garde scan-range "$MOTIFS" "$DEPART..HEAD"
echo "11 bis : rc=$RC"; echo "$OUT" | tail -n 3
[ "$RC" -eq 1 ] || fail "11 bis : la garde rend $RC au lieu de 1"
rien_fuit "11 bis"
echo "$OUT" | grep -qF "61 correspondance(s) de valeurs interdites dans 2 commit(s)" \
    || fail "11 bis : comptes attendus « 61 correspondance(s) … dans 2 commit(s) » — fin de sortie : $(echo "$OUT" | tail -n 2)"
echo "$OUT" | grep -qF "et 11 autres, non listées" || fail "11 bis : la troncature de la liste n'est pas annoncée"
[ "$(echo "$OUT" | grep -c '^  commit ')" -eq 50 ] || fail "11 bis : 50 lignes de détail attendues"
pass "11 bis plus de 50 correspondances : liste tronquée et annoncée, comptes exacts"
git -C "$R" reset -q --hard "$DEPART"

# ══ Les exceptions : .oss-guard-allow, à la racine du dépôt ══════════════════
# Un fichier listé y référence fonctionnellement un outil interne : son contenu
# n'est pas signalé. Chemin exact seulement. Restent examinés : les messages de
# commit, les chemins ajoutés ou renommés, et un chemin suivi qui contient une
# valeur interdite. Le compte final annonce les fichiers ignorés.
ALLOW="$R/.oss-guard-allow"
mkdir "$R/outils"
printf 'outil = %s\n' "$LITTERAL" > "$R/outils/reference.txt"
printf 'outil = %s\n' "$LITTERAL" > "$R/outils/second.txt"
commit "ajout de deux fichiers qui référencent l'outil"

# ── 11 ter. sans fichier d'exceptions : rien ne change ───────────────────────
[ ! -e "$ALLOW" ] || fail "11 ter fixture : .oss-guard-allow ne devrait pas exister"
run_garde scan-tree "$MOTIFS"
doit_refuser "11 ter scan-tree sans exceptions" "outils/reference.txt:1" "outils/second.txt:1"
printf '%s\n' "$OUT" | grep -q "ignoré" && fail "11 ter : le compte final parle d'exceptions alors qu'il n'y en a pas — sortie : $OUT"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "11 ter scan-range sans exceptions" "outils/reference.txt:1" "outils/second.txt:1"
pass "11 ter fichier d'exceptions absent : comportement inchangé"

# ── 11 quater. fichiers listés : non signalés en scan-tree comme en scan-range ──
# Espaces de fin de ligne, fin de ligne CRLF, commentaire, ligne vide, et un
# chemin qui ne correspond à aucun fichier.
printf '# exceptions : fichiers qui référencent fonctionnellement un outil interne\n\noutils/reference.txt   \n   \noutils/second.txt\r\n# commentaire\noutils/absent.txt\n' > "$ALLOW"
commit "exceptions"
run_garde scan-tree "$MOTIFS"
doit_accepter "11 quater scan-tree"
printf '%s\n' "$OUT" | grep -qF "2 fichier(s) ignoré(s) par .oss-guard-allow" \
    || fail "11 quater scan-tree : compte final sans « 2 fichier(s) ignoré(s) par .oss-guard-allow » — sortie : $OUT"
printf '%s\n' "$OUT" | grep -q '^  ' && fail "11 quater scan-tree : une ligne de détail est affichée alors que tout est ignoré — sortie : $OUT"
run_garde scan-range "$MOTIFS" HEAD~2..HEAD
doit_accepter "11 quater scan-range, ajout des fichiers puis des exceptions"
printf '%s\n' "$OUT" | grep -qF "2 fichier(s) ignoré(s) par .oss-guard-allow" \
    || fail "11 quater scan-range : compte final sans « 2 fichier(s) ignoré(s) par .oss-guard-allow » — sortie : $OUT"
pass "11 quater fichiers listés : ignorés en scan-tree et en scan-range ; commentaire, ligne vide, espaces de fin et CRLF ne comptent pas"

# ── 11 quinquies. même préfixe, non listé : examiné ──────────────────────────
cp "$R/outils/reference.txt" "$R/outils/reference.txt.bak"
printf 'outil = %s\n' "$LITTERAL" > "$R/outils/reference.txt2"
commit "deux fichiers au préfixe d'un fichier listé"
run_garde scan-tree "$MOTIFS"
doit_refuser "11 quinquies scan-tree" "outils/reference.txt.bak:1" "outils/reference.txt2:1" "2 fichier(s) ignoré(s) par .oss-guard-allow"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "11 quinquies scan-range" "outils/reference.txt.bak:1" "outils/reference.txt2:1"
git -C "$R" rm -q outils/reference.txt.bak outils/reference.txt2
commit "retrait des fichiers au préfixe"
pass "11 quinquies un fichier qui ne partage que le préfixe d'un chemin listé reste examiné"

# ── 11 sexies. un commit qui touche un fichier listé : message et chemin restent examinés ──
echo precis >> "$R/outils/reference.txt"
commit "message qui cite $LITTERAL"              # ligne ajoutée propre, message fautif
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "11 sexies message d'un commit qui touche un fichier listé" "message de commit" "motif n°2"
git -C "$R" mv outils/second.txt "outils/$LITTERAL.txt"
commit "renommage d'un fichier listé vers un chemin interdit"
run_garde scan-range "$MOTIFS" HEAD~1..HEAD
doit_refuser "11 sexies renommage d'un fichier listé" "chemin renommé" "motif n°2"
pass "11 sexies message de commit et chemin renommé : examinés même pour un fichier listé"

# ── 11 septies. l'exception porte sur le contenu : un chemin suivi fautif reste signalé ──
# Le fichier d'exceptions est ici non suivi : lister un chemin fautif y écrirait
# la valeur interdite.
git -C "$R" rm -q --cached .oss-guard-allow
printf 'outils/%s.txt\n' "$LITTERAL" >> "$ALLOW"
run_garde scan-tree "$MOTIFS"
doit_refuser "11 septies chemin suivi d'un fichier listé" "chemin suivi" "motif n°2" "2 fichier(s) ignoré(s) par .oss-guard-allow"
[ "$(printf '%s\n' "$OUT" | grep -c '^  ')" -eq 1 ] || fail "11 septies : seule la ligne du chemin devrait être en détail — sortie : $OUT"
pass "11 septies un chemin suivi qui contient une valeur interdite reste signalé, même pour un fichier listé"

rm -f "$ALLOW"
git -C "$R" reset -q --hard "$DEPART"

# ══ Le hook pre-push, simulé par son entrée standard ══════════════════════════
git init -q -b main --bare "$TMP/origin.git"
git -C "$R" remote add origin "$TMP/origin.git"
git -C "$R" push -q origin main 2>/dev/null
git -C "$R" remote set-head origin -a
LOIN="$(git -C "$R" rev-parse origin/main)"
run_hook "$MOTIFS" "refs/heads/main $LOIN refs/heads/main $LOIN"
[ "$RC" -eq 0 ] || fail "fixture : l'état poussé ne devrait rien avoir à signaler — sortie : $OUT"

# ── 12. motif trouvé dans la plage poussée → refus ───────────────────────────
printf 'hote = %s\n' "$LITTERAL" > "$R/serveur.txt"
commit "fautif"
FAUTIF="$CIBLE"
run_hook "$MOTIFS" "refs/heads/main $FAUTIF refs/heads/main $LOIN"
doit_refuser "12 refus" "refs/heads/main" "serveur.txt:1" "motif n°2" "refusé"
pass "12 pre-push : motif trouvé dans la plage poussée → refus"

# ── 13. plage propre → acceptation ; plusieurs références sur l'entrée standard ─
git -C "$R" reset -q --hard "$LOIN"
echo propre2 > "$R/deux.txt"
commit "propre"
PROPRE="$CIBLE"
run_hook "$MOTIFS" "refs/heads/main $PROPRE refs/heads/main $LOIN"
doit_accepter "13 acceptation"
echo propre3 > "$R/trois.txt"
commit "propre 2"
DEUX="$CIBLE"
run_hook "$MOTIFS" "refs/heads/main $DEUX refs/heads/main $LOIN" "refs/heads/autre $DEUX refs/heads/autre $NUL"
doit_accepter "13 deux références propres"
# Seule la seconde référence est fautive : l'entrée standard doit lui parvenir entière.
echo "$LITTERAL" > "$R/quatre.txt"
commit "fautif sur la seconde référence"
FAUTIF2="$CIBLE"
run_hook "$MOTIFS" "refs/heads/main $DEUX refs/heads/main $LOIN" "refs/heads/autre $FAUTIF2 refs/heads/autre $NUL"
doit_refuser "13 seconde référence fautive" "refs/heads/autre" "quatre.txt:1"
git -C "$R" reset -q --hard "$DEUX"
pass "13 pre-push : plage propre → acceptation ; plusieurs références examinées"

# ── 13 ter. un fichier listé dans .oss-guard-allow passe le hook ; son message, non ──
printf 'hote = %s\n' "$LITTERAL" > "$R/reference.txt"
printf '# exception\nreference.txt\n' > "$R/.oss-guard-allow"
commit "fichier listé dans les exceptions"
LISTE="$CIBLE"
run_hook "$MOTIFS" "refs/heads/main $LISTE refs/heads/main $LOIN"
doit_accepter "13 ter fichier listé"
printf '%s\n' "$OUT" | grep -qF "1 fichier(s) ignoré(s) par .oss-guard-allow" \
    || fail "13 ter : compte final sans « 1 fichier(s) ignoré(s) par .oss-guard-allow » — sortie : $OUT"
echo y >> "$R/reference.txt"
commit "message fautif sur un fichier listé : $LITTERAL"
run_hook "$MOTIFS" "refs/heads/main $CIBLE refs/heads/main $LOIN"
doit_refuser "13 ter message fautif" "message de commit" "refs/heads/main"
git -C "$R" rm -q reference.txt .oss-guard-allow
commit "retrait du fichier listé"
pass "13 ter pre-push : le contenu d'un fichier listé passe, le message de commit non"

# ── 13 bis. une commande de l'analyse qui lirait l'entrée standard ne doit pas voler les lignes suivantes ─
# Enveloppeur de test : il consomme l'entrée standard avant de lancer la vraie garde.
GOURMAND="$TMP/gourmand"
mkdir -p "$GOURMAND/hooks"
cp "$HOOK" "$GOURMAND/hooks/pre-push-oss-guard.sh"
printf '#!/usr/bin/env bash\ncat > /dev/null\nexec bash %q "$@"\n' "$GARDE" > "$GOURMAND/oss-guard.sh"
git -C "$R" checkout -q -b gourmande "$DEUX"
echo "$LITTERAL" > "$R/cinq.txt"
commit "fautif derrière un enfant gourmand"
set +e
OUT="$(cd "$R" && printf '%s\n' "refs/heads/main $DEUX refs/heads/main $LOIN" "refs/heads/gourmande $CIBLE refs/heads/gourmande $NUL" \
      | OSS_FORBIDDEN_FILE="$MOTIFS" bash "$GOURMAND/hooks/pre-push-oss-guard.sh" 2>&1)"; RC=$?
set -e
doit_refuser "13 bis seconde référence derrière un enfant gourmand" "refs/heads/gourmande" "cinq.txt:1"
git -C "$R" checkout -q main
pass "13 bis pre-push : l'entrée standard du hook est réservée au hook, même derrière une commande qui la lit"

# ── 14. fichier de motifs absent : avertissement et sortie 0 ─────────────────
run_hook "$ABSENT" "refs/heads/main $DEUX refs/heads/main $LOIN"
echo "14 fichier absent : rc=$RC"; echo "$OUT"
[ "$RC" -eq 0 ] || fail "14 fichier de motifs absent : le hook rend $RC au lieu de 0"
echo "$OUT" | grep -q "⚠" || fail "14 fichier de motifs absent : aucun avertissement"
pass "14 pre-push : fichier de motifs absent → avertissement, push autorisé"

# ── 15. fichier de motifs vide : analyse impossible, refus ───────────────────
run_hook "$TMP/vide.txt" "refs/heads/main $DEUX refs/heads/main $LOIN"
[ "$RC" -eq 1 ] || fail "15 fichier de motifs vide : le hook rend $RC au lieu de 1"
pass "15 pre-push : fichier de motifs vide → push refusé"

# ── 16. nouvelle branche (sha distant nul) : base = origin/HEAD, seuls ses apports sont examinés ─
git -C "$R" checkout -q -b sujets "$LOIN"
echo sujet > "$R/sujet.txt"
commit "sujet propre"
SUJET_PROPRE="$CIBLE"
run_hook "$MOTIFS" "refs/heads/sujets $SUJET_PROPRE refs/heads/sujets $NUL"
doit_accepter "16 nouvelle branche propre (historique fautif avant la base)"
printf 'hote = %s\n' "$LITTERAL" > "$R/sujet.txt"
commit "sujet fautif"
SUJET="$CIBLE"
run_hook "$MOTIFS" "refs/heads/sujets $SUJET refs/heads/sujets $NUL"
doit_refuser "16 nouvelle branche fautive" "sujet.txt:1"
pass "16 pre-push : nouvelle branche — base sur origin/HEAD, seul ce qu'elle apporte est examiné"

# ── 17. origin/HEAD absent : repli sur origin/main ───────────────────────────
# Le lien symbolique lui-même : `update-ref -d` suivrait le lien et supprimerait origin/main.
git -C "$R" symbolic-ref -d refs/remotes/origin/HEAD
[ "$(git -C "$R" rev-parse origin/main)" = "$LOIN" ] || fail "17 fixture : origin/main aurait dû rester"
run_hook "$MOTIFS" "refs/heads/sujets $SUJET refs/heads/sujets $NUL"
doit_refuser "17 sans origin/HEAD" "sujet.txt:1"
run_hook "$MOTIFS" "refs/heads/sujets $SUJET_PROPRE refs/heads/sujets $NUL"
doit_accepter "17 sans origin/HEAD, branche propre"
pass "17 pre-push : sans origin/HEAD, la base est cherchée sur origin/main"

# ── 18. plus aucune référence distante : tout l'historique apporté est examiné ─
git -C "$R" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r ref; do
    git -C "$R" update-ref -d "$ref"
done
[ -z "$(git -C "$R" for-each-ref refs/remotes/origin)" ] || fail "18 fixture : des références distantes restent"
run_hook "$MOTIFS" "refs/heads/main $DEUX refs/heads/main $NUL"
doit_refuser "18 premier push d'un historique fautif" "message de commit"
pass "18 pre-push : sans aucune référence distante, tout l'historique est examiné"

# ── 19. suppression de branche (sha local nul) : rien à examiner ─────────────
run_hook "$MOTIFS" "refs/heads/ancienne $NUL refs/heads/ancienne $DEUX"
doit_accepter "19 suppression de branche"
pass "19 pre-push : suppression de branche → rien à examiner"

echo ""
echo "🎉 Tous les tests passent."
