---
name: agent-isolation-git
description: 'Isoler le travail git d''un agent via un worktree dédié (.worktrees/_agents/<branche>/) + registre partagé, pour que plusieurs agents jellycode travaillent en parallèle sans collision. OBLIGATOIRE (politique parc, 17/09/2026) avant TOUTE intervention touchant du code, sans exception — même petite, même si aucun autre agent ne semble actif. Ne PAS utiliser pour une simple question (réponse directe), ni pour isoler Docker/DB (→ app-workshop-mover), ni pour les secrets (→ vault-manager).'
argument-hint: 'Action et branche, ex: isoler feat/filtres-recherche | finaliser | nettoyer feat-filtres-recherche'
---

# agent-isolation-git

## Overview

Plusieurs agents jellycode peuvent travailler en parallèle sur le même dépôt POULIDOR. Sans isolation, leurs commits/branches/checkouts se marchent dessus. Ce skill garantit que chaque agent a son propre worktree git étanche, via un registre partagé qui évite les collisions et sérialise les merges vers `main`.

**Modèle** : 1 agent = 1 worktree = 1 branche. Le worktree est **périssable** : créé pour la tâche, supprimé après merge.

> **Politique stricte (décision utilisateur du 17/09/2026)** : le worktree est **obligatoire**
> pour toute intervention qui touche du code dans le parc, **sans exception** — même petite,
> même si aucun autre agent ne semble actif. L'ancien critère « quand d'autres agents
> peuvent être actifs » est **remplacé** par « systématique ». Motivation : une session
> parallèle peut apparaître en cours de route (incident HUB_base 17/09/2026 : bump empilé
> sur une release non commitée d'une autre session). Seules les questions sans modif de
> fichiers restent hors périmètre (règle d'or ci-dessous).

> **Règle d'or** : si la demande est une **question** (pas de modif de code), répondre normalement **sans** créer de worktree. L'isolation n'a de sens que lorsqu'un agent va modifier des fichiers et committer.

## Fast-path scripté (voie normale)

Les étapes **1-2** (registre sous lock + branche + worktree) et l'étape **5** (cleanup)
sont automatisées par `scripts/parc-isolate` — même registre, même lock, mêmes
conventions. **Utilise le script d'abord** : un seul appel bash au lieu de la
procédure manuelle.

```bash
# Isoler (étapes 1-2) — branche créée depuis origin/main, push upstream inclus :
bash scripts/parc-isolate feat/ma-branche "Description de la tâche"

# Lister les agents actifs (détection visuelle de collision) :
bash scripts/parc-isolate --list

# Nettoyer (étape 5) après merge :
bash scripts/parc-isolate --cleanup feat/ma-branche

# Forcer un lock stale (>60s, agent crashé) :
bash scripts/parc-isolate --release-lock
```

Invariants du script : registre modifié **avant** création du worktree, rollback
registre+branche si `git worktree add` échoue, lock libéré via trap EXIT, collision
détectée parmi les entrées `active`. Submodules non initialisés par défaut
(`--submodules` pour les initialiser).

**Restent manuels** : l'étape **3** (travail dans le worktree) et surtout l'étape
**4** (merge vers `main` **sous lock** + `release-on-main` obligatoire + push),
car elle enchaîne release et bump — procédure ci-dessous. En cas d'échec ou
d'absence du script, appliquer la procédure manuelle complète.

## When to Use

- "Je vais modifier du code" → **isoler** (toujours — règle stricte du parc, pas de condition) — **fast-path : `bash scripts/parc-isolate <branche> "task"`**
- "Crée-moi un worktree pour X" → **isoler**
- "Finalise / merge ma branche" → **finaliser** (étape 4, manuelle, sous lock)
- "Nettoie le worktree de X" → **nettoyer** (étape 5) — fast-path : `bash scripts/parc-isolate --cleanup <branche>`

**Ne PAS utiliser** : question simple sans code → répondre direct · isolation Docker/DB → `app-workshop-mover` · secrets/`.env` → `vault-manager` · push sur `main` → `release-on-main` (invoqué *par* ce skill à l'étape 4).

## Conventions de nommage

| Ressource | Convention | Exemple |
|---|---|---|
| Branche agent | `feat/<desc>` ou `fix/<desc>` | `feat/filtres-recherche` |
| Dossier worktree | `.worktrees/_agents/<branch-slug>/` | `.worktrees/_agents/feat-filtres-recherche/` |
| Branch-slug | `/` → `-` | `feat/filtres-recherche` → `feat-filtres-recherche` |
| Agent ID | `jellycode-<uuid4:8>` | `jellycode-a3f2b1c0` |
| Registre | `.worktrees/_agents/registry.json` | — |
| Lock | `.worktrees/_agents/.lock` | — |

> `.worktrees/` est déjà dans le `.gitignore` du projet → registre et lock héritent de l'exclusion. Aucune modif du `.gitignore` nécessaire.

## Le registre

**Fichier** : `.worktrees/_agents/registry.json` (racine du dépôt).

```json
{
  "agents": [
    {
      "branch": "feat/filtres-recherche",
      "path": ".worktrees/_agents/feat-filtres-recherche",
      "agent_id": "jellycode-a3f2b1c0",
      "status": "active",
      "created_at": "2026-08-02T10:00:00Z",
      "task": "Ajouter des filtres de recherche avances"
    }
  ]
}
```

`status` : `active` → `merged` (transitoire, retiré au cleanup) → `abandoned` (laissé pour audit). Le champ `branch` est **unique parmi les `active`** (détection de collision).

## Lock (accès concurrent au registre)

Le registre est partagé entre agents sur le même filesystem. On utilise un lock par répertoire (`mkdir` atomique sur tous les OS POSIX) :

```bash
agent_lock_acquire() {
    local attempts=0
    while ! mkdir .worktrees/_agents/.lock 2>/dev/null; do
        # Vérifier stale : lock > 60s = agent crashé, on force
        if [ -d .worktrees/_agents/.lock ]; then
            local age=$(( $(date +%s) - $(stat -c %Y .worktrees/_agents/.lock) ))
            [ $age -gt 60 ] && rmdir .worktrees/_agents/.lock 2>/dev/null && continue
        fi
        attempts=$((attempts + 1))
        [ $attempts -ge 10 ] && { echo "❌ Lock: 10 tentatives échouées"; return 1; }
        sleep 1
    done
}

agent_lock_release() { rmdir .worktrees/_agents/.lock 2>/dev/null; }
```

Usage : `agent_lock_acquire && { ... ; agent_lock_release; }` ou trap sur EXIT. **Toujours libérer le lock**, même en cas d'erreur.

## Cycle de vie (5 étapes)

> Schéma : `QUESTION sans code ? → répondre direct, STOP` · `sinon → 1 → 2 → 3 → 4 → 5`

**Étape 1 — Enregistrement** (sous lock) : générer `AGENT_ID` (`jellycode-<uuid4:8>`) → `agent_lock_acquire` → lire/créer `registry.json` → vérifier pas de collision sur `branch` avec un `active` → ajouter l'entrée → `agent_lock_release`. Si collision : abort, proposer un nom alternatif.

**Étape 2 — Création du worktree** : `git checkout main && git pull` → créer la branche (`git checkout -b "$BRANCHE"`) → `git push -u origin "$BRANCHE"` → `git checkout main` → `git worktree add ".worktrees/_agents/$BRANCH_SLUG/" "$BRANCHE"`. Si `git worktree add` échoue : prendre le lock, retirer l'entrée du registre, libérer.

**Étape 3 — Travail** : `cd ".worktrees/_agents/$BRANCH_SLUG/"` → modifier, committer, pousser normalement.

**Étape 4 — Finalisation (merge vers main, SÉRIALISÉ)** : le **lock est tenu pendant TOUTE la durée** du merge + release-on-main + push.

```bash
cd "$(git rev-parse --show-toplevel)"   # revenir au worktree principal
agent_lock_acquire
git fetch origin && git checkout main && git pull origin main
git merge "origin/$BRANCHE" --no-ff
# Conflit ? Résoudre, git add, git commit. Si impossible : git merge --abort && agent_lock_release && abort.
# Invoquer release-on-main (bump version + changelog) — skill dédié obligatoire.
git push origin main
git push origin --delete "$BRANCHE" 2>/dev/null   # optionnel
# Marquer status='merged' dans le registre (sous le même lock)
agent_lock_release
```

**Étape 5 — Nettoyage** : `git worktree remove ".worktrees/_agents/$BRANCH_SLUG/"` (+ `rm -rf` en sécurité) → sous lock, retirer l'entrée du registre → libérer le lock.

## Pièges & Red Flags

| Erreur | Conséquence | Correction |
|---|---|---|
| Modifier du code dans le worktree principal sans isoler | Conflit avec d'autres agents, WIP mélangé | Toujours worktree avant modif (si d'autres agents actifs) |
| Oublier de libérer le lock | Tous les autres agents bloqués | try/finally ou `trap EXIT` systématique |
| Merger sans tenir le lock | Deux agents bumpent la même version → conflit VERSION/CHANGELOG | Le lock couvre merge + release + push |
| Merger sans `release-on-main` | Push `main` sans bump = violation AGENTS.md | `release-on-main` obligatoire, appelé dans l'étape 4 |
| Créer le worktree **avant** le registre | Pas de détection de collision | Étape 1 (registre) AVANT étape 2 (worktree) |
| Nettoyer le worktree sans retirer l'entrée registre | Entrée fantôme = fausse collision | Étape 5 systématique après étape 4 |
| Ignorer un lock stale | Bloque tous les agents | Le forcer après 60s est obligatoire (helper ci-dessus) |

**Red_flags (STOP)** : "Pas besoin de worktree, c'est petit" · "Je merge sans lock, plus rapide" · "Le registre, je l'ignore" · "Lock stale, j'attends". → Revenir à l'étape concernée, ordre strict.

## Non géré (v1)

Docker/DB/volumes → `app-workshop-mover` · `.env`/secrets → `vault-manager` · dispatch subagents → `task` natif · submodules → gérés manuellement · nettoyage auto des worktrees zombies (manuel).

## Skills liés

| Skill | Rôle |
|---|---|
| `release-on-main` | Invoqué à l'étape 4 sous lock. Non modifié par ce skill. |
| `using-git-worktrees` (superpowers) | Référence pour commandes `git worktree` avancées. |
| `app-workshop-mover` | Indépendant. Isolation git uniquement. Combiner manuellement si isolation Docker/DB nécessaire. |
