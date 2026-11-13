#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# =============================================================================
# fork-remotes.sh — fait tirer à un fork de déploiement SES propres mises à jour.
#
# Le tooling du parc (`hubctl update`, `update-submodules.sh`, `hubctl doctor`)
# tire tout du remote `origin` du méta et des sous-modules. Sur un fork de
# déploiement, il faut donc :
#   - origin   = le fork du client (c'est LUI qui porte les updates du fork) ;
#   - upstream = l'org officielle POULIDOR (rapatriement volontaire contrôlé) ;
#   - sous-modules : basculés pareillement, avec surcharge LOCALE dans
#     `.git/config` (`submodule.<nom>.url`) — le `.gitmodules` versionné reste
#     identique à l'officiel, donc zéro conflit au rapatriement amont.
#
# Usage :
#   scripts/fork-remotes.sh --fork-url git@github.com:<org>/POULIDOR.git [options]
#
# Options :
#   --sub <nom>=<url>   fork explicite d'un sous-module dont le repo forké porte
#                       un autre nom (ex. HUB_base=git@github.com:<org>/HUB.git).
#                       Répétable. Sans mapping, l'org du fork remplace
#                       POULIDOR-Audit-Developpement dans l'URL officielle.
#   --check             rapport seul : aucune modification
#   --dry-run           affiche les changements sans les appliquer
#   --pull-upstream     rapatrie l'amont officiel : sous-modules d'abord, puis
#                       méta (fetch + fast-forward + push vers le fork)
#   --skip-submodules   ne traite que le méta-repo
#   --yes               sans confirmation
#
# Prérequis :
#   - à exécuter depuis la branche `main` du méta-repo, arbre propre ;
#   - réseau vers les remotes (existence des forks testée par `git ls-remote`).
#
# Garde-fous :
#   - aucune donnée touchée : seules des configs git locales sont modifiées
#     (remotes et surcharges dans `.git/config`) — jamais de fichier versionné ;
#   - un fork de sous-module inexistant/inaccessible N'EST PAS basculé
#     (warning) : le sous-module continue de tirer l'officiel ;
#   - `--pull-upstream` saute tout repo avec du WIP, ne fait que du
#     fast-forward et ne pousse QUE vers origin (le fork) — jamais upstream ;
#   - ne pas lancer `git submodule sync` après ce script : il réécrirait les
#     URLs officielles par-dessus les surcharges du fork.
# =============================================================================

set -euo pipefail

OFFICIAL_ORG="POULIDOR-Audit-Developpement"
FORK_URL=""
CHECK=0; DRYRUN=0; PULL_UPSTREAM=0; SKIP_SUBMODULES=0; YES=0
declare -A SUB_MAP=()

usage_die() { sed -n '7,45p' "$0"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --fork-url)       FORK_URL="${2:-}"; shift 2 ;;
    --sub)            SUB_MAP["${2%%=*}"]="${2#*=}"; shift 2 ;;
    --check)          CHECK=1; shift ;;
    --dry-run)        DRYRUN=1; shift ;;
    --pull-upstream)  PULL_UPSTREAM=1; shift ;;
    --skip-submodules) SKIP_SUBMODULES=1; shift ;;
    --yes)            YES=1; shift ;;
    -h|--help)        usage_die ;;
    *) echo "❌ Option inconnue : $1 (voir l'en-tête du script)"; exit 1 ;;
  esac
done

[ -n "$FORK_URL" ] || { echo "❌ --fork-url est obligatoire (voir l'en-tête du script)"; exit 1; }

cd "$(git rev-parse --show-toplevel)"
[ -f .gitmodules ] || { echo "❌ Racine du méta-repo introuvable (.gitmodules absent)"; exit 1; }

BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "❌ Branche courante : '$BRANCH' — passe sur main d'abord : git checkout main"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  Arbre de travail non propre (git status) — configs modifiées quand même,"
  echo "    mais aligne ton WIP avant toute mise à jour (hubctl update)."
fi

# L'org du fork, dérivée de --fork-url (git@github.com:<org>/POULIDOR.git ou
# https://github.com/<org>/POULIDOR.git).
FORK_ORG=$(basename "$(dirname "${FORK_URL%.git}")")

# L'upstream officiel du méta = l'ancienne origin si elle pointe l'org officielle.
CUR_ORIGIN=$(git remote get-url origin)
UPSTREAM_META="$CUR_ORIGIN"

apply_or_note() {
  local label="$1"; shift
  if [ "$DRYRUN" -eq 1 ] || [ "$CHECK" -eq 1 ]; then
    echo "    [$( [ "$CHECK" -eq 1 ] && echo check || echo dry-run )] $label : $*"
  else
    "$@"
  fi
}

# Idempotent : set-url si le remote existe, add sinon (set -e ne meurt jamais ici).
set_remote() { # <repo> <nom-du-remote> <url> <label>
  local repo="$1" name="$2" url="$3" label="$4"
  if git -C "$repo" remote get-url "$name" >/dev/null 2>&1; then
    apply_or_note "$label" git -C "$repo" remote set-url "$name" "$url"
  else
    apply_or_note "$label (création)" git -C "$repo" remote add "$name" "$url"
  fi
}

# --- PULL-UPSTREAM : rapatrier l'amont officiel vers le fork ------------------
# Ordre imposé : sous-modules D'ABORD (les pointeurs du méta doivent exister
# dans les forks), méta ENSUITE. Fast-forward seul, push vers origin (fork).
ff_repo() { # <repo> <remote> [ignore-submodules]  → 0 avancé, 1 déjà à jour, 2 refusé
  local repo="$1" remote="$2" branch behind
  local -a st=(status --porcelain)
  # Pour le méta, le rapatriement des sous-modules vient de créer l'état
  # transitoire « sous-module avancé, pointeur pas encore » — légitime ici.
  [ "${3:-}" = "ignore-submodules" ] && st+=(--ignore-submodules=all)
  branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
  # Sous-module en HEAD détaché (cas systématique après `submodule update`) :
  # rattacher à main, comme `hubctl` le fait dans `_ensure_branch_attached`.
  if [ "$branch" = "HEAD" ]; then
    if git -C "$repo" show-ref --verify --quiet refs/heads/main; then
      git -C "$repo" checkout main -q
    else
      if git -C "$repo" checkout -B main "$remote/main" -q 2>/dev/null; then
        git -C "$repo" push origin main -q 2>/dev/null \
          || echo "    ⚠️  $repo : push origin main a échoué — à faire à la main"
        echo "    ✅ $repo : main créée depuis $remote/main et poussée vers origin"
        return 0
      fi
      echo "    ⚠️  $repo : ni main locale ni $remote/main — sauté"
      return 2
    fi
    branch=main
  fi
  [ "$branch" = "main" ] || { echo "    ⚠️  $repo : branche '$branch' ≠ main — sauté"; return 2; }
  [ -z "$(git -C "$repo" "${st[@]}")" ] || { echo "    ⚠️  $repo : WIP local — sauté"; return 2; }
  git -C "$repo" remote get-url "$remote" >/dev/null 2>&1 \
    || { echo "    ⚠️  $repo : pas de remote '$remote' — sauté"; return 2; }
  git -C "$repo" fetch "$remote" --prune -q 2>/dev/null \
    || { echo "    ⚠️  $repo : fetch $remote impossible — sauté"; return 2; }
  git -C "$repo" rev-parse --verify -q "$remote/main" >/dev/null \
    || { echo "    ⚠️  $repo : pas de branche $remote/main — sauté"; return 2; }
  behind=$(git -C "$repo" rev-list --count "main..$remote/main")
  [ "$behind" -gt 0 ] || return 1
  if git -C "$repo" merge --ff-only "$remote/main" -q; then
    echo "    ✅ $repo : avancé de $behind commit(s) depuis $remote/main"
  else
    echo "    ⚠️  $repo : fast-forward impossible (divergence) — traiter à la main"
    return 2
  fi
  git -C "$repo" push origin main -q 2>/dev/null \
    || echo "    ⚠️  $repo : push origin a échoué (fork divergent ?) — à traiter à la main"
  return 0
}

if [ "$PULL_UPSTREAM" -eq 1 ]; then
  if [ "$YES" -ne 1 ]; then
    echo "── Rapatriement de l'amont officiel ($OFFICIAL_ORG) vers le fork ──"
    read -rp "Fast-forward + push vers le fork ($FORK_URL). Confirmer ? [o/N] " r
    [[ "$r" =~ ^[oO]$ ]] || { echo "annulé"; exit 1; }
  fi
  echo "── Sous-modules ────────────────────────────────────────────"
  while IFS=$'\t' read -r name path; do
    [ -e "$path/.git" ] || continue   # non initialisé (dossier vidé par deinit inclus)
    origin=$(git -C "$path" remote get-url origin)
    case "$origin" in
      *"$OFFICIAL_ORG"*) echo "    ↷ $name : origin officielle — rien à rapatrier" ;;
      *)  official=$(git config --file .gitmodules "submodule.${name}.url")
          git -C "$path" remote get-url upstream >/dev/null 2>&1 \
            || git -C "$path" remote add upstream "$official"
          ff_repo "$path" upstream || true ;;
    esac
  done < <(git config --file .gitmodules --get-regexp '^submodule\.[^.]+\.path$' \
             | while read -r key path; do
                 name=${key#submodule.}; echo -e "${name%.path}\t$path"
               done)
  echo "── Méta-repo ───────────────────────────────────────────────"
  ff_repo . upstream ignore-submodules || true
  echo ""
  echo "✅ Rapatriement terminé. Applique maintenant : ./hubctl update hub"
  exit 0
fi

# --- RAPPORT / BASCULE des remotes --------------------------------------------
echo "── État AVANT ──────────────────────────────────────────────"
echo "  fork          : $FORK_URL (org « $FORK_ORG »)"
echo "  méta origin   : $CUR_ORIGIN"
git remote get-url upstream >/dev/null 2>&1 && echo "  méta upstream : $(git remote get-url upstream)" || true

echo "── Méta-repo ───────────────────────────────────────────────"
if [ "$CUR_ORIGIN" = "$FORK_URL" ]; then
  echo "  ✅ origin pointe déjà le fork"
  git remote get-url upstream >/dev/null 2>&1 \
    && echo "  ✅ upstream déjà présent ($(git remote get-url upstream))" \
    || echo "  ⚠️  pas de remote upstream (rapatriement amont impossible)"
else
  set_remote . origin "$FORK_URL" "méta origin → fork"
  set_remote . upstream "$UPSTREAM_META" "méta upstream → amont officiel ($UPSTREAM_META)"
  if [ "$CHECK" -eq 0 ] && [ "$DRYRUN" -eq 0 ]; then
    echo "  ✅ origin → $FORK_URL · upstream → $UPSTREAM_META"
  fi
fi

if [ "$SKIP_SUBMODULES" -eq 0 ]; then
  echo "── Sous-modules ────────────────────────────────────────────"
  while IFS=$'\t' read -r name path; do
    official=$(git config --file ".gitmodules" "submodule.${name}.url")
    if [ -n "${SUB_MAP[$name]:-}" ]; then
      fork_url="${SUB_MAP[$name]}"
    else
      fork_url="${official//$OFFICIAL_ORG/$FORK_ORG}"
      [ "$fork_url" != "$official" ] || { echo "  ⚠️  $name : URL non dérivable ($official) — passe par --sub $name=<url>"; continue; }
    fi
    # Test « initialisé » : path/.git doit exister (fichier gitdir absorbé OU
    # dossier). Jamais `git -C path rev-parse` seul : sur un module désinit
    # (dossier vidé), git remonte au méta et les écritures fuieraient dedans.
    if [ ! -e "$path/.git" ]; then
      echo "  ⚠️  $name : sous-module non initialisé — surcharge locale posée quand même"
      apply_or_note "$name : surcharge submodule.$name.url" git config "submodule.${name}.url" "$fork_url"
      continue
    fi
    if ! timeout 15 git ls-remote --exit-code --heads "$fork_url" >/dev/null 2>&1; then
      echo "  ⚠️  $name : fork inaccessible ou absent ($fork_url) — origin officielle conservée"
      echo "      (fork le repo côté GitHub puis relance, ou --sub $name=<url>)"
      continue
    fi
    cur=$(git -C "$path" remote get-url origin)
    if [ "$cur" = "$fork_url" ]; then
      echo "  ✅ $name : origin déjà sur le fork"
    else
      set_remote "$path" origin "$fork_url" "$name origin → fork"
      set_remote "$path" upstream "$official" "$name upstream → officiel"
      apply_or_note "$name : surcharge submodule.$name.url" git config "submodule.${name}.url" "$fork_url"
      if [ "$CHECK" -eq 0 ] && [ "$DRYRUN" -eq 0 ]; then
        echo "  ✅ $name : origin → $fork_url · upstream → $official (+ surcharge locale)"
      fi
    fi
  done < <(git config --file .gitmodules --get-regexp '^submodule\.[^.]+\.path$' \
             | while read -r key path; do
                 name=${key#submodule.}; echo -e "${name%.path}\t$path"
               done)
fi

# --- Récap + apps --------------------------------------------------------------
echo "── État APRÈS ──────────────────────────────────────────────"
echo "  méta origin   : $(git remote get-url origin)"
echo "  méta upstream : $(git remote get-url upstream 2>/dev/null || echo '—')"
if [ "$SKIP_SUBMODULES" -eq 0 ]; then
  git submodule status 2>/dev/null | sed 's/^/  /' || true
fi

echo "── Apps (APPS/*, info — chaque app est un cas par déploiement) ──"
for app in APPS/*/; do
  [ -d "$app/.git" ] || continue
  url=$(git -C "$app" remote get-url origin 2>/dev/null || echo '?')
  if [[ "$url" == *"$OFFICIAL_ORG"* ]]; then
    echo "  $app → $url   (org officielle — à vérifier)"
  else
    echo "  $app → $url"
  fi
done

if [ "$CHECK" -eq 1 ]; then
  echo ""
  echo "✅ Rapport seul (--check) — rien n'a été modifié. Relance sans --check pour appliquer."
elif [ "$DRYRUN" -eq 1 ]; then
  echo ""
  echo "✅ Simulation terminée — rien n'a été modifié. Relance sans --dry-run pour appliquer."
else
  echo ""
  echo "✅ Fork configuré : les mises à jour tirent désormais de TON origin (hubctl update inchangé)."
  echo "   Rappels :"
  echo "   - suivre l'amont officiel : scripts/fork-remotes.sh --fork-url ... --pull-upstream"
  echo "   - ne PAS lancer 'git submodule sync' (écraserait les surcharges du fork)"
  echo "   - après un re-clone (PRA, migration), relancer ce script : .git/config n'est pas versionné"
  echo "   - resynchronise le coffre (hubctl vault sync) pour récapituler les git_url des apps"
fi
