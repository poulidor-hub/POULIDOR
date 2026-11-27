#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_vm_push_branch.sh — régression : vm_push_branch (scripts/lib/vm-debian12.sh)
# pousse le méta ET tous ses sous-modules dans une VM par bundles git.
#
# Bugs constatés à chaque passage en labo (26/11/2026) :
#   - liste codée en dur de 5 sous-modules → HUBsocle jamais bundlé ;
#   - ~/POULIDOR et ~/POULIDOR/<sub> supposés déjà clonés → VM neuve en échec ;
#   - `|| true` partout → échecs avalés en silence ;
#   - clone d'un bundle sans -b → HEAD indéterminé ;
#   - origins (méta et sous-modules) laissées sur le chemin du bundle, dossier
#     détruit en fin d'appel → tout fetch ultérieur dans la VM échoue.
#
# Fixture : un méta factice et 3 sous-modules aux noms quelconques (compA,
# compB, soclex : la liste doit être DÉCOUVERTE dans .gitmodules), 2 commits
# chacun, URL enregistrée INJOIGNABLE — comme GitHub sans nos SHA : si un
# sous-module allait chercher son commit à son URL, le cas échouerait.
#
# La lib est copiée dans le méta (elle y calcule sa racine), puis vm_ssh et
# vm_scp sont remplacées : les commandes « distantes » tournent réellement en
# local, avec le HOME d'une fausse VM — l'état final se vérifie sur disque.

# shellcheck disable=SC2317  # vm_ssh / vm_scp remplacées : appelées par la lib, jamais ici
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/scripts/lib/vm-debian12.sh"
BRANCH="main"
SUBS=(compA compB soclex)

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

[ -f "$LIB" ] || fail "scripts/lib/vm-debian12.sh absent"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/vm-push-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
ORIG_TRAP="$(trap -p EXIT)"

# Les bundles côté hôte (dossier mktemp de la lib) vivent dans la fixture :
# on peut alors vérifier qu'aucun ne survit à l'appel.
export TMPDIR="$TMP/host-tmp"
mkdir -p "$TMPDIR"

META="$TMP/meta"        # le méta, côté hôte — la lib copiée y prend racine
VMHOME="$TMP/vmhome"    # HOME de la « VM »
VMP="$VMHOME/POULIDOR"
VMTMP="$VMHOME/tmp"     # le /tmp de la « VM »
mkdir -p "$VMTMP" "$TMP/origin"

# ── Fixture ──────────────────────────────────────────────────────────────────
gitcfg() { # identité des commits de la fixture, sans signature
  git -C "$1" config user.email test@local
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
}

mkcomponent() { # mkcomponent <nom> : dépôt bare + 2 commits, ajouté au méta comme sous-module
  local name="$1" seed="$TMP/seed-$1"
  git init -q --bare -b main "$TMP/origin/$name.git"
  git init -q -b main "$seed"
  gitcfg "$seed"
  echo "$name 1" > "$seed/README.md"
  git -C "$seed" add README.md && git -C "$seed" commit -qm "$name c1"
  echo "$name 2" >> "$seed/README.md"
  git -C "$seed" commit -qam "$name c2"
  git -C "$seed" push -q "$TMP/origin/$name.git" main
  git -C "$META" -c protocol.file.allow=always submodule add -q "$TMP/origin/$name.git" "$name"
  gitcfg "$META/$name"
  # URL enregistrée injoignable : le sous-module ne peut venir QUE du bundle
  git -C "$META" config --file .gitmodules "submodule.$name.url" "$TMP/unreachable/$name.git"
  git -C "$META" add .gitmodules "$name"
  git -C "$META" commit -qm "méta : sous-module $name"
}

git init -q -b main "$META"
gitcfg "$META"
echo méta > "$META/README.md"
git -C "$META" add README.md && git -C "$META" commit -qm "méta c1"
for s in "${SUBS[@]}"; do mkcomponent "$s"; done

mkdir -p "$META/scripts/lib"
cp "$LIB" "$META/scripts/lib/vm-debian12.sh"
# shellcheck disable=SC1091  # lib sous test, copiée dans la fixture
source "$META/scripts/lib/vm-debian12.sh"

# ssh colle les arguments avec des espaces et confie la ligne au shell de
# connexion ; scp copie vers ce qui suit « hôte: ». HOME et TMPDIR = la « VM ».
vm_ssh() { HOME="$VMHOME" TMPDIR="$VMTMP" bash -c "$*"; }
vm_scp() { cp "$1" "${2#*:}"; }

# ── Outils ───────────────────────────────────────────────────────────────────
RC=0 OUT=""
run_push() { # run_push [origin_méta] : vm_push_branch $BRANCH [origin] → RC (retour), OUT (stdout+stderr)
  RC=0
  vm_push_branch "$BRANCH" "${1:-}" >"$TMP/out.log" 2>&1 || RC=$?
  OUT="$(cat "$TMP/out.log")"
}

assert_clean() { # assert_clean <cas> : aucun bundle résiduel, ni côté hôte ni dans la « VM »
  local r
  r="$(ls -A "$TMPDIR")"
  [ -z "$r" ] || fail "$1 : bundle(s) résiduel(s) côté hôte : $r"
  r="$(find "$VMTMP" -mindepth 1)"
  [ -z "$r" ] || fail "$1 : résidu dans le /tmp de la VM : $r"
}

assert_state() { # assert_state <cas> <sous-module>… : méta sur $BRANCH au commit bundlé,
  #               chaque sous-module initialisé, sans branche fi-sub, au HEAD de l'hôte
  local cas="$1" sub st
  shift
  st="$(git -C "$VMP" submodule status)" || fail "$cas : git submodule status en échec — $OUT"
  [ "$(printf '%s\n' "$st" | wc -l)" -eq "$#" ] \
    || fail "$cas : $# sous-module(s) attendus, état lu :"$'\n'"$st"
  if printf '%s\n' "$st" | grep '^[-+U]' >/dev/null; then
    fail "$cas : sous-module non initialisé (-), déplacé (+) ou en conflit (U) :"$'\n'"$st"
  fi
  for sub in "$@"; do
    [ "$(git -C "$VMP/$sub" rev-parse HEAD)" = "$(git -C "$META/$sub" rev-parse HEAD)" ] \
      || fail "$cas : $sub n'est pas au HEAD bundlé"
    [ "$(cat "$VMP/$sub/README.md")" = "$(git -C "$META/$sub" show "HEAD:README.md")" ] \
      || fail "$cas : $sub : les fichiers de travail ne sont pas à HEAD"
    [ -z "$(git -C "$VMP/$sub" for-each-ref --format='%(refname)' refs/heads/fi-sub)" ] \
      || fail "$cas : branche fi-sub résiduelle dans $sub"
  done
  [ "$(git -C "$VMP" rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || fail "$cas : le méta n'est pas sur $BRANCH"
  [ "$(git -C "$VMP" rev-parse HEAD)" = "$(git -C "$META" rev-parse "$BRANCH")" ] \
    || fail "$cas : le méta n'est pas au commit bundlé"
}

assert_origins() { # assert_origins <cas> <sous-module>… : origins des sous-modules propres —
  #   (a) aucun remote.origin.url ne pointe dans le dossier de bundles détruit (il vivait dans $VMTMP)
  #   (b) chaque remote.origin.url == URL .gitmodules correspondante
  local cas="$1" sub url want
  shift
  for sub in "$@"; do
    url="$(git -C "$VMP/$sub" config --get remote.origin.url)" \
      || fail "$cas : $sub : remote.origin.url illisible"
    case "$url" in
      "$VMTMP"|"$VMTMP"/*) fail "$cas : $sub : origin pointe dans le dossier de bundles détruit : $url" ;;
    esac
    want="$(git -C "$META" config --file .gitmodules --get "submodule.$sub.url")"
    [ "$url" = "$want" ] || fail "$cas : $sub : origin « $url » ≠ URL .gitmodules « $want »"
  done
}

# ── 1. VM neuve : aucun ~/POULIDOR ───────────────────────────────────────────
run_push
[ "$RC" -eq 0 ] || fail "1. VM neuve : vm_push_branch rend $RC — sortie :"$'\n'"$OUT"
assert_state "1. VM neuve" "${SUBS[@]}"
for s in "${SUBS[@]}"; do
  [ "$(git -C "$VMP" config --get "submodule.$s.url")" = "$TMP/unreachable/$s.git" ] \
    || fail "1. VM neuve : URL de $s non enregistrée (submodule init)"
done
assert_origins "1. VM neuve" "${SUBS[@]}"
assert_clean "1. VM neuve"
pass "1. VM neuve : méta cloné sur $BRANCH, 3 sous-modules au HEAD bundlé, sans aller chercher leur URL"

# ── 2. Relance : tout existe déjà ────────────────────────────────────────────
BEFORE="$(git -C "$VMP" rev-parse HEAD) $(for s in "${SUBS[@]}"; do git -C "$VMP/$s" rev-parse HEAD; done)"
run_push
[ "$RC" -eq 0 ] || fail "2. Relance : vm_push_branch rend $RC — sortie :"$'\n'"$OUT"
assert_state "2. Relance" "${SUBS[@]}"
assert_clean "2. Relance"
AFTER="$(git -C "$VMP" rev-parse HEAD) $(for s in "${SUBS[@]}"; do git -C "$VMP/$s" rev-parse HEAD; done)"
[ "$AFTER" = "$BEFORE" ] || fail "2. Relance : l'état de la VM a changé : '$BEFORE' → '$AFTER'"
pass "2. Relance : même état, aucun bundle résiduel, aucune branche fi-sub"

# ── 3. Sous-module en retard + commit pas sur l'origin ───────────────────────
# compB : nouveau commit côté hôte, jamais poussé sur origin (le cas du labo) ;
# soclex : la VM est restée à l'ancien commit.
echo "compB 3" >> "$META/compB/README.md"
git -C "$META/compB" commit -qam "compB c3 (local uniquement)"
git -C "$META" add compB && git -C "$META" commit -qm "méta : bump compB"
OLD_SOCLEX="$(git -C "$META/soclex" rev-parse HEAD~1)"
git -C "$VMP/soclex" checkout -q --detach "$OLD_SOCLEX"
[ "$(git -C "$VMP/soclex" rev-parse HEAD)" = "$OLD_SOCLEX" ] || fail "3. fixture : soclex pas à l'ancien commit"
run_push
[ "$RC" -eq 0 ] || fail "3. Sous-module en retard : vm_push_branch rend $RC — sortie :"$'\n'"$OUT"
assert_state "3. Sous-module en retard" "${SUBS[@]}"
assert_clean "3. Sous-module en retard"
[ "$(git -C "$VMP/compB" rev-parse HEAD)" = "$(git -C "$META/compB" rev-parse HEAD)" ] \
  || fail "3. : compB n'a pas reçu son commit local"
pass "3. Sous-module en retard : repositionné au HEAD bundlé ; commit jamais poussé : transmis"

# ── 4. Échec propagé ─────────────────────────────────────────────────────────
# Rien ne doit partir tant que tout n'est pas prêt : compA reçoit un commit
# local (bump du méta) qui ne doit PAS arriver à la VM quand un autre dépôt casse.
echo "compA 3" >> "$META/compA/README.md"
git -C "$META/compA" commit -qam "compA c3 (local uniquement)"
git -C "$META" add compA && git -C "$META" commit -qm "méta : bump compA"
VMP_HEAD="$(git -C "$VMP" rev-parse HEAD)" VMP_COMPA="$(git -C "$VMP/compA" rev-parse HEAD)"

# 4a. dépôt local cassé (HEAD illisible) → retour non-zéro + message
SOCLEX_GD="$(git -C "$META/soclex" rev-parse --absolute-git-dir)"
cp "$SOCLEX_GD/HEAD" "$TMP/soclex.HEAD.save"
echo "ref: refs/heads/disparue" > "$SOCLEX_GD/HEAD"
run_push
cp "$TMP/soclex.HEAD.save" "$SOCLEX_GD/HEAD"
[ "$RC" -ne 0 ] || fail "4a. dépôt local cassé : vm_push_branch rend 0 — sortie :"$'\n'"$OUT"
echo "$OUT" | grep -q '✗ vm_push_branch' || fail "4a. dépôt local cassé : pas de message — sortie :"$'\n'"$OUT"
echo "$OUT" | grep -q 'soclex' || fail "4a. dépôt local cassé : le sous-module fautif n'est pas nommé — sortie :"$'\n'"$OUT"
[ "$(git -C "$VMP" rev-parse HEAD)" = "$VMP_HEAD" ] || fail "4a. : le méta de la VM a bougé alors que l'appel a échoué"
[ "$(git -C "$VMP/compA" rev-parse HEAD)" = "$VMP_COMPA" ] || fail "4a. : compA a bougé alors que l'appel a échoué"
assert_clean "4a."
pass "4a. dépôt local cassé : non-zéro + message, rien envoyé"

# 4b. vm_scp en échec → retour non-zéro + message
vm_scp() { echo "scp: erreur simulée" >&2; return 255; }
run_push
vm_scp() { cp "$1" "${2#*:}"; }
[ "$RC" -ne 0 ] || fail "4b. vm_scp en échec : vm_push_branch rend 0 — sortie :"$'\n'"$OUT"
echo "$OUT" | grep -q '✗ vm_push_branch' || fail "4b. vm_scp en échec : pas de message — sortie :"$'\n'"$OUT"
assert_clean "4b."
pass "4b. vm_scp en échec : non-zéro + message, bundles retirés"

# 4c. commande distante en échec : ~/POULIDOR existe sans dépôt, non vide
mv "$VMP" "$TMP/POULIDOR.save"
mkdir "$VMP" && echo viellerie > "$VMP/README.md"
run_push
[ "$RC" -ne 0 ] || fail "4c. commande distante en échec : vm_push_branch rend 0 — sortie :"$'\n'"$OUT"
echo "$OUT" | grep -q '✗ vm_push_branch' || fail "4c. commande distante en échec : pas de message — sortie :"$'\n'"$OUT"
assert_clean "4c."
[ "$(cat "$VMP/README.md")" = viellerie ] || fail "4c. : le dossier préexistant a été écrasé"
rm -rf "$VMP" && mv "$TMP/POULIDOR.save" "$VMP"
pass "4c. commande distante en échec : non-zéro + message, bundles retirés"

# 4d. commande distante en échec, sur UN sous-module : son dépôt est cassé dans la VM
rm -rf "$VMP/compB/.git" && echo cassé > "$VMP/compB/.git"
run_push
[ "$RC" -ne 0 ] || fail "4d. sous-module cassé côté VM : vm_push_branch rend 0 — sortie :"$'\n'"$OUT"
echo "$OUT" | grep -q 'compB' || fail "4d. sous-module cassé côté VM : le sous-module fautif n'est pas nommé — sortie :"$'\n'"$OUT"
assert_clean "4d."
pass "4d. sous-module cassé côté VM : non-zéro + message nommant le sous-module"

# L'appel sain qui suit remet la VM entière à l'état attendu, compB compris :
# son dossier a disparu (comme après `rm -rf ~/POULIDOR/compB`) → recloné depuis le bundle
rm -rf "$VMP/compB"
run_push
[ "$RC" -eq 0 ] || fail "4. retour à la normale : vm_push_branch rend $RC — sortie :"$'\n'"$OUT"
assert_state "4. retour à la normale" "${SUBS[@]}"
assert_clean "4. retour à la normale"
pass "4. après réparation : un appel remet la VM entière à l'état attendu (sous-module manquant recloné)"

# ── 5. Aucune liste en dur : un 4ᵉ sous-module arrive ────────────────────────
mkcomponent compD
run_push
[ "$RC" -eq 0 ] || fail "5. 4ᵉ sous-module : vm_push_branch rend $RC — sortie :"$'\n'"$OUT"
assert_state "5. 4ᵉ sous-module" "${SUBS[@]}" compD
assert_clean "5. 4ᵉ sous-module"
pass "5. 4ᵉ sous-module : bundlé sans rien changer au script"

# ── 6. Sous-module non initialisé côté hôte : ignoré, avec avertissement ──────
mv "$META/compD/.git" "$TMP/compD.git.save"
run_push
mv "$TMP/compD.git.save" "$META/compD/.git"
[ "$RC" -eq 0 ] || fail "6. sous-module non initialisé : vm_push_branch rend $RC — sortie :"$'\n'"$OUT"
echo "$OUT" | grep -q 'compD' || fail "6. sous-module non initialisé : pas d'avertissement — sortie :"$'\n'"$OUT"
assert_clean "6."
pass "6. sous-module non initialisé côté hôte : ignoré, signalé"

# ── 7. Interruption en cours d'appel (Ctrl-C) : trap ─────────────────────────
# Un signal au milieu d'une copie : les bundles partent des deux côtés, et le
# trap EXIT de l'appelant (ex. destruction de la VM par le harnais) s'exécute.
: > "$TMP/chain.log"
RC=0
(
  trap 'echo "trap de l'"'"'appelant" >> "$TMP/chain.log"' EXIT
  vm_scp() { kill -INT "$BASHPID"; }
  vm_push_branch "$BRANCH"
) || RC=$?
[ "$RC" -ne 0 ] || fail "7. interruption : l'appel aurait dû échouer"
grep -q "trap de l'appelant" "$TMP/chain.log" || fail "7. interruption : le trap EXIT de l'appelant n'a pas été chaîné"
assert_clean "7. interruption"
pass "7. interruption en cours d'appel : bundles retirés, trap EXIT de l'appelant chaîné"

# ── 8. Origin du méta passée à l'appel ───────────────────────────────────────
# Le clone neuf du méta vient du bundle (détruit ensuite) : l'appelant qui
# connaît la vraie URL (ex. $CLONE_URL du harness) la repose en 2ᵉ argument.
META_ORIGIN="https://github.com/poulidor-hub/POULIDOR.git"
run_push "$META_ORIGIN" || fail "8. origin du méta : vm_push_branch en échec — sortie :"$'\n'"$OUT"
[ "$(git -C "$VMP" config --get remote.origin.url)" = "$META_ORIGIN" ] \
  || fail "8. origin du méta : remote.origin.url « $(git -C "$VMP" config --get remote.origin.url) » ≠ « $META_ORIGIN »"
assert_state "8. origin du méta" "${SUBS[@]}" compD
assert_origins "8. origin du méta" "${SUBS[@]}" compD
assert_clean "8. origin du méta"
# Relance sans argument : l'origine posée doit survivre (le méta existe déjà,
# aucun re-clone depuis un bundle).
run_push "" || fail "8. relance : vm_push_branch en échec — sortie :"$'\n'"$OUT"
[ "$(git -C "$VMP" config --get remote.origin.url)" = "$META_ORIGIN" ] \
  || fail "8. relance : l'origin du méta a été écrasée : $(git -C "$VMP" config --get remote.origin.url)"
assert_origins "8. relance" "${SUBS[@]}" compD
pass "8. origin du méta : posée en 2ᵉ argument, survit à une relance sans argument ; sous-modules toujours sur .gitmodules"

# Le trap EXIT de CE script doit avoir survécu à tous les appels
[ "$(trap -p EXIT)" = "$ORIG_TRAP" ] || fail "le trap EXIT de l'appelant n'a pas été rendu : $(trap -p EXIT)"
pass "trap EXIT de l'appelant rendu intact après chaque appel"

echo ""
echo "🎉 Tous les tests passent."
