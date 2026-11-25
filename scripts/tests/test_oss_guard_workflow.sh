#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# test_oss_guard_workflow.sh — régression : le job « aucune donnée privée » du
# workflow .github/workflows/oss-guard.yml ne cite aucune valeur interdite et
# refuse ce qu'il doit refuser.
#
# Open source — filet de sécurité : un workflow public qui cite les valeurs
# qu'il interdit les publie. Les motifs viennent donc de la variable de dépôt
# OSS_FORBIDDEN_PATTERNS, jamais du fichier du workflow. Les scripts `run` des
# pas du job sont extraits du YAML et exécutés tels quels, comme le fait GitHub
# Actions (bash -eo pipefail, depuis la racine du dépôt), sur un dépôt factice.
#
# Toutes les valeurs interdites de ce test sont factices.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/oss-guard.yml"
GARDE="$ROOT/scripts/oss-guard.sh"
BASH_BIN="$(command -v bash)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/oss-test-workflow.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

[ -f "$WORKFLOW" ] || fail ".github/workflows/oss-guard.yml absent"
[ -f "$GARDE" ] || fail "scripts/oss-guard.sh absent"
command -v python3 >/dev/null || fail "python3 requis (lecture du workflow)"
python3 -c 'import yaml' 2>/dev/null || fail "module Python « yaml » absent (paquet python3-yaml)"

LITTERAL='INTERDIT-CLIENT-FICTIF-7F3A'
MOTIFS="# Motifs factices de test
$LITTERAL
interdit[-_]hote[-_]fictif[0-9]{2}"

# ── Le job, lu dans le YAML ───────────────────────────────────────────────────
# CONDITION : le `if` du job ; PAS : les scripts `run` de ses pas, dans l'ordre,
# séparés par une ligne « --- ».
JOB="$(python3 - "$WORKFLOW" <<'EOF'
import sys, yaml
job = yaml.safe_load(open(sys.argv[1]))["jobs"]["no-private-data"]
print(job.get("if") or "")
runs = [s["run"] for s in job["steps"] if "run" in s]
print(len(runs))
for r in runs:
    sys.stdout.write(r if r.endswith("\n") else r + "\n")
    print("---")
EOF
)"
CONDITION="$(printf '%s\n' "$JOB" | sed -n 1p)"
NB_PAS="$(printf '%s\n' "$JOB" | sed -n 2p)"
pas() {  # pas <numéro> : le script `run` de ce pas
    printf '%s\n' "$JOB" | awk -v n="$1" 'NR > 2 && /^---$/ { i++; next } NR > 2 && i == n - 1 { print }'
}

[ -n "$CONDITION" ] || fail "le job no-private-data n'a pas de condition « if »"
printf '%s\n' "$CONDITION" | grep -qF "github.event.pull_request.head.repo.fork == false" \
    || fail "le job doit s'exécuter aussi pour les pull_request du dépôt (fork == false) — condition : $CONDITION"
printf '%s\n' "$CONDITION" | grep -qF "github.event_name == 'push'" \
    || fail "le job doit s'exécuter aux push — condition : $CONDITION"
pass "condition du job : push, et pull_request qui ne vient pas d'un fork (une variable de dépôt n'y est pas transmise)"

[ "$NB_PAS" -eq 3 ] || fail "3 pas avec un script attendus (motifs, garde, chemins personnels) — lus : $NB_PAS"
printf '%s\n' "$(pas 1)" | grep -q 'OSS_FORBIDDEN_PATTERNS' || fail "pas 1 : il doit recevoir la variable OSS_FORBIDDEN_PATTERNS"
printf '%s\n' "$(pas 1)" | grep -q 'oss-forbidden.txt' || fail "pas 1 : il doit écrire oss-forbidden.txt"
printf '%s\n' "$(pas 2)" | grep -q 'oss-guard.sh scan-tree' || fail "pas 2 : il doit appeler scripts/oss-guard.sh scan-tree"
printf '%s\n' "$(pas 3)" | grep -q '/home/' || fail "pas 3 : il doit refuser les chemins personnels (/home/<nom>)"
pass "trois pas : motifs depuis la variable, garde des valeurs interdites, chemins personnels"

# ── Le workflow ne cite ni motif ni adresse IP ────────────────────────────────
grep -qE '[0-9]{1,3}\\?\.[0-9]{1,3}\\?\.[0-9]{1,3}\\?\.[0-9]{1,3}' "$WORKFLOW" \
    && fail "le workflow cite une adresse IP — un workflow public ne doit contenir aucune valeur réelle"
pass "le workflow ne cite aucune adresse IP"

# ── Les pas, exécutés comme GitHub Actions, sur un dépôt factice ──────────────
R="$TMP/repo"
RUNNER_TEMP="$TMP/runner-temp"
mkdir -p "$R/scripts" "$RUNNER_TEMP"
git init -q -b main "$R"
git -C "$R" config user.email test@example.org
git -C "$R" config user.name test
cp "$GARDE" "$R/scripts/oss-guard.sh"
echo propre > "$R/README.md"
commit() {  # commit <message>
    git -C "$R" add -A
    git -C "$R" commit -q -m "$1"
}
commit "init"

lancer() {  # lancer <numéro de pas> [VAR=valeur …] : le pas, depuis le dépôt ; renseigne RC et OUT
    local n="$1"; shift
    set +e
    OUT="$(cd "$R" && env -i PATH="$PATH" HOME="$TMP" RUNNER_TEMP="$RUNNER_TEMP" "$@" \
          "$BASH_BIN" --noprofile --norc -eo pipefail -c "$(pas "$n")" 2>&1)"; RC=$?
    set -e
}

echo "── pas 1 : motifs"
lancer 1 OSS_FORBIDDEN_PATTERNS=""
[ "$RC" -ne 0 ] || fail "variable OSS_FORBIDDEN_PATTERNS vide : le pas 1 devrait échouer — sortie : $OUT"
printf '%s\n' "$OUT" | grep -q 'OSS_FORBIDDEN_PATTERNS' || fail "variable vide : le message ne nomme pas la variable — sortie : $OUT"
printf '%s\n' "$OUT" | grep -q '::error' || fail "variable vide : pas de message d'erreur (::error) — sortie : $OUT"
pass "variable absente ou vide : le job échoue, en nommant la variable"

lancer 1 OSS_FORBIDDEN_PATTERNS="$MOTIFS"
[ "$RC" -eq 0 ] || fail "variable renseignée : le pas 1 échoue — sortie : $OUT"
[ -f "$RUNNER_TEMP/oss-forbidden.txt" ] || fail "le pas 1 n'écrit pas oss-forbidden.txt dans RUNNER_TEMP — sortie : $OUT"
[ "$(cat "$RUNNER_TEMP/oss-forbidden.txt")" = "$MOTIFS" ] || fail "oss-forbidden.txt ne contient pas les motifs reçus"
printf '%s\n' "$OUT" | grep -qF -- "$LITTERAL" && fail "le pas 1 affiche les motifs — sortie : $OUT"
pass "variable renseignée : les motifs sont écrits dans RUNNER_TEMP, sans être affichés"

echo "── pas 2 : garde"
lancer 2
[ "$RC" -eq 0 ] || fail "dépôt propre : le pas 2 devrait réussir — sortie : $OUT"
printf 'hote = %s\n' "$LITTERAL" > "$R/serveur.txt"
commit "fautif"
lancer 2
[ "$RC" -ne 0 ] || fail "valeur interdite dans un fichier suivi : le pas 2 devrait échouer — sortie : $OUT"
printf '%s\n' "$OUT" | grep -qF -- "$LITTERAL" && fail "le pas 2 affiche la valeur interdite — sortie : $OUT"
git -C "$R" rm -q serveur.txt
commit "nettoyage"
pass "valeur interdite (motif de la variable) : le job échoue, sans afficher la valeur"

echo "── pas 3 : chemins personnels"
lancer 3
[ "$RC" -eq 0 ] || fail "dépôt propre : le pas 3 devrait réussir — sortie : $OUT"
printf '# doc\nchemin doc : /home/utilisateur/projet et /home/user/src, ou /home/<nom>/src\n' > "$R/doc.md"
commit "chemins d'exemple"
lancer 3
[ "$RC" -eq 0 ] || fail "chemins d'exemple de la documentation : le pas 3 devrait réussir — sortie : $OUT"
# Le chemin fautif est assemblé à l'exécution : ce fichier de test ne doit lui-même
# citer aucun chemin personnel, sous peine d'être signalé par le pas qu'il vérifie.
printf 'XDG=/home/%s/.local\n' 'jean.dupont-test' > "$R/env.sh"
commit "chemin personnel"
lancer 3
[ "$RC" -ne 0 ] || fail "chemin personnel dans un fichier suivi : le pas 3 devrait échouer — sortie : $OUT"
printf '%s\n' "$OUT" | grep -qF 'env.sh' || fail "chemin personnel : le fichier en cause n'est pas nommé — sortie : $OUT"
git -C "$R" rm -q env.sh
commit "nettoyage"
pass "chemin personnel : le job échoue et nomme le fichier ; chemins d'exemple de la documentation acceptés"

echo ""
echo "🎉 Tous les tests passent."
