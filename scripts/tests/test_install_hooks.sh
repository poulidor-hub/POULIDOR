#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_install_hooks.sh — régression : install-hooks.sh doit être idempotent,
# chaîner sans écraser un hook existant, et couvrir les sous-modules (--all).
#
# Fixture : superprojets temporaires (« méta ») avec un sous-module, clonés
# d'origines locales. Les scripts du pare-feu sont remplacés par des factices
# qui se signalent (GL, AUTH, GUARD) : les hooks installés sont exercés par de
# VRAIS `git commit` et `git push`, pour vérifier qui appelle quoi, dans quel
# ordre, et avec quelle entrée standard.
set -euo pipefail

SCRIPT_UNDER_TEST="$(cd "$(dirname "$0")/../hooks" && pwd)/install-hooks.sh"
MARQUEUR='# --- pare-feu open source (install-hooks) ---'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-install-hooks.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Hermétique : ni la configuration globale ni la configuration système de git
# de la personne qui lance le test (signature, hooks globaux…) n'interviennent.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

identite() { git -C "$1" config user.email test@example.org; git -C "$1" config user.name test; }
hooks_de() {  # dossier de hooks de <dépôt>, en chemin absolu
    local h
    h="$(git -C "$1" rev-parse --git-path hooks)"
    case "$h" in /*) ;; *) h="$1/$h" ;; esac
    printf '%s\n' "$h"
}
run_installateur() {  # run_installateur <méta> [options…] : lance l'installateur, renseigne RC et OUT
    local m="$1"; shift
    set +e
    OUT="$(cd "$m" && bash "$m/scripts/hooks/install-hooks.sh" "$@" 2>&1)"
    RC=$?
    set -e
}

# ── Scripts factices du pare-feu ─────────────────────────────────────────────
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/pre-commit-gitleaks.sh" <<'EOF'
#!/usr/bin/env bash
echo "GL"
exit "${STUB_GL_RC:-0}"
EOF
cat > "$STUBS/check-author.sh" <<'EOF'
#!/usr/bin/env bash
echo "AUTH"
EOF
cat > "$STUBS/pre-push-oss-guard.sh" <<'EOF'
#!/usr/bin/env bash
echo "GUARD"
cat
exit "${STUB_GUARD_RC:-0}"
EOF
chmod +x "$STUBS"/*.sh

# ── Origines, puis superprojets clonés avec leur sous-module « sub » ─────────
git init -q -b main --bare "$TMP/origin_meta.git"
git init -q -b main --bare "$TMP/origin_sub.git"

git clone -q "$TMP/origin_sub.git" "$TMP/amorce_sub" 2>/dev/null
identite "$TMP/amorce_sub"
echo sub > "$TMP/amorce_sub/README.md"
git -C "$TMP/amorce_sub" add README.md
git -C "$TMP/amorce_sub" commit -qm "init sub"
git -C "$TMP/amorce_sub" push -q origin main

git clone -q "$TMP/origin_meta.git" "$TMP/amorce_meta" 2>/dev/null
identite "$TMP/amorce_meta"
echo meta > "$TMP/amorce_meta/README.md"
git -C "$TMP/amorce_meta" add README.md
git -C "$TMP/amorce_meta" commit -qm "init meta"
git -C "$TMP/amorce_meta" -c protocol.file.allow=always submodule add -q "$TMP/origin_sub.git" sub
git -C "$TMP/amorce_meta" commit -qm "add submodule"
git -C "$TMP/amorce_meta" push -q origin main

outils() {  # outils <méta> : l'installateur testé et les scripts factices, dans le méta de la fixture
    local m="$1"
    mkdir -p "$m/scripts/hooks"
    cp "$SCRIPT_UNDER_TEST" "$m/scripts/hooks/install-hooks.sh"
    cp "$STUBS"/*.sh "$m/scripts/hooks/"
}
superprojet() {  # superprojet <répertoire> : clone + sous-module initialisé + outils du méta
    local m="$1"
    git -c protocol.file.allow=always clone -q --recurse-submodules "$TMP/origin_meta.git" "$m" 2>/dev/null
    identite "$m"
    identite "$m/sub"
    outils "$m"
}

# ══ A. Le contrat du brief ═══════════════════════════════════════════════════
# Méta sans hook ; sous-module dont le pre-commit contient déjà « echo custom ».
META="$TMP/meta"
superprojet "$META"
SUB="$META/sub"
HM="$(hooks_de "$META")"     # hooks du méta
HS="$(hooks_de "$SUB")"      # hooks du sous-module
mkdir -p "$HS"
printf '#!/usr/bin/env bash\necho custom\n' > "$HS/pre-commit"
chmod +x "$HS/pre-commit"
CUSTOM_AVANT="$(sha256sum "$HS/pre-commit")"

# ── 1. sans --all : le méta seul, marqueur une fois ──────────────────────────
run_installateur "$META"
echo "$OUT"
[ "$RC" -eq 0 ] || fail "A1 première exécution : l'installateur rend $RC"
[ "$(grep -cF "$MARQUEUR" "$HM/pre-commit")" -eq 1 ] \
    || fail "A1 pre-commit du méta : marqueur présent $(grep -cF "$MARQUEUR" "$HM/pre-commit" || true) fois, attendu 1"
[ -x "$HM/pre-commit" ] || fail "A1 pre-commit du méta : non exécutable"
echo "$OUT" | grep -q "installé" || fail "A1 sortie sans « installé »"
pass "A1 sans --all : pre-commit du méta installé, marqueur une fois, exécutable"

# ── 5. sans --all : aucun hook créé dans le sous-module ──────────────────────
[ ! -e "$HS/pre-push" ] || fail "A5 sans --all : pre-push créé dans le sous-module"
[ "$CUSTOM_AVANT" = "$(sha256sum "$HS/pre-commit")" ] || fail "A5 sans --all : le pre-commit existant du sous-module a changé"
pass "A5 sans --all : aucun hook créé dans le sous-module"

# ── 2. seconde exécution : fichiers identiques ───────────────────────────────
AVANT="$(sha256sum "$HM/pre-commit" "$HM/pre-push")"
run_installateur "$META"
[ "$RC" -eq 0 ] || fail "A2 seconde exécution : l'installateur rend $RC"
[ "$AVANT" = "$(sha256sum "$HM/pre-commit" "$HM/pre-push")" ] || fail "A2 seconde exécution : les hooks du méta ont changé"
[ "$(echo "$OUT" | grep -c "déjà présent")" -eq 2 ] || fail "A2 « déjà présent » attendu 2 fois — sortie : $OUT"
pass "A2 seconde exécution : fichiers identiques, « déjà présent » ×2"

# ── 3. avec --all : chaînage après le hook existant du sous-module ───────────
run_installateur "$META" --all
echo "$OUT"
[ "$RC" -eq 0 ] || fail "A3 --all : l'installateur rend $RC"
[ "$(grep -cF 'echo custom' "$HS/pre-commit")" -eq 1 ] || fail "A3 « echo custom » n'est plus présent une fois dans le pre-commit du sous-module"
[ "$(grep -cF "$MARQUEUR" "$HS/pre-commit")" -eq 1 ] \
    || fail "A3 marqueur présent $(grep -cF "$MARQUEUR" "$HS/pre-commit" || true) fois dans le sous-module, attendu 1"
[ -x "$HS/pre-commit" ] || fail "A3 pre-commit du sous-module non exécutable"
[ -x "$HS/pre-push" ] || fail "A3 pre-push du sous-module non exécutable"
echo "$OUT" | grep -q "chaîné après un hook existant" || fail "A3 sortie sans « chaîné après un hook existant »"
pass "A3 avec --all : pre-commit du sous-module chaîné (echo custom + marqueur, une fois chacun), exécutable"

# ── 4. second --all : fichiers identiques ────────────────────────────────────
TOUS=("$HM/pre-commit" "$HM/pre-push" "$HS/pre-commit" "$HS/pre-push")
AVANT="$(sha256sum "${TOUS[@]}")"
run_installateur "$META" --all
[ "$RC" -eq 0 ] || fail "A4 second --all : l'installateur rend $RC"
[ "$AVANT" = "$(sha256sum "${TOUS[@]}")" ] || fail "A4 second --all : les hooks ont changé"
[ "$(echo "$OUT" | grep -c "déjà présent")" -eq 4 ] || fail "A4 « déjà présent » attendu 4 fois — sortie : $OUT"
pass "A4 second --all : fichiers identiques, « déjà présent » ×4"

# ── Le pre-commit du sous-module, par un vrai commit ─────────────────────────
set +e
OUT="$(git -C "$SUB" commit --allow-empty -m "x" 2>&1)"; RC=$?
set -e
echo "$OUT"
[ "$RC" -eq 0 ] || fail "commit du sous-module : rend $RC — sortie : $OUT"
for attendu in custom GL AUTH; do
    [ "$(echo "$OUT" | grep -c "^$attendu\$")" -eq 1 ] || fail "commit du sous-module : « $attendu » attendu une fois — sortie : $OUT"
done
[ "$(echo "$OUT" | grep -n '^GL$' | cut -d: -f1)" -lt "$(echo "$OUT" | grep -n '^AUTH$' | cut -d: -f1)" ] \
    || fail "commit du sous-module : GL doit précéder AUTH — sortie : $OUT"
pass "commit du sous-module : hook existant conservé, gitleaks puis auteur appelés"

# ══ B. Un hook existant doit rester effectif, et le pare-feu avec ═════════════
# État réel des checkouts principaux du parc : un pre-commit existant qui se
# termine par « exit 0 » (ancienne copie du script gitleaks), et un pre-push
# existant qui lit toute l'entrée standard (garde-version). Un bloc ajouté
# après eux ne s'exécuterait jamais, ou lirait une entrée standard vide.
META2="$TMP/meta2"
superprojet "$META2"
SUB2="$META2/sub"
HM2="$(hooks_de "$META2")"
HS2="$(hooks_de "$SUB2")"
mkdir -p "$HM2" "$HS2"
printf '#!/usr/bin/env bash\necho "legacy"\nexit 0\n' > "$HM2/pre-commit"
printf '#!/usr/bin/env bash\necho custom\n' > "$HS2/pre-commit"
cat > "$HS2/pre-push" <<'EOF'
#!/usr/bin/env bash
n=0
while read -r locale sha_l distante sha_d; do n=$((n + 1)); done
echo "legacy-pre-push:$n"
[ -z "${LEGACY_PP_FAIL:-}" ]
EOF
chmod +x "$HM2/pre-commit" "$HS2/pre-commit" "$HS2/pre-push"
git -C "$SUB2" checkout -q -b travail   # une branche nommée : ligne de référence déterministe
run_installateur "$META2" --all
[ "$RC" -eq 0 ] || fail "B installation : l'installateur rend $RC — sortie : $OUT"

git_commit() {  # git_commit <dépôt> [VAR=valeur …] : vrai commit ; RC et OUT
    local d="$1"; shift
    set +e
    OUT="$(env "$@" git -C "$d" commit --allow-empty -m "x" 2>&1)"; RC=$?
    set -e
}
# Vrai push, l'entrée standard du hook étant fournie par git lui-même. Le
# dossier temporaire est dédié, pour vérifier qu'aucun fichier ne survit.
TMPD="$TMP/tmp-push"
mkdir -p "$TMPD"
git_push() {  # git_push <dépôt> <branche locale> <branche distante> [VAR=valeur …] : RC et OUT
    local d="$1" src="$2" br="$3"; shift 3
    set +e
    OUT="$(env "$@" TMPDIR="$TMPD" git -C "$d" push -q origin "$src:refs/heads/$br" 2>&1)"; RC=$?
    set -e
}
ref_lue() {  # la ligne de référence que git fournit au pre-push, répercutée par la garde factice
    echo "$OUT" | grep -c "^refs/heads/$1 [0-9a-f]\\{40\\} refs/heads/$2 0\\{40\\}\$"
}
ref_absente() {  # ref_absente <dépôt nu> <branche> : la branche n'a pas été poussée
    ! git -C "$1" rev-parse --verify -q "refs/heads/$2" >/dev/null
}

# ── B1. pre-commit existant terminé par « exit 0 » : le pare-feu passe quand même ─
git_commit "$META2"
echo "$OUT"
[ "$RC" -eq 0 ] || fail "B1 commit du méta : rend $RC — sortie : $OUT"
for attendu in GL AUTH legacy; do
    [ "$(echo "$OUT" | grep -c "^$attendu\$")" -eq 1 ] || fail "B1 « $attendu » attendu une fois — sortie : $OUT"
done
pass "B1 hook existant terminé par exit 0 : gitleaks et auteur appelés, l'existant aussi"

# ── B2. pre-push existant qui lit l'entrée standard : la garde reçoit les références ─
git_push "$SUB2" travail topic
echo "$OUT"
[ "$RC" -eq 0 ] || fail "B2 push du sous-module : rend $RC — sortie : $OUT"
[ "$(echo "$OUT" | grep -c '^GUARD$')" -eq 1 ] || fail "B2 « GUARD » attendu une fois — sortie : $OUT"
[ "$(ref_lue travail topic)" -eq 1 ] || fail "B2 la garde pre-push n'a pas reçu la ligne de référence de git — sortie : $OUT"
[ "$(echo "$OUT" | grep -c '^legacy-pre-push:1$')" -eq 1 ] || fail "B2 le hook existant n'a plus reçu la référence — sortie : $OUT"
pass "B2 pre-push chaîné : la garde et le hook existant lisent tous deux l'entrée standard"

# ── B3. pre-push sans hook existant : la garde lit l'entrée standard de git ──
git_push "$META2" main topic
echo "$OUT"
[ "$RC" -eq 0 ] || fail "B3 push du méta : rend $RC — sortie : $OUT"
[ "$(ref_lue main topic)" -eq 1 ] || fail "B3 la garde pre-push n'a pas reçu la ligne de référence de git — sortie : $OUT"
pass "B3 pre-push installé seul : la garde lit l'entrée standard de git"

# ── B4. « || exit 1 » : un refus de gitleaks arrête le hook ──────────────────
git_commit "$SUB2" STUB_GL_RC=1
echo "$OUT"
[ "$RC" -ne 0 ] || fail "B4 gitleaks refuse : le commit a réussi — sortie : $OUT"
[ "$(echo "$OUT" | grep -c '^GL$')" -eq 1 ] || fail "B4 gitleaks factice non appelé — sortie : $OUT"
[ "$(echo "$OUT" | grep -c '^AUTH$')" -eq 0 ] || fail "B4 la garde d'identité a été appelée après un refus — sortie : $OUT"
pass "B4 refus de gitleaks : commit refusé, garde d'identité non appelée"

# ── B5. un refus de la garde pre-push bloque le push ─────────────────────────
git_push "$SUB2" travail refuse STUB_GUARD_RC=1
echo "$OUT"
[ "$RC" -ne 0 ] || fail "B5 la garde refuse : le push a réussi — sortie : $OUT"
ref_absente "$TMP/origin_sub.git" refuse || fail "B5 la branche refusée a été poussée"
pass "B5 refus de la garde pre-push : push refusé, rien sur l'origine"

# ── B6. un échec du hook existant n'est pas masqué par le pare-feu ───────────
git_push "$SUB2" travail masque LEGACY_PP_FAIL=1
echo "$OUT"
[ "$RC" -ne 0 ] || fail "B6 le hook existant échoue : le push a réussi — sortie : $OUT"
ref_absente "$TMP/origin_sub.git" masque || fail "B6 la branche refusée par le hook existant a été poussée"
pass "B6 échec du hook existant : push refusé, le pare-feu ne le masque pas"

# ── B7. aucun fichier temporaire ne subsiste après les pushes ────────────────
[ -z "$(ls -A "$TMPD")" ] || fail "B7 fichiers temporaires laissés par le hook pre-push : $(ls -A "$TMPD")"
pass "B7 aucun fichier temporaire laissé par le hook pre-push"

# ══ C. Refus protecteurs : ni casser, ni se tromper de cible ═════════════════
# Les hooks sont partagés par tous les worktrees d'un dépôt et le bloc contient
# un chemin absolu : là où l'installateur ne peut pas faire proprement, il
# refuse — avant d'écrire quoi que ce soit — au lieu de laisser un filet mort.
hooks_crees() {  # hooks_crees <dépôt> : les hooks pre-commit / pre-push présents
    local h hk
    h="$(hooks_de "$1")"
    for hk in pre-commit pre-push; do
        if [ -e "$h/$hk" ]; then echo "$hk"; fi
    done
    return 0
}

# ── C1. lancé depuis un worktree lié : refus, rien dans le checkout principal ─
W="$TMP/c1"
superprojet "$W"
WT="$TMP/c1-wt"
git -C "$W" worktree add -q -b br "$WT" 2>/dev/null
outils "$WT"
run_installateur "$WT"
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C1 worktree lié : l'installateur a réussi — sortie : $OUT"
echo "$OUT" | grep -q "worktree" || fail "C1 worktree lié : le refus n'explique pas pourquoi — sortie : $OUT"
[ -z "$(hooks_crees "$W")" ] || fail "C1 worktree lié : hooks écrits dans le checkout principal : $(hooks_crees "$W")"
[ ! -e "$W/.git/worktrees/br/hooks" ] || fail "C1 worktree lié : un dossier de hooks a été créé pour le worktree"
pass "C1 worktree lié : refus explicite, rien écrit"

# ── C2. hook existant écrit dans une autre langue : refus, fichier intact ────
W="$TMP/c2"
superprojet "$W"
H="$(hooks_de "$W")"
mkdir -p "$H"
printf '#!/usr/bin/env python3\nprint("legacy")\n' > "$H/pre-commit"
chmod +x "$H/pre-commit"
AVANT="$(sha256sum "$H/pre-commit")"
run_installateur "$W"
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C2 hook non shell : l'installateur a réussi — sortie : $OUT"
[ "$AVANT" = "$(sha256sum "$H/pre-commit")" ] || fail "C2 hook non shell : le fichier a été modifié"
[ ! -e "$H/pre-push" ] || fail "C2 hook non shell : un autre hook a été écrit malgré le refus"
pass "C2 hook existant non shell : refus, fichier intact, rien d'autre écrit"

# ── C3. --all avec un sous-module non initialisé : rien écrit nulle part ────
W="$TMP/c3"
git clone -q "$TMP/origin_meta.git" "$W" 2>/dev/null
identite "$W"
outils "$W"
[ -z "$(ls -A "$W/sub")" ] || fail "C3 fixture : le sous-module est initialisé"
run_installateur "$W" --all
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C3 sous-module non initialisé : l'installateur a réussi — sortie : $OUT"
echo "$OUT" | grep -q "initialisé" || fail "C3 sous-module non initialisé : le refus en donne une autre cause — sortie : $OUT"
[ -z "$(hooks_crees "$W")" ] || fail "C3 sous-module non initialisé : des hooks ont été écrits dans le méta : $(hooks_crees "$W")"
pass "C3 --all, sous-module non initialisé : refus, aucun hook écrit (tout ou rien)"

# ── C4. méta déplacé : le bloc existant pointe ailleurs, ce n'est pas « déjà présent » ─
W="$TMP/c4"
superprojet "$W"
run_installateur "$W"
[ "$RC" -eq 0 ] || fail "C4 fixture : l'installateur rend $RC — sortie : $OUT"
mv "$W" "$TMP/c4-deplace"
W="$TMP/c4-deplace"
run_installateur "$W"
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C4 méta déplacé : « déjà présent » rendu alors que les hooks pointent vers l'ancien chemin"
echo "$OUT" | grep -q "déplacé" || fail "C4 méta déplacé : le refus n'explique pas pourquoi — sortie : $OUT"
pass "C4 méta déplacé : refus explicite plutôt qu'un « déjà présent » trompeur"

# ── C5. dossier de hooks hors du dépôt (core.hooksPath) : refus ─────────────
W="$TMP/c5"
superprojet "$W"
git -C "$W" config core.hooksPath .githooks
mkdir -p "$W/.githooks"
run_installateur "$W"
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C5 core.hooksPath : l'installateur a réussi — sortie : $OUT"
[ ! -e "$W/.githooks/pre-commit" ] || fail "C5 core.hooksPath : un hook (et son chemin absolu) a été écrit dans l'arbre de travail"
for hk in pre-commit pre-push; do
    [ ! -e "$W/.git/hooks/$hk" ] || fail "C5 core.hooksPath : $hk a été écrit ailleurs"
done
pass "C5 dossier de hooks hors du dépôt : refus, rien écrit"

# ── C6. hook existant symbolique : refus, cible du lien intacte ─────────────
W="$TMP/c6"
superprojet "$W"
H="$(hooks_de "$W")"
mkdir -p "$H"
printf '#!/usr/bin/env bash\necho legacy\n' > "$TMP/cible-hook.sh"
chmod +x "$TMP/cible-hook.sh"
CIBLE_AVANT="$(sha256sum "$TMP/cible-hook.sh")"
ln -s "$TMP/cible-hook.sh" "$H/pre-commit"
run_installateur "$W"
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C6 hook symbolique : l'installateur a réussi — sortie : $OUT"
[ -L "$H/pre-commit" ] || fail "C6 hook symbolique : le lien a été remplacé"
[ "$CIBLE_AVANT" = "$(sha256sum "$TMP/cible-hook.sh")" ] || fail "C6 hook symbolique : la cible du lien a été modifiée"
pass "C6 hook existant symbolique : refus, lien et cible intacts"

# ── C7. lancé avec GIT_DIR exporté (contexte d'un hook git) : les bons dépôts ─
W="$TMP/c7"
superprojet "$W"
set +e
OUT="$(cd "$W" && GIT_DIR="$W/.git" bash "$W/scripts/hooks/install-hooks.sh" --all 2>&1)"; RC=$?
set -e
echo "$OUT"
[ "$RC" -eq 0 ] || fail "C7 GIT_DIR exporté : l'installateur rend $RC — sortie : $OUT"
for d in "$W" "$W/sub"; do
    [ "$(grep -cF "$MARQUEUR" "$(hooks_de "$d")/pre-commit")" -eq 1 ] \
        || fail "C7 GIT_DIR exporté : pre-commit absent de $d — sortie : $OUT"
done
pass "C7 GIT_DIR exporté : chaque dépôt reçoit ses propres hooks"

# ── C8. chemin du méta avec espace, apostrophe et dollar ────────────────────
W="$TMP/avec espace ' et \$"
superprojet "$W"
run_installateur "$W"
[ "$RC" -eq 0 ] || fail "C8 chemin particulier : l'installateur rend $RC — sortie : $OUT"
git_commit "$W"
echo "$OUT"
[ "$RC" -eq 0 ] || fail "C8 chemin particulier : le commit rend $RC — sortie : $OUT"
for attendu in GL AUTH; do
    [ "$(echo "$OUT" | grep -c "^$attendu\$")" -eq 1 ] || fail "C8 chemin particulier : « $attendu » attendu une fois — sortie : $OUT"
done
set +e
# Branche distante inédite : un push qui ne peut pas avancer rapidement est
# rejeté par git, qui ne fournit alors aucune référence au hook.
OUT="$(TMPDIR="$TMPD" git -C "$W" push -q origin main:refs/heads/chemin-particulier 2>&1)"; RC=$?
set -e
echo "$OUT"
[ "$RC" -eq 0 ] || fail "C8 chemin particulier : le push rend $RC — sortie : $OUT"
[ "$(ref_lue main chemin-particulier)" -eq 1 ] || fail "C8 chemin particulier : la garde pre-push n'a pas reçu la référence — sortie : $OUT"
pass "C8 chemin du méta avec espace, apostrophe et dollar : hooks opérationnels"

# ── C9. hook existant = copie d'une ancienne version d'un script du pare-feu ─
# État du checkout principal du méta : l'ancien installateur recopiait
# scripts/hooks/pre-commit-gitleaks.sh dans .git/hooks/pre-commit. Chaînée
# derrière le bloc neuf, cette copie obsolète (appel de gitleaks invalide)
# resterait active. L'installateur ne l'écrase pas : il refuse et la nomme.
W="$TMP/c9"
superprojet "$W"
H="$(hooks_de "$W")"
mkdir -p "$H"
git -C "$W" add scripts/hooks/pre-commit-gitleaks.sh
git -C "$W" commit -qm "pare-feu"
cp "$W/scripts/hooks/pre-commit-gitleaks.sh" "$H/pre-commit"
chmod +x "$H/pre-commit"
COPIE_AVANT="$(sha256sum "$H/pre-commit")"
run_installateur "$W"
echo "$OUT"
[ "$RC" -ne 0 ] || fail "C9 copie d'un ancien script : l'installateur a réussi, la copie obsolète reste active — sortie : $OUT"
echo "$OUT" | grep -q "pre-commit-gitleaks.sh" || fail "C9 le refus ne nomme pas le script dont c'est une copie — sortie : $OUT"
[ "$COPIE_AVANT" = "$(sha256sum "$H/pre-commit")" ] || fail "C9 la copie a été modifiée"
[ ! -e "$H/pre-push" ] || fail "C9 un autre hook a été écrit malgré le refus"
rm "$H/pre-commit"
run_installateur "$W"
[ "$RC" -eq 0 ] || fail "C9 copie retirée : l'installateur rend $RC — sortie : $OUT"
git_commit "$W"
[ "$RC" -eq 0 ] || fail "C9 copie retirée : le commit rend $RC — sortie : $OUT"
for attendu in GL AUTH; do
    [ "$(echo "$OUT" | grep -c "^$attendu\$")" -eq 1 ] || fail "C9 « $attendu » attendu une fois — sortie : $OUT"
done
pass "C9 copie d'une ancienne version d'un script du pare-feu : refus qui nomme le script ; recréé une fois retirée"

echo ""
echo "🎉 Tous les tests passent."
