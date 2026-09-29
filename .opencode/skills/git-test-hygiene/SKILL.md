---
name: git-test-hygiene
description: 'Hygiène git des cycles de test Jellycode : tester sur un état propre (git status réflexe, git stash -u, cycle rouge/vert sans pollution WIP), staging discipliné (git add ciblés, add -p, commits atomiques par intention), boucle de test graduée (unitaires ciblés → scope élargi → verify-feature en fin de cycle uniquement, stash pour comparer deux variantes, bisect pour les régressions historiques). Utiliser AVANT de lancer des tests en cours de développement, AVANT tout commit, et pour comparer deux variantes de code.'
---

# git-test-hygiene

## Overview

Les cycles de test de Jellycode échouent ou trompent pour trois raisons git récurrentes :
l'arbre de travail est pollué par du WIP non lié, les commits empilent des intentions
mélangées, et les tests sont relancés en intégralité au lieu d'être gradués. Ce skill fixe
la discipline git du cycle de test : **état propre → staging discipliné → boucle graduée**.

**Périmètre** : s'applique **dans le worktree d'isolation** (étape 3 de
`agent-isolation-git`). Il ne remplace ni l'isolation (obligatoire avant toute modif), ni
`release-on-main` (gate push main), ni `verify-feature` (cycle Docker/make des apps) —
il les alimente.

## When to Use

- « Je vais lancer des tests » → **état propre d'abord** (section 1)
- « Je commite » → **staging discipliné** (section 2)
- « Je relance les tests » → **boucle graduée** (section 3)
- « Je compare deux approches » → stash de comparaison (section 3)
- « Depuis quand ce bug est-il là ? » → bisect (section 3)

**Ne PAS utiliser** : isoler son travail → `agent-isolation-git` · push `main` →
`release-on-main` · cycle Docker/make d'une app → `verify-feature` (skill app).

## 1. État propre avant de tester (anti-pollution WIP)

Réflexe de base : ne **jamais** interpréter un résultat de test sans savoir ce que contient
l'arbre. Toute session de test commence par `git status`.

```bash
git status --short          # réflexe AVANT toute commande de test
```

- Arbre propre → tester normalement.
- Arbre sale :
  - Si le WIP **est** le sujet du test → committer d'abord (section 2), puis tester.
  - Si le WIP **n'est pas** lié au test → `git stash -u` (`-u` inclut les non-trackés),
    tester, puis `git stash pop`.

### Cycle rouge/vert sans pollution (TDD)

Le test « rouge » n'a de valeur que s'il prouve que le bug existe **sans** le fix :

```bash
git stash -u                       # 1. écarter le fix (rouge)
<test ciblé du module touché>      # 2. doit ÉCHOUER → rouge prouvé
git stash pop                      # 3. remettre le fix
<test ciblé du module touché>      # 4. doit PASSER → vert
```

Variantes utiles : `git stash push -u -m "fix filtres WIP"` (stash **nommé**, obligatoire
dès qu'il peut y en avoir plusieurs), `git stash list`, `git stash show -p stash@{0}`
(visualiser avant de pop).

### Le stash n'est pas une poubelle

Un stash non repris est une dette invisible. Règle : à la fin de chaque tâche, tout stash
est **repris, committé ou supprimé consciemment** (`git stash drop`). `git stash list`
vide = état de sortie attendu.

## 2. Staging discipliné (add/commit)

Un commit = **une intention**. Le staging est le moment où on la choisit.

```bash
git diff                       # ce qui a changé (avant tout add)
git add <fichiers>             # ciblé par intention — JAMAIS `git add -A` en aveugle
git diff --staged              # relecture de ce qui part
git commit -m "fix(app): ..."  # message conventionné, aligné sur la branche fix/ feat/
```

- **Fichiers ciblés** : `git add backend/routers/filtres.py backend/tests/test_filtres.py`
  — jamais un add global « pour aller vite ».
- **Partiel** : `git add -p <fichier>` quand un fichier contient deux intentions (ex. un
  fix + un renommage incidentel) → ne stage que les hunks de l'intention en cours.
- **Atomique** : fix, feat, test et chore partent dans des commits séparés. Un commit mixte
  se défait **avant** push (`git reset --soft HEAD~1` puis re-staging) — pas après.
- **Contrôle de sortie** : `git status` propre (rien d'oublié, rien d'inattendu) +
  `git log --oneline -5` cohérent avant de passer à la finalisation.

## 3. Boucle de test optimisée

Ordre croissant de coût — on ne monte d'un cran que quand le cran précédent est vert :

1. **Unitaire ciblé** sur le module/fichier touché (secondes) → la majorité du loop.
2. **Scope élargi** : dossier/suite complète du domaine modifié (minute(s)).
3. **`verify-feature`** (cycle Docker/make de l'app) → **une seule fois en fin de cycle**,
   avant finalisation. Jamais en boucle de dev.

> Les tests complets en début de loop sont la forme la plus courante de temps perdu : ils
> n'apportent rien tant que le test ciblé est rouge.

### Comparer deux variantes sans commits jetables

```bash
git stash -u -m "variante A"      # écarter A après l'avoir testée
# ...écrire la variante B, tester...
# décision → variante B : git stash drop   |  retour → A : git stash pop
```

### Bisect : régressions historiques uniquement

`git bisect start <mauvais> <bon>` localise une régression **déjà commitée** dans
l'historique. Ce n'est pas un outil de débogage courant — si le bug est reproductible sur
l'état courant, déboguer normalement.

## Pièges & Red Flags

| Erreur | Conséquence | Correction |
|---|---|---|
| Tester sur un arbre sale sans le savoir | Faux vert / faux rouge, temps perdu à déboguer le test | `git status --short` réflexe avant tout test |
| `git stash pop` sans regarder | Conflits surprise, WIP mélangé | `git stash list` + `git stash show -p` avant pop |
| Plusieurs stashes anonymes | On ne sait plus lequel est lequel | `git stash push -u -m "..."` systématique |
| Stash laissé « pour plus tard » | Travail perdu ou oublié | À fin de tâche : reprendre, committer ou drop consciemment |
| `git add -A` en aveugle | Débris (logs, debug, .env locaux) commités | `git add <fichiers>` ciblés, `git diff` avant |
| Commit mixte fix+refactor+test | Revert impossible, bisect aveugle | Commits atomiques ; défaire avec `reset --soft` avant push |
| `verify-feature` en boucle de dev | Minutes perdues à chaque itération | Unitaires ciblés d'abord, verify-feature en fin de cycle |
| Bisect pour un bug courant | Perte de temps massive | Bisect = régressions historiques uniquement |

**Red_flags (STOP)** : « l'arbre est sale mais ça doit passer quand même » · « add -A, on
triera au push » · « je pop et je verrai bien » · « relançons toute la suite pour être sûr ».
→ Revenir à la section concernée, ordre strict.

## Skills liés

| Skill | Rôle |
|---|---|
| `agent-isolation-git` | En amont : ce skill s'applique DANS le worktree (étape 3). |
| `release-on-main` | En aval : gate push main (bump + changelog), inchangé. |
| `verify-feature` (skill app) | Dernier cran de la boucle de test (section 3). |
| `test-driven-development` (superpowers) | Le cycle rouge/vert du stash alimente TDD, il ne le remplace pas. |
