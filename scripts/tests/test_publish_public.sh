#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_publish_public.sh — régression : publish-public.sh publie les mains
# privées du parc vers les dépôts publics, et ne pousse rien sans avoir tout
# vérifié.
#
# Open source — la copie publique doit suivre la copie privée. Tout le pré-vol
# passe avant tout push : un refus sur un dépôt, aucun push nulle part. Le méta
# part en dernier : ses gitlinks référencent des commits qui doivent exister
# publiquement.
#
# Fixture, tout local. Origines privées et publics sont des dépôts bare sous
# $TMP (composants compA → pubA, compB → pubB ; méta POULIDOR) ; les clones de
# publication vivent sous $TMP/publish ; le faux --root est le checkout du méta
# (origin = méta privé) et porte les deux sous-modules. .gitmodules et
# manifest.json du méta citent des URL privées factices (https et ssh),
# introuvables : une URL qui resterait privée fait échouer le clone anonyme de
# --verify.
#
# Cas : 1 dry-run · 2 --yes, relance, rien à réécrire, --only · 3 commit
# étranger · 4 garde OSS · 5 clone manquant (bootstrap) · 6 --verify · 7
# fichier de motifs absent ou vide · 8 usage · 9 push refusé en cours de
# route · 10 identité git absente · 11 post-contrôles de l'adaptation.
#
# Toutes les valeurs interdites de ce test sont factices.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$SCRIPTS/publish-public.sh"
GARDE="$SCRIPTS/oss-guard.sh"

fail() {
    echo "❌ FAIL: $*" >&2
    if [ -n "${OUT:-}" ]; then printf '%s\n' "$OUT" | sed 's/^/    | /' >&2; fi
    exit 1
}
pass() { echo "✅ $*"; }

[ -f "$GARDE" ] || fail "scripts/oss-guard.sh absent"
[ -f "$PUB" ] || fail "scripts/publish-public.sh absent"

# ── Isolation : rien ne touche le vrai ~ (ni ~/publish, ni le vrai fichier de motifs) ──
TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-publish-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
# Les sous-modules de la fixture sont des chemins locaux : git ne les clone que
# sur autorisation explicite (valable pour la fixture comme pour le script).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
mkdir -p "$HOME" "$TMP/tmp"
git config --global user.name test
git config --global user.email test@example.org

PRIVE="$TMP/priv"        # origines privées (bare)
PUBLIC="$TMP/public"     # dépôts publics (bare) ; PUBLIC_SSH_BASE = PUBLIC_HTTPS_BASE = ce dossier
ROOT="$TMP/root"         # faux --root : checkout du méta
WORK="$TMP/work"         # checkouts de travail des composants
MAP="$TMP/map.txt"
MOTIFS="$TMP/motifs.txt"
PUBLISH="$TMP/publish"   # PUBLISH_DIR ; vide = défaut du script (sous le HOME isolé)
LITTERAL='INTERDIT-CLIENT-FICTIF-9C2B'

printf '# Motifs de test (factices) : une expression rationnelle étendue par ligne.\n%s\n' "$LITTERAL" > "$MOTIFS"
printf 'compA pubA component\ncompB pubB component\nPOULIDOR POULIDOR meta\n' > "$MAP"

lancer() {  # lancer [options…] : le script sur la fixture ; renseigne RC et OUT
    set +e
    OUT="$(PUBLISH_DIR="$PUBLISH" PUBLIC_SSH_BASE="$PUBLIC" PUBLIC_HTTPS_BASE="$PUBLIC" PUBLISH_MAP="$(cat "$MAP")" \
           OSS_FORBIDDEN_FILE="$MOTIFS" TMPDIR="$TMP/tmp" bash "$PUB" --root "$ROOT" "$@" 2>&1)"; RC=$?
    set -e
}

commit_dans() {  # commit_dans <dépôt> <message> : commit de tout le répertoire de travail
    git -C "$1" add -A
    git -C "$1" commit -q -m "$2"
}
nouveau_commit() {  # nouveau_commit <dépôt de travail> <message> [contenu de nouveau.txt] : commit poussé sur l'origine privée
    printf '%s\n' "${3:-nouveau}" > "$1/nouveau.txt"
    commit_dans "$1" "$2"
    git -C "$1" push -q origin main
}
commit_etranger() {  # commit_etranger <dépôt public bare> <message> : un commit fait directement sur le public
    local c="$TMP/etranger"
    rm -rf "$c"
    git clone -q "$1" "$c"
    echo etranger > "$c/etranger.txt"
    commit_dans "$c" "$2"
    git -C "$c" push -q origin main
    rm -rf "$c"
}
etat() {  # etat <dépôt bare>… : toutes leurs références (nom sha) — prouver qu'un dépôt n'a pas bougé
    local d
    for d in "$@"; do git -C "$d" for-each-ref --format='%(refname) %(objectname)'; done
}
publics() { etat "$PUBLIC/pubA.git" "$PUBLIC/pubB.git" "$PUBLIC/POULIDOR.git"; }
prives()  { etat "$PRIVE/compA.git" "$PRIVE/compB.git" "$PRIVE/POULIDOR.git"; }
main_de() { git -C "$1" rev-parse -q --verify refs/heads/main 2>/dev/null || true; }   # vide si absent
main_court() { printf '%s' "$(main_de "$1")" | cut -c1-7; }
nb_worktrees() { git -C "$1" worktree list --porcelain | grep -c '^worktree ' || true; }

doit_accepter() {  # doit_accepter <libellé>
    echo "$1 : rc=$RC"
    [ "$RC" -eq 0 ] || fail "$1 : le script rend $RC au lieu de 0"
}
doit_refuser() {  # doit_refuser <libellé> [fragment attendu…] : code 1 ; la sortie cite chaque fragment
    local libelle="$1" f; shift
    echo "$libelle : rc=$RC"
    printf '%s\n' "$OUT" | grep -v '^✅ oss-guard' | sed 's/^/    /'
    [ "$RC" -eq 1 ] || fail "$libelle : le script rend $RC au lieu de 1"
    for f in "$@"; do printf '%s\n' "$OUT" | grep -qF -- "$f" || fail "$libelle : sortie sans « $f »"; done
}
doit_usage() {  # doit_usage <libellé>
    echo "$1 : rc=$RC"
    [ "$RC" -eq 2 ] || fail "$1 : le script rend $RC au lieu de 2"
}
inchange() {  # inchange <libellé> <état avant> <état après>
    [ "$2" = "$3" ] || fail "$1 : l'état des dépôts a changé — avant : [$2] ; après : [$3]"
}
propre() {  # propre <libellé> : aucun worktree jetable ni répertoire temporaire ne subsiste
    if [ -d "$PUBLISH/POULIDOR" ]; then
        [ "$(nb_worktrees "$PUBLISH/POULIDOR")" -eq 1 ] \
            || fail "$1 : un worktree jetable subsiste dans le clone de publication du méta"
    fi
    [ -z "$(ls -A "$TMP/tmp")" ] || fail "$1 : des répertoires temporaires subsistent : $(ls -A "$TMP/tmp")"
}
dans_sortie() {  # dans_sortie <libellé> <fragment> : le fragment figure dans la sortie
    printf '%s\n' "$OUT" | grep -qF -- "$2" || fail "$1 : sortie sans « $2 »"
}
hors_sortie() {  # hors_sortie <libellé> <fragment> : le fragment ne figure pas dans la sortie
    if printf '%s\n' "$OUT" | grep -qF -- "$2"; then fail "$1 : la sortie contient « $2 »"; fi
}
ligne_du_plan() {  # ligne_du_plan <nom interne> : la ligne du plan de ce dépôt
    printf '%s\n' "$OUT" | grep -E "^  $1 → " || true
}
apres_du_plan() {  # apres_du_plan <nom interne> : le sha « après » de sa ligne du plan
    ligne_du_plan "$1" | sed -nE 's/.* → ([0-9a-f]{7}).*/\1/p' | grep -v '^$' || true
}
meta_public_sain() {  # meta_public_sain <libellé> : public/main = privé + UN commit d'adaptation, aux URL publiques
    local libelle="$1" pub pr n sujet fichiers f
    pub="$(main_de "$PUBLIC/POULIDOR.git")"; pr="$(main_de "$PRIVE/POULIDOR.git")"
    [ -n "$pub" ] || fail "$libelle : le méta public n'a pas de branche main"
    [ "$(git -C "$PUBLIC/POULIDOR.git" rev-parse "$pub^" 2>/dev/null || true)" = "$pr" ] \
        || fail "$libelle : le premier parent du méta public n'est pas le main privé"
    n="$(git -C "$PUBLIC/POULIDOR.git" rev-list --count "$pr..$pub")"
    [ "$n" -eq 1 ] || fail "$libelle : $n commit(s) public(s) au-delà du privé, 1 attendu (l'adaptation s'empile ?)"
    sujet="$(git -C "$PUBLIC/POULIDOR.git" log -1 --format=%s "$pub")"
    case "$sujet" in "chore: URLs publiques"*) ;; *) fail "$libelle : sujet du commit public : « $sujet »" ;; esac
    for f in .gitmodules manifest.json; do
        fichiers="$(git -C "$PUBLIC/POULIDOR.git" show "$pub:$f")"
        printf '%s\n' "$fichiers" | grep -q 'git@' && fail "$libelle : une URL git@ subsiste dans $f public"
        printf '%s\n' "$fichiers" | grep -q 'github.com' && fail "$libelle : une URL privée subsiste dans $f public"
        printf '%s\n' "$fichiers" | grep -qF "$PUBLIC/pubA.git" || fail "$libelle : $f public sans l'URL de pubA"
        printf '%s\n' "$fichiers" | grep -qF "$PUBLIC/pubB.git" || fail "$libelle : $f public sans l'URL de pubB"
    done
}

# ── Fixture ─────────────────────────────────────────────────────────────────
monde_neuf() {  # monde_neuf [urls-publiques | un-seul-sous-module] : composants (2 commits, tag v1.0), méta (VERSION + sous-modules) ; publics vides, aucun clone de publication
    [ -d "$TMP/home" ] || fail "fixture : $TMP improbable"
    rm -rf "$PRIVE" "$PUBLIC" "$ROOT" "$WORK" "$PUBLISH" "$HOME/publish"
    mkdir -p "$PRIVE" "$PUBLIC" "$WORK"
    local r
    for r in compA compB POULIDOR; do git init -q -b main --bare "$PRIVE/$r.git"; done
    for r in pubA pubB POULIDOR; do git init -q -b main --bare "$PUBLIC/$r.git"; done
    for r in compA compB; do
        git clone -q "$PRIVE/$r.git" "$WORK/$r" 2>/dev/null
        echo "$r" > "$WORK/$r/README.md"
        commit_dans "$WORK/$r" "init $r"
        echo "1.0" > "$WORK/$r/VERSION"
        commit_dans "$WORK/$r" "version 1.0 de $r"
        git -C "$WORK/$r" tag v1.0
        git -C "$WORK/$r" push -q origin main --tags
    done
    git clone -q "$PRIVE/POULIDOR.git" "$ROOT" 2>/dev/null
    mkdir -p "$ROOT/scripts" "$ROOT/.git/info"
    cp "$GARDE" "$ROOT/scripts/"                      # le script appelle <root>/scripts/oss-guard.sh
    echo scripts/ > "$ROOT/.git/info/exclude"         # jamais commité dans le méta de la fixture
    echo "0.0.1" > "$ROOT/VERSION"
    git -C "$ROOT" submodule add -q "$PRIVE/compA.git" compA
    if [ "${1:-}" = un-seul-sous-module ]; then
        # le méta ne déclare qu'un sous-module ; compB reste un composant de la map, donc checkout sous --root
        echo compB/ >> "$ROOT/.git/info/exclude"
        git clone -q "$PRIVE/compB.git" "$ROOT/compB" 2>/dev/null
    else
        git -C "$ROOT" submodule add -q "$PRIVE/compB.git" compB
    fi
    if [ "${1:-}" = urls-publiques ]; then            # méta dont les URL sont déjà publiques : rien à réécrire
        printf '[submodule "compA"]\n\tpath = compA\n\turl = %s/pubA.git\n[submodule "compB"]\n\tpath = compB\n\turl = %s/pubB.git\n' \
            "$PUBLIC" "$PUBLIC" > "$ROOT/.gitmodules"
        printf '{\n  "compA": "%s/pubA.git",\n  "compB": "%s/pubB.git"\n}\n' "$PUBLIC" "$PUBLIC" > "$ROOT/manifest.json"
    else
        printf '[submodule "compA"]\n\tpath = compA\n\turl = https://github.com/fakepriv/compA.git\n' > "$ROOT/.gitmodules"
        if [ "${1:-}" != un-seul-sous-module ]; then
            printf '[submodule "compB"]\n\tpath = compB\n\turl = git@github.com:fakepriv/compB.git\n' >> "$ROOT/.gitmodules"
        fi
        printf '{\n  "compA": "https://github.com/fakepriv/compA.git",\n  "compB": "git@github.com:fakepriv/compB.git"\n}\n' > "$ROOT/manifest.json"
    fi
    commit_dans "$ROOT" "init méta : VERSION et deux sous-modules"
    git -C "$ROOT" push -q origin main
}
depuis_zero() {  # depuis_zero : monde neuf, puis publication initiale
    monde_neuf
    lancer --yes
    doit_accepter "publication initiale"
}

echo "Fixture : $TMP"

# ══ 1. dry-run : rien n'est poussé, tout est vérifié ═════════════════════════
monde_neuf
AVANT="$(publics)"; PRIVES_AVANT="$(prives)"
lancer
doit_accepter "1 dry-run"
printf '%s\n' "$OUT" | sed 's/^/    /'
printf '%s\n' "$OUT" | grep -qi 'dry-run' || fail "1 : la sortie n'annonce pas le dry-run"
A="$(main_court "$PRIVE/compA.git")"; B="$(main_court "$PRIVE/compB.git")"; M="$(main_court "$PRIVE/POULIDOR.git")"
printf '%s\n' "$(ligne_du_plan compA)" | grep -qE "^  compA → pubA +\(vide\) → $A +2  ✓$" || fail "1 : ligne du plan compA attendue « (vide) → $A, 2 commits, garde ✓ » — $(ligne_du_plan compA)"
printf '%s\n' "$(ligne_du_plan compB)" | grep -qE "^  compB → pubB +\(vide\) → $B +2  ✓$" || fail "1 : ligne du plan compB — $(ligne_du_plan compB)"
printf '%s\n' "$(ligne_du_plan POULIDOR)" | grep -qE "^  POULIDOR → POULIDOR +\(vide\) → [0-9a-f]{7} +2  ✓$" \
    || fail "1 : ligne du plan POULIDOR attendue « (vide) → <sha>, 2 commits (1 privé + 1 adaptation), garde ✓ » — $(ligne_du_plan POULIDOR)"
APRES="$(apres_du_plan POULIDOR)"
if [ -z "$APRES" ] || [ "$APRES" = "$M" ]; then
    fail "1 : l'adaptation du méta n'a pas été régénérée (après : « $APRES », privé : « $M »)"
fi
[ "$(git -C "$PUBLISH/POULIDOR" cat-file -t "$APRES" 2>/dev/null || true)" = commit ] \
    || fail "1 : le commit d'adaptation « $APRES » n'existe pas dans le clone de publication — la faisabilité n'est pas prouvée"
[ "$(git -C "$PUBLISH/POULIDOR" show "$APRES:.gitmodules" | grep -c -e 'git@' -e 'github\.com')" -eq 0 ] \
    || fail "1 : le commit d'adaptation du dry-run laisse une URL privée"
inchange "1 rien n'est poussé nulle part (SHAs des publics inchangés)" "$AVANT" "$(publics)"
[ -z "$(publics)" ] || fail "1 : le dry-run a laissé des références dans un dépôt public"
inchange "1 dépôts privés intacts" "$PRIVES_AVANT" "$(prives)"
for d in compA compB POULIDOR; do
    [ -d "$PUBLISH/$d/.git" ] || fail "1 : clone de publication $d non amorcé"
done
[ "$(git -C "$PUBLISH/compA" remote get-url origin)" = "$PRIVE/compA.git" ] || fail "1 : origin du clone compA"
[ "$(git -C "$PUBLISH/compA" remote get-url public)" = "$PUBLIC/pubA.git" ] || fail "1 : remote public de compA"
propre "1"
pass "1 dry-run : rien n'est poussé, plan affiché, adaptation prouvée en worktree jetable, aucun résidu"

# ══ 2. --yes : composants = privé ; méta = privé + UN commit d'adaptation ═══
PRIVES_AVANT="$(prives)"
lancer --yes
doit_accepter "2 --yes"
for d in compA compB; do
    p="$d"; case "$d" in compA) p=pubA ;; compB) p=pubB ;; esac
    [ "$(main_de "$PUBLIC/$p.git")" = "$(main_de "$PRIVE/$d.git")" ] || fail "2 : public $p ≠ privé $d"
    [ "$(git -C "$PUBLIC/$p.git" rev-parse 'v1.0^{commit}')" = "$(git -C "$PRIVE/$d.git" rev-parse 'v1.0^{commit}')" ] \
        || fail "2 : le tag v1.0 de $d n'est pas publié"
done
meta_public_sain 2
inchange "2 les dépôts privés ne sont jamais touchés" "$PRIVES_AVANT" "$(prives)"
propre "2"
pass "2 --yes : composants et tags publiés tels quels ; méta = privé + 1 commit d'adaptation ; .gitmodules et manifest 100 % URL publiques"

# ── 2b. relance après de nouveaux commits privés : tout rattrape, l'adaptation se régénère au lieu de s'empiler ──
VIEUX_A="$(main_de "$PUBLIC/pubA.git")"; VIEUX_B="$(main_de "$PUBLIC/pubB.git")"; VIEUX_META="$(main_de "$PUBLIC/POULIDOR.git")"
nouveau_commit "$WORK/compA" "compA : nouveau commit"
echo "0.0.2" > "$ROOT/VERSION"
nouveau_commit "$ROOT" "méta : VERSION 0.0.2"
A="$(main_court "$PRIVE/compA.git")"
AVANT="$(publics)"
lancer
doit_accepter "2b relance, dry-run"
printf '%s\n' "$(ligne_du_plan compA)" | grep -qE "^  compA → pubA +${VIEUX_A:0:7} → $A +1  ✓$" || fail "2b : ligne compA — $(ligne_du_plan compA)"
printf '%s\n' "$(ligne_du_plan compB)" | grep -qE "^  compB → pubB +${VIEUX_B:0:7} → ${VIEUX_B:0:7} \(inchangé\) +0  ✓$" \
    || fail "2b : ligne compB attendue « inchangé, 0 commit » — $(ligne_du_plan compB)"
printf '%s\n' "$(ligne_du_plan POULIDOR)" | grep -qE "^  POULIDOR → POULIDOR +${VIEUX_META:0:7} → [0-9a-f]{7} +2  ✓$" \
    || fail "2b : ligne POULIDOR attendue « ancien → nouveau, 2 commits » — $(ligne_du_plan POULIDOR)"
inchange "2b le dry-run ne pousse rien" "$AVANT" "$(publics)"
lancer --yes
doit_accepter "2b relance, --yes"
[ "$(main_de "$PUBLIC/pubA.git")" = "$(main_de "$PRIVE/compA.git")" ] || fail "2b : compA non rattrapé"
[ "$(main_de "$PUBLIC/pubB.git")" = "$VIEUX_B" ] || fail "2b : compB a bougé sans commit privé"
meta_public_sain 2b
[ "$(git -C "$PUBLIC/POULIDOR.git" show "$(main_de "$PUBLIC/POULIDOR.git"):VERSION")" = "0.0.2" ] \
    || fail "2b : le VERSION du méta public n'est pas celui du nouveau commit privé"
pass "2b relance : le public rattrape le privé ; l'adaptation est régénérée (toujours 1 commit au-delà du privé)"

# ── 2c. méta déjà aux URL publiques : rien à réécrire, origin/main poussé tel quel ──
monde_neuf urls-publiques
M="$(main_court "$PRIVE/POULIDOR.git")"
lancer
doit_accepter "2c rien à réécrire, dry-run"
printf '%s\n' "$(ligne_du_plan POULIDOR)" | grep -qE "^  POULIDOR → POULIDOR +\(vide\) → $M +1  ✓$" \
    || fail "2c : ligne POULIDOR attendue « (vide) → $M (main privé tel quel), 1 commit » — $(ligne_du_plan POULIDOR)"
lancer --yes
doit_accepter "2c rien à réécrire, --yes"
[ "$(main_de "$PUBLIC/POULIDOR.git")" = "$(main_de "$PRIVE/POULIDOR.git")" ] || fail "2c : le méta public devrait être exactement le main privé"
pass "2c rien à réécrire : le méta public est le main privé, sans commit d'adaptation"

# ── 2d. --only : nom interne ou public ; le méta, sélectionné seul, s'adapte pour tous les composants ──
depuis_zero
VIEUX_B="$(main_de "$PUBLIC/pubB.git")"; VIEUX_META="$(main_de "$PUBLIC/POULIDOR.git")"
nouveau_commit "$WORK/compA" "compA : nouveau commit" a
nouveau_commit "$WORK/compB" "compB : nouveau commit" b
nouveau_commit "$ROOT" "méta : nouveau commit" m
lancer --only pubA --yes
doit_accepter "2d --only <nom public>"
[ "$(main_de "$PUBLIC/pubA.git")" = "$(main_de "$PRIVE/compA.git")" ] || fail "2d : compA non publié"
[ "$(main_de "$PUBLIC/pubB.git")" = "$VIEUX_B" ] || fail "2d : compB publié alors que non sélectionné"
[ "$(main_de "$PUBLIC/POULIDOR.git")" = "$VIEUX_META" ] || fail "2d : méta publié alors que non sélectionné"
hors_sortie "2d" "compB → pubB"
lancer --only compA compB --yes
doit_accepter "2d --only <composants> : le méta reste pour dernier"
[ "$(main_de "$PUBLIC/pubB.git")" = "$(main_de "$PRIVE/compB.git")" ] || fail "2d : compB non publié"
[ "$(main_de "$PUBLIC/POULIDOR.git")" = "$VIEUX_META" ] || fail "2d : le méta a été publié sans être sélectionné"
lancer --only POULIDOR --yes
doit_accepter "2d --only POULIDOR"
meta_public_sain 2d
pass "2d --only accepte le nom interne ou le public ; seuls les dépôts sélectionnés bougent"

# ── 2e. tag recréé côté privé : il l'emporte dans le clone de publication, et le tag public suit ──
depuis_zero
VIEUX_TAG="$(git -C "$PUBLIC/pubA.git" rev-parse 'v1.0^{commit}')"
nouveau_commit "$WORK/compA" "compA : nouveau commit"
git -C "$WORK/compA" tag -f v1.0 >/dev/null
git -C "$WORK/compA" push -q --force origin v1.0
NOUVEAU_TAG="$(git -C "$PRIVE/compA.git" rev-parse 'v1.0^{commit}')"
[ "$NOUVEAU_TAG" != "$VIEUX_TAG" ] || fail "2e fixture : le tag privé aurait dû changer"
lancer --yes
doit_accepter "2e tag recréé côté privé"
[ "$(git -C "$PUBLIC/pubA.git" rev-parse 'v1.0^{commit}')" = "$NOUVEAU_TAG" ] || fail "2e : le tag public n'a pas suivi le tag privé recréé"
pass "2e tag recréé côté privé : le clone de publication le suit, et le tag public aussi"

# ── 2f. un run refusé après le fetch d'origin ne doit pas bloquer le suivant (tag déjà récupéré) ──
depuis_zero
BON_B="$(main_de "$PUBLIC/pubB.git")"
commit_etranger "$PUBLIC/pubB.git" "feat: commit étranger, pour refuser le run"
nouveau_commit "$WORK/compA" "compA : nouveau commit"
git -C "$WORK/compA" tag -f v1.0 >/dev/null
git -C "$WORK/compA" push -q --force origin v1.0
lancer --yes
doit_refuser "2f run refusé, tag privé recréé déjà dans le clone" "compB" "étranger"
NOUVEAU_TAG="$(git -C "$PRIVE/compA.git" rev-parse 'v1.0^{commit}')"
[ "$(git -C "$PUBLISH/compA" rev-parse 'v1.0^{commit}')" = "$NOUVEAU_TAG" ] \
    || fail "2f fixture : le clone de publication devrait déjà porter le tag recréé"
[ "$(git -C "$PUBLIC/pubA.git" rev-parse 'v1.0^{commit}')" != "$NOUVEAU_TAG" ] \
    || fail "2f fixture : le tag public n'aurait pas dû bouger pendant un run refusé"
git -C "$PUBLIC/pubB.git" update-ref refs/heads/main "$BON_B"       # le public de compB revient dans le droit chemin
lancer --yes
doit_accepter "2f run suivant"
[ "$(git -C "$PUBLIC/pubA.git" rev-parse 'v1.0^{commit}')" = "$NOUVEAU_TAG" ] || fail "2f : le tag public n'a pas suivi le tag privé recréé"
pass "2f un run refusé ne laisse pas le clone de publication dans un état qui bloque le suivant"

# ══ 3. commit étranger sur UN public → refus, et aucun push sur aucun dépôt ══
depuis_zero
nouveau_commit "$WORK/compA" "compA : nouveau commit"
nouveau_commit "$WORK/compB" "compB : nouveau commit"
nouveau_commit "$ROOT" "méta : nouveau commit"
commit_etranger "$PUBLIC/pubB.git" "feat: commit étranger sur le public"
ETRANGER="$(main_de "$PUBLIC/pubB.git")"
AVANT="$(publics)"
lancer --yes
doit_refuser "3 commit étranger sur UN public" "compB" "étranger" "${ETRANGER:0:7}"
inchange "3 aucun push sur aucun dépôt" "$AVANT" "$(publics)"
[ "$(main_de "$PUBLIC/pubA.git")" != "$(main_de "$PRIVE/compA.git")" ] || fail "3 : compA a été poussé malgré le refus"
propre "3"
pass "3 commit étranger sur UN public : refus, et rien n'est poussé nulle part"

# ── 3b. commit étranger sur le public du méta : seul « chore: URLs publiques » est toléré ──
depuis_zero
nouveau_commit "$WORK/compA" "compA : nouveau commit"
nouveau_commit "$ROOT" "méta : nouveau commit"
commit_etranger "$PUBLIC/POULIDOR.git" "feat: commit étranger sur le public du méta"
ETRANGER="$(main_de "$PUBLIC/POULIDOR.git")"
AVANT="$(publics)"
lancer --yes
doit_refuser "3b commit étranger sur le public du méta" "POULIDOR" "étranger" "${ETRANGER:0:7}"
inchange "3b aucun push sur aucun dépôt" "$AVANT" "$(publics)"
pass "3b commit étranger sur le public du méta : refus (le précédent commit d'adaptation, lui, est toléré — cas 2b)"

# ══ 4. garde OSS en échec : motif dans un nouveau commit privé → refus, aucun push ──
depuis_zero
printf 'hote = %s\n' "$LITTERAL" > "$WORK/compA/serveur.txt"
commit_dans "$WORK/compA" "ajout serveur"
git -C "$WORK/compA" push -q origin main
AVANT="$(publics)"
lancer --yes
doit_refuser "4 garde OSS en échec (composant)" "oss-guard" "compA" "serveur.txt:1"
hors_sortie "4 (la valeur interdite n'apparaît jamais en clair)" "$LITTERAL"
inchange "4 aucun push sur aucun dépôt" "$AVANT" "$(publics)"
propre "4"

# privé corrigé (le main privé revient en arrière), puis le méta fautif à son tour
BON_A="$(git -C "$PRIVE/compA.git" rev-parse main~1)"
git -C "$PRIVE/compA.git" branch -f main "$BON_A"
printf 'hote = %s\n' "$LITTERAL" > "$ROOT/serveur.txt"
nouveau_commit "$ROOT" "ajout serveur"
AVANT="$(publics)"
lancer --yes
doit_refuser "4b garde OSS en échec (méta)" "oss-guard" "POULIDOR" "serveur.txt:1"
hors_sortie "4b" "$LITTERAL"
inchange "4b aucun push sur aucun dépôt" "$AVANT" "$(publics)"
propre "4b"
pass "4 garde OSS : un motif dans un nouveau commit privé (composant ou méta) refuse tout, sans rien révéler"

# ── 4c. public vierge : tout l'historique est examiné, commit racine compris ──
monde_neuf
git -C "$WORK/compA" checkout -q --orphan racine
git -C "$WORK/compA" rm -q -rf .
printf 'hote = %s\n' "$LITTERAL" > "$WORK/compA/serveur.txt"
commit_dans "$WORK/compA" "commit racine"
git -C "$WORK/compA" push -q --force origin racine:main
[ "$(git -C "$PRIVE/compA.git" rev-list --count main)" -eq 1 ] || fail "4c fixture : compA devrait n'avoir qu'un commit racine"
AVANT="$(publics)"
lancer --yes
doit_refuser "4c valeur interdite dans le commit RACINE, public vierge" "oss-guard" "compA" "serveur.txt:1"
inchange "4c aucun push sur aucun dépôt" "$AVANT" "$(publics)"
pass "4c public vierge : la garde couvre tout l'historique, commit racine compris"

# ══ 5. clone de publication manquant → bootstrap depuis --root ══════════════
depuis_zero
rm -rf "$PUBLISH/compB"
lancer --yes
doit_accepter "5 clone compB manquant"
[ "$(git -C "$PUBLISH/compB" remote get-url origin)" = "$PRIVE/compB.git" ] || fail "5 : le clone réamorcé n'a pas l'URL privée lue dans --root"
[ "$(git -C "$PUBLISH/compB" remote get-url public)" = "$PUBLIC/pubB.git" ] || fail "5 : remote public du clone réamorcé"
dans_sortie "5" "compB"
[ "$(main_de "$PUBLIC/pubB.git")" = "$(main_de "$PRIVE/compB.git")" ] || fail "5 : compB non publié"

# tout manque : PUBLISH_DIR non défini → défaut ~/publish du HOME isolé, les trois clones sortent de --root
PUBLISH=""
rm -rf "$HOME/publish"
lancer --yes
doit_accepter "5b aucun clone : PUBLISH_DIR par défaut"
for d in compA compB POULIDOR; do
    [ "$(git -C "$HOME/publish/$d" remote get-url origin)" = "$PRIVE/$d.git" ] || fail "5b : origin de ~/publish/$d"
done
meta_public_sain 5b
PUBLISH="$TMP/publish"

# le remote public existe mais pointe ailleurs — vers un dépôt joignable, que
# seul ce contrôle peut refuser : erreur, rien n'est poussé
git init -q -b main --bare "$TMP/ailleurs.git"
git -C "$PUBLISH/compB" remote set-url public "$TMP/ailleurs.git"
nouveau_commit "$WORK/compB" "compB : nouveau commit"
AVANT="$(publics)"
lancer --yes
doit_refuser "5c remote public différent" "compB" "pointe ailleurs" "ailleurs.git"
inchange "5c aucun push sur aucun dépôt" "$AVANT" "$(publics)"
[ -z "$(git -C "$TMP/ailleurs.git" for-each-ref)" ] || fail "5c : le dépôt vers lequel pointait le remote divergent a reçu un push"
pass "5 clone de publication manquant : amorcé depuis --root (URL privée), remote public ajouté ; un remote public qui pointe ailleurs refuse"

# ── 5d. dépôt public injoignable : refus en pré-vol, avant le moindre push ──
depuis_zero
rm -rf "$PUBLIC/pubB.git"                        # le remote est correct, le dépôt ne répond plus
nouveau_commit "$WORK/compA" "compA : nouveau commit"
AVANT="$(publics)"
lancer --yes
doit_refuser "5d dépôt public injoignable" "compB" "injoignable"
inchange "5d aucun push sur aucun dépôt" "$AVANT" "$(publics)"
pass "5d dépôt public injoignable : détecté en pré-vol — un fetch en échec n'est jamais pris pour un public vide"

# ══ 6. --yes --verify : clone anonyme, sous-modules résolus, VERSION affiché ──
monde_neuf
lancer --yes --verify
doit_accepter "6 --yes --verify"
printf '%s\n' "$OUT" | sed 's/^/    /'
dans_sortie "6" "0.0.1"
printf '%s\n' "$OUT" | grep -q 'vérification' || fail "6 : aucune ligne de vérification"
pass "6 --verify : le méta public se clone anonymement avec ses sous-modules, et VERSION est affiché"

# ── 6b. --verify échoue : sous-modules publiés n'importe où (composants encore vierges) ──
monde_neuf
lancer --only POULIDOR --yes --verify
doit_refuser "6b --verify : sous-modules absents du public" "vérification"
pass "6b --verify signale un méta public dont les sous-modules ne se résolvent pas"

# ── 6c. --verify échoue : un sous-module n'est pas initialisé (update = none) ──
monde_neuf
printf '[submodule "compA"]\n\tpath = compA\n\turl = https://github.com/fakepriv/compA.git\n[submodule "compB"]\n\tpath = compB\n\turl = git@github.com:fakepriv/compB.git\n\tupdate = none\n' > "$ROOT/.gitmodules"
nouveau_commit "$ROOT" "méta : compB déclaré sans mise à jour"
lancer --yes --verify
doit_refuser "6c --verify : sous-module non initialisé" "vérification" "compB"
pass "6c --verify signale un sous-module que le clone anonyme n'a pas initialisé"

# ── 6d. --verify échoue : le méta public porte moins de sous-modules que la map n'a de composants ──
monde_neuf un-seul-sous-module
lancer --yes --verify
doit_refuser "6d --verify : un sous-module manque au méta public" "vérification" "attendu(s)"
pass "6d --verify compte les sous-modules du méta public contre les composants de la map"

# ══ 7. fichier de motifs absent ou vide → refus (fail-closed), avant tout clone ══
monde_neuf
MOTIFS="$TMP/jamais-cree.txt"
AVANT="$(publics)"
lancer --yes
doit_refuser "7 fichier de motifs absent" "fichier de motifs absent"
inchange "7 aucun push sur aucun dépôt" "$AVANT" "$(publics)"
[ ! -e "$PUBLISH" ] || fail "7 : un clone de publication a été créé avant le refus"
lancer
doit_refuser "7b fichier de motifs absent, dry-run" "fichier de motifs absent"
: > "$TMP/vide.txt"
MOTIFS="$TMP/vide.txt"
lancer --yes
doit_refuser "7c fichier de motifs vide" "motifs" "refus"
inchange "7c aucun push sur aucun dépôt" "$AVANT" "$(publics)"
MOTIFS=""                                       # emplacement par défaut, absent du HOME isolé
lancer --yes
doit_refuser "7d fichier de motifs par défaut absent" "fichier de motifs absent"
MOTIFS="$TMP/motifs.txt"
pass "7 fichier de motifs absent ou vide : refus avant tout clone, rien n'est poussé"

# ══ 8. usage : code 2, rien n'est touché ═════════════════════════════════════
monde_neuf
lancer --bogus
doit_usage "8a option inconnue"
lancer --only inconnu
doit_usage "8b --only <nom inconnu>"
lancer --only
doit_usage "8c --only sans nom"
lancer --root "$TMP/nulle-part"
doit_usage "8d --root introuvable"
printf 'compA pubA\n' > "$TMP/map-invalide.txt"
MAP="$TMP/map-invalide.txt"
lancer --yes
doit_usage "8e PUBLISH_MAP sans rôle"
printf 'compA pubA component\ncompB pubB component\nPOULIDOR POULIDOR meta\nautre X meta\n' > "$TMP/map-invalide.txt"
lancer --yes
doit_usage "8f PUBLISH_MAP avec deux méta"
MAP="$TMP/map.txt"
[ ! -e "$PUBLISH" ] || fail "8 : une erreur d'usage a touché les clones de publication"
lancer --help
[ "$RC" -eq 0 ] || fail "8 --help : rend $RC"
dans_sortie "8 --help" "--yes"
pass "8 usage : option inconnue, --only sans correspondance, --root introuvable, map malformée → code 2, rien n'est touché"

# ══ 9. push refusé en cours de route (hook pre-push) : on s'arrête, et le méta n'est jamais publié ──
depuis_zero
VIEUX_B="$(main_de "$PUBLIC/pubB.git")"; VIEUX_META="$(main_de "$PUBLIC/POULIDOR.git")"
nouveau_commit "$WORK/compA" "compA : nouveau commit"
nouveau_commit "$WORK/compB" "compB : nouveau commit"
nouveau_commit "$ROOT" "méta : nouveau commit"
mkdir -p "$PUBLISH/compB/.git/hooks"
printf '#!/usr/bin/env bash\necho "hook pre-push de test : refus" >&2\nexit 1\n' > "$PUBLISH/compB/.git/hooks/pre-push"
chmod +x "$PUBLISH/compB/.git/hooks/pre-push"
lancer --yes
doit_refuser "9 push refusé en cours de route" "compB" "hook pre-push de test : refus"
[ "$(main_de "$PUBLIC/pubA.git")" = "$(main_de "$PRIVE/compA.git")" ] || fail "9 : compA (passé avant) aurait dû être publié"
[ "$(main_de "$PUBLIC/pubB.git")" = "$VIEUX_B" ] || fail "9 : compB a bougé alors que son push a été refusé"
[ "$(main_de "$PUBLIC/POULIDOR.git")" = "$VIEUX_META" ] || fail "9 : le méta a été publié après l'échec d'un composant"
propre 9
pass "9 push refusé (hook pre-push, jamais contourné) : arrêt immédiat ; le méta n'est jamais publié derrière un composant en échec"

# ── 9b. public/main déplacé juste après le push (hook post-receive) : l'écart est vu, et on s'arrête ──
depuis_zero
VIEUX_META="$(main_de "$PUBLIC/POULIDOR.git")"
mkdir -p "$PUBLIC/pubA.git/hooks"
# shellcheck disable=SC2016  # le contenu du hook s'exécute dans le dépôt public, plus tard
printf '#!/usr/bin/env bash\ngit update-ref refs/heads/main "$(git rev-parse refs/heads/main~1)"\n' > "$PUBLIC/pubA.git/hooks/post-receive"
chmod +x "$PUBLIC/pubA.git/hooks/post-receive"
nouveau_commit "$WORK/compA" "compA : nouveau commit"
nouveau_commit "$ROOT" "méta : nouveau commit"
RECULE="$(git -C "$PRIVE/compA.git" rev-parse main~1)"     # là où le hook ramène public/main
lancer --yes
doit_refuser "9b public/main déplacé après le push" "compA" "attendu"
[ "$(main_de "$PUBLIC/pubA.git")" = "$RECULE" ] || fail "9b fixture : le hook post-receive aurait dû reculer public/main"
[ "$(main_de "$PUBLIC/POULIDOR.git")" = "$VIEUX_META" ] || fail "9b : le méta a été publié après une anomalie sur un composant"
pass "9b public/main ≠ sha poussé : vu par ls-remote, arrêt immédiat, le méta n'est pas publié"

# ══ 10. identité git absente : le commit d'adaptation échoue → refus, aucun push nulle part ──
monde_neuf
AVANT="$(publics)"
GIT_CONFIG_GLOBAL=/dev/null lancer --yes          # plus de configuration globale : plus d'identité
unset GIT_CONFIG_GLOBAL
doit_refuser "10 identité git absente" "POULIDOR" "adaptation"
inchange "10 aucun push sur aucun dépôt" "$AVANT" "$(publics)"
propre 10
pass "10 identité git absente : l'adaptation du méta échoue en pré-vol, aucun composant n'est poussé"

# ══ 11. post-contrôles de l'adaptation : une URL qui n'est pas publique refuse ──
monde_neuf
printf '[submodule "compA"]\n\tpath = compA\n\turl = ../compA.git\n[submodule "compB"]\n\tpath = compB\n\turl = https://github.com/fakepriv/compB.git\n' > "$ROOT/.gitmodules"
nouveau_commit "$ROOT" "méta : URL relative dans .gitmodules"
AVANT="$(publics)"
lancer --yes
doit_refuser "11a .gitmodules : url = hors de la base publique" ".gitmodules" "../compA.git"
inchange "11a aucun push sur aucun dépôt" "$AVANT" "$(publics)"
propre 11a

monde_neuf
printf '[submodule "compA"]\n\tpath = compA\n\turl = ssh://git@github.com/fakepriv/compA.git\n[submodule "compB"]\n\tpath = compB\n\turl = https://github.com/fakepriv/compB.git\n' > "$ROOT/.gitmodules"
nouveau_commit "$ROOT" "méta : URL ssh:// dans .gitmodules"
AVANT="$(publics)"
lancer --yes
doit_refuser "11b .gitmodules : URL ssh:// git@, forme inconnue de la réécriture" ".gitmodules" "git@"
inchange "11b aucun push sur aucun dépôt" "$AVANT" "$(publics)"

monde_neuf
printf '{\n  "compA": "https://github.com/fakepriv/compA.git",\n  "compB": "git@github.com:fakepriv/compB.git",\n  "autre": "https://github.com/fakepriv/autre.git"\n}\n' > "$ROOT/manifest.json"
nouveau_commit "$ROOT" "méta : composant hors map dans manifest.json"
AVANT="$(publics)"
lancer --yes
doit_refuser "11c manifest.json : URL d'un composant hors map" "manifest.json" "fakepriv/autre.git"
inchange "11c aucun push sur aucun dépôt" "$AVANT" "$(publics)"
propre 11c
monde_neuf
printf '{\n  "compA": "https://github.com/fakepriv/compA.git",\n  "compB": "git@github.com:fakepriv/compB.git",\n  "autre": "git@gitlab.example:org/autre.git"\n}\n' > "$ROOT/manifest.json"
nouveau_commit "$ROOT" "méta : URL ssh d'une autre forge dans manifest.json"
AVANT="$(publics)"
lancer --yes
doit_refuser "11d manifest.json : URL ssh git@ d'une autre forge" "manifest.json" "git@gitlab.example"
inchange "11d aucun push sur aucun dépôt" "$AVANT" "$(publics)"
propre 11d
pass "11 post-contrôles : url = hors base publique, URL ssh git@, URL privée hors map dans manifest → refus, rien n'est poussé"

echo ""
echo "🎉 Tous les tests passent."
