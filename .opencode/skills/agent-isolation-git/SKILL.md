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
