---
name: agent-isolation-git
description: 'Isoler le travail git d''un agent via un worktree dédié dans .worktrees/_agents/<branche>/ et un registre partagé, pour que plusieurs agents jellycode travaillent en parallèle sans collision de commits ou de branches. Utiliser avant toute modification de code substantielle (pas pour une simple question), quand plusieurs agents sont susceptibles de travailler sur le même dépôt, ou pour créer/rejoindre/nettoyer un worktree agent.'
argument-hint: 'Action et branche, ex: isoler feat/filtres-recherche | finaliser | nettoyer feat-filtres-recherche'
---

# agent-isolation-git

## Overview

Plusieurs agents jellycode peuvent travailler en parallèle sur le même dépôt POULIDOR.
Sans isolation, leurs commits, branches et checkouts se marchent dessus. Ce skill
garantit que chaque agent a son propre worktree git étanche, via un registre partagé
qui évite les collisions de branches et sérialise les merges vers `main`.

**Modèle** : un agent = un worktree = une branche. Le worktree est périssable :
créé pour la tâche, supprimé après merge.

**Règle d'or** : si la demande de l'utilisateur est une **question** (pas de
modification de code), répondre normalement sans créer de worktree. L'isolation
n'est nécessaire que lorsqu'un agent va modifier des fichiers et committer.

## When to Use

- "Je vais modifier du code" et d'autres agents pourraient être actifs → **isoler**
- "Crée-moi un worktree pour travailler sur X" → **isoler**
- "Finalise / merge ma branche" → **finaliser** (étape 4 du cycle)
- "Nettoie le worktree de X" → **nettoyer** (étape 5)

**Ne PAS utiliser pour :**
- Une question simple sans modif de code → répondre directement
- Isoler Docker/DB d'une app → `app-workshop-mover` (workshop)
- Gérer les secrets/`.env` → `vault-manager`
- Pousser sur `main` → `release-on-main` (invoqué *par* ce skill à l'étape finalisation)

## Périmètre

### ✅ Géré
- Création/suppression de worktrees agents dans `.worktrees/_agents/`
- Registre partagé (`registry.json`) avec lock atomique
- Cycle de vie complet (enregistrement → création → travail → merge → nettoyage)
- Sérialisation des merges vers `main` (via le lock)
- Détection de lock stale (>60s)

### ❌ Non géré (v1)
- Docker, DB, volumes → `app-workshop-mover`
- `.env`, secrets → `vault-manager`
- Dispatch de subagents → mécanisme natif opencode `task`
- Submodules → gérés manuellement par l'agent
- Nettoyage automatique des worktrees zombies

## Conventions de nommage

| Ressource | Convention | Exemple |
|---|---|---|
| Branche agent | `feat/<description>` ou `fix/<description>` | `feat/filtres-recherche` |
| Dossier worktree | `.worktrees/_agents/<branch-slug>/` | `.worktrees/_agents/feat-filtres-recherche/` |
| Branch-slug | Nom de branche avec `/` → `-` | `feat/filtres-recherche` → `feat-filtres-recherche` |
| Agent ID | `jellycode-<uuid4:8>` | `jellycode-a3f2b1c0` |
| Registre | `.worktrees/_agents/registry.json` | — |
| Lock | `.worktrees/_agents/.lock` | — |

> **Worktree principal** : le répertoire racine du dépôt (le checkout `main`
> par défaut, là où l'agent a été invoqué). C'est depuis ce répertoire qu'on
> exécute les commandes `git worktree` et les merges.

## Le registre

**Fichier** : `.worktrees/_agents/registry.json` (au niveau racine du dépôt).

**Exclu de git** : `.worktrees/` est déjà dans le `.gitignore` du projet. Le
registre et le lock héritent de cette exclusion. Aucune modification du
`.gitignore` n'est nécessaire.

**Format** :

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

| Champ | Type | Description |
|---|---|---|
| `branch` | string | Nom de la branche (unique parmi les `active`) |
| `path` | string | Chemin relatif du worktree depuis la racine |
| `agent_id` | string | `jellycode-<uuid4:8>` |
| `status` | string | `active` → `merged` (transitoire, retiré au cleanup) → `abandoned` (laissé pour audit) |
| `created_at` | string | ISO 8601 UTC |
| `task` | string | Optionnel, description humaine |

## Lock (accès concurrent au registre)

Le registre est partagé entre tous les agents sur le même filesystem. Pour éviter
les race conditions à l'écriture, on utilise un lock par répertoire (`mkdir`
atomique sur tous les OS POSIX).

### Acquisition

```bash
mkdir .worktrees/_agents/.lock  # atomique : échoue si déjà pris
```

Si l'acquisition échoue (répertoire existe déjà) : retry avec `sleep 1`, max 10
tentatives. Au-delà, vérifier si le lock est stale (voir ci-dessous).

### Libération

```bash
rmdir .worktrees/_agents/.lock
```

**Toujours libérer le lock**, même en cas d'erreur. Wrapper les opérations
protégées dans un try/finally équivalent.

### Lock stale (crash d'un agent)

Si un agent crash en tenant le lock, le répertoire `.lock` persiste. Le prochain
agent qui tente d'acquérir le lock vérifie l'âge du répertoire et le force
si >60 secondes :

```bash
if [ -d .worktrees/_agents/.lock ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y .worktrees/_agents/.lock) ))
    if [ $LOCK_AGE -gt 60 ]; then
        rmdir .worktrees/_agents/.lock
        echo "⚠️  Lock stale (>${LOCK_AGE}s) forcé. Vérifier le registre."
    fi
fi
```

### Helper bash réutilisable

```bash
agent_lock_acquire() {
    local attempts=0
    while ! mkdir .worktrees/_agents/.lock 2>/dev/null; do
        # Vérifier stale
        if [ -d .worktrees/_agents/.lock ]; then
            local age=$(( $(date +%s) - $(stat -c %Y .worktrees/_agents/.lock) ))
            [ $age -gt 60 ] && rmdir .worktrees/_agents/.lock 2>/dev/null && continue
        fi
        attempts=$((attempts + 1))
        [ $attempts -ge 10 ] && { echo "❌ Lock: 10 tentatives échouées"; return 1; }
        sleep 1
    done
}

agent_lock_release() {
    rmdir .worktrees/_agents/.lock 2>/dev/null
}
```

Usage : `agent_lock_acquire && { ... ; agent_lock_release; }` ou trap sur EXIT.

## Cycle de vie d'un agent

### Arbre de décision

```
La demande est-elle une QUESTION SANS modification de code ?
  → OUI → répondre normalement, pas de worktree
  → NON → suivre le cycle ci-dessous
```

### Étape 1 — Enregistrement

```bash
# 1. Générer un agent_id
AGENT_ID="jellycode-$(python3 -c 'import uuid;print(uuid.uuid4().hex[:8])')"

# 2. Acquérir le lock
agent_lock_acquire

# 3. Lire le registre (créer si absent)
if [ ! -f .worktrees/_agents/registry.json ]; then
    echo '{"agents":[]}' > .worktrees/_agents/registry.json
fi

# 4. Vérifier pas de collision sur la branche
python3 -c "
import json,sys
reg=json.load(open('.worktrees/_agents/registry.json'))
if any(a['status']=='active' and a['branch']=='$BRANCHE' for a in reg['agents']):
    print('COLLISION'); sys.exit(1)
"
# → si COLLISION : agent_lock_release && abort

# 5. Ajouter l'entrée
python3 -c "
import json,datetime
reg=json.load(open('.worktrees/_agents/registry.json'))
reg['agents'].append({
    'branch':'$BRANCHE',
    'path':'.worktrees/_agents/$BRANCH_SLUG',
    'agent_id':'$AGENT_ID',
    'status':'active',
    'created_at':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'task':'$TASK'
})
json.dump(reg,open('.worktrees/_agents/registry.json','w'),indent=2,ensure_ascii=False)
"

# 6. Libérer le lock
agent_lock_release
```

### Étape 2 — Création du worktree

```bash
# Depuis le worktree principal
git checkout main && git pull origin main

# Créer la branche si absente
git checkout -b "$BRANCHE" 2>/dev/null || git checkout "$BRANCHE"
git push -u origin "$BRANCHE"

# Revenir sur main et créer le worktree
git checkout main
git worktree add ".worktrees/_agents/$BRANCH_SLUG/" "$BRANCHE"
ls ".worktrees/_agents/$BRANCH_SLUG/"  # vérifier
```

### Étape 3 — Travail

```bash
cd ".worktrees/_agents/$BRANCH_SLUG/"
# Modifier, committer, pousser normalement
git add -A && git commit -m "feat: ..."
git push
```

### Étape 4 — Finalisation (merge vers main, SÉRIALISÉ)

**Le lock est tenu pendant TOUTE la durée du merge + release-on-main + push.**

```bash
cd "$(git rev-parse --show-toplevel)"  # revenir au worktree principal

agent_lock_acquire

git fetch origin
git checkout main
git pull origin main
git merge "origin/$BRANCHE" --no-ff
# → Conflit ? Résoudre, git add, git commit.
#   Si impossible : git merge --abort && agent_lock_release && abort

# Invoquer release-on-main (bump version + changelog) — voir skill dédié
git push origin main

# Optionnel : supprimer la branche distante
git push origin --delete "$BRANCHE" 2>/dev/null

# Marquer merged dans le registre
python3 -c "
import json
reg=json.load(open('.worktrees/_agents/registry.json'))
for a in reg['agents']:
    if a['branch']=='$BRANCHE': a['status']='merged'
json.dump(reg,open('.worktrees/_agents/registry.json','w'),indent=2,ensure_ascii=False)
"

agent_lock_release
```

### Étape 5 — Nettoyage

```bash
# 1. Supprimer le worktree
git worktree remove ".worktrees/_agents/$BRANCH_SLUG/" 2>/dev/null
rm -rf ".worktrees/_agents/$BRANCH_SLUG/"  # sécurité

# 2. Retirer l'entrée du registre
agent_lock_acquire
python3 -c "
import json
reg=json.load(open('.worktrees/_agents/registry.json'))
reg['agents']=[a for a in reg['agents'] if a['branch']!='$BRANCHE']
json.dump(reg,open('.worktrees/_agents/registry.json','w'),indent=2,ensure_ascii=False)
"
agent_lock_release
```
