---
name: release-on-main
description: 'Avant tout push ou merge vers la branche main d''un dépôt du parc POULIDOR, préparer la release : déduire et appliquer un bump de version (patch/minor/major), mettre à jour le CHANGELOG technique, et rédiger sur demande un patchnote utilisateur. Utiliser pour : push main, release, bump de version, changelog, patchnote, notes de version.'
argument-hint: 'Dépôt et action, ex: prépare la release avant push main de HUB_base'
---

# Release on main

À invoquer **avant tout `git push` (ou merge) vers la branche `main`** d'un dépôt du parc. Deux actions :

1. **Toujours** : bump de version + entrée CHANGELOG technique.
2. **Patchnote utilisateur** : demander à chaque release si l'app est publiée et s'il faut le rédiger (cf. §4).

## 1. Préconditions

- Déterminer le dépôt courant et la branche qui va être poussée.
- Si la branche **n'est pas** `main` → ce skill ne s'applique pas, sortir sans rien faire.
- Confirmer que le dépôt est dans le périmètre (a une source de version, ou est le méta-repo POULIDOR, ou est un nouveau dépôt à bootstrapper).

## 2. Déduire le niveau de bump

- Inspecter les changements depuis la dernière version : `git log --oneline <ref>..HEAD` et le diff.
- Règles : correctifs uniquement → `patch` ; nouvelle fonctionnalité → `minor` ; rupture de compatibilité → `major`.
- **Annoncer** explicitement le niveau choisi et la version résultante avant d'agir. L'utilisateur peut corriger.

## 3. Bump + CHANGELOG technique — TOUJOURS, sans demander

Détecter la source de version dans cet ordre :

1. **`sync_version.py` présent** (ex. HUB_base) :
   - `python sync_version.py bump <level>`
   - Le script crée une entrée CHANGELOG placeholder « À compléter » → **la compléter** avec le vrai contenu technique (sections `### ⚡ …`). Une entrée placeholder non complétée = release incomplète.
   - ⚠️ **Vérifier les dérivés synchronisés par le script** et les inclure au commit de release : `VERSION`, `INTEGRATION.md`, `frontend/public/index.html` (badge navbar + cache-busting `?v=`). Incident réel (`ff7ec5a`) : dérivés oubliés du commit → bump incomplet.
2. **Sinon, `scripts/bump_version.py` présent** ou cibles `bump-patch/bump-minor/bump-major` dans le Makefile (**template + apps instanciées**) :
   - `make bump-<level>` (ou `python3 scripts/bump_version.py <level>`).
   - ⚠️ Le script **ne crée pas** l'entrée CHANGELOG : il la **valide** (avertit si absente) et affiche un template. C'est à toi de **prépendre l'entrée CHANGELOG** au format de la section « Format » (avant ou juste après le bump, mais **avant le commit**).
   - Vérifier la cohérence : `python3 scripts/bump_version.py --check` doit passer (exit 0).
   - Fichiers synchronisés par le script (à inclure au commit) : `VERSION`, `frontend/package.json`, `backend/main.py` (ou via `APP_VERSION`), `.env.example` + `.env` (`APP_VERSION` — le `.env` est gitigné), `docs/API.md` (badge).
   - ⚠️ `README.md` (badge de version) **n'est pas** synchronisé par le script — le corriger manuellement si présent (dérive réelle constatée).
   - ⚠️ Pré-commit hook : si `scripts/install-hooks.sh` a été installé, le hook re-synchronise et re-stage automatiquement les fichiers dérivés à chaque commit.
3. **Sinon, `pyproject.toml` avec `version`** (ex. hub-mcp) :
   - Éditer manuellement le champ `version` du `pyproject.toml` (pas d'outil de bump automatique).
   - Prépendre l'entrée CHANGELOG comme ci-dessus.
   - ⚠️ **Ne pas tomber dans le cas « bootstrap »** : créer un faux `VERSION` = 0.1.0 ici serait une erreur (la vraie source est le `pyproject.toml`).
4. **Sinon, fichier `VERSION` présent** (fallback manuel — méta-repo POULIDOR, hubctl_src, HUBsocle) :
   - Lire `VERSION` (`MAJOR.MINOR.PATCH`).
   - Incrémenter : `patch`→PATCH+1 ; `minor`→MINOR+1, PATCH=0 ; `major`→MAJOR+1, MINOR=0, PATCH=0.
   - Écrire la nouvelle valeur dans `VERSION` (avec saut de ligne final).
   - **Prépendre** une nouvelle entrée en tête du `CHANGELOG.md` (après le header `---`), au format de la section « Format ».
   - Synchroniser tout fichier dérivé présent ; absent → ignorer.
   - **Méta-repo POULIDOR uniquement** — resynchroniser aussi la version **affichée** :
     `bash scripts/sync-parc-version.sh <nouvelle_version>` (badge README, `guide.js`,
     footers `data-parc-version` des pages `docs/guide-hub/`) — vérification :
     `bash scripts/sync-parc-version.sh --check` (exit 1 = drift). **Inclure ces fichiers
     au commit de release** (sinon la version affichée dérive — cf. garde-fous).
5. **Sinon, `package.json` avec `"version"`** (ex. HUBCSS) :
   - `npm version <level> --no-git-tag-version` (met à jour `package.json` + `package-lock.json`).
   - Prépendre l'entrée CHANGELOG comme ci-dessus.
   - ⚠️ Vérifier `manifest.json` (champ `version`) : dérivé **non** synchronisé par `npm version` — à mettre à jour manuellement si utilisé.
6. **Sinon (aucune source de version)** — dernier recours :
   - Créer `VERSION` = `0.1.0` et un `CHANGELOG.md` initial, puis traiter comme cas 4.

## 4. Patchnote utilisateur — DEMANDER d'abord

Poser **une seule** question : « Cette app est-elle publiée ? Dois-je rédiger le patchnote utilisateur pour cette version ? » (oui/non).

- **Oui** → dans la **même entrée** CHANGELOG, ajouter en tête une section :
  ```
  ### 📣 Pour les utilisateurs
  - **Ajouté** : …
  - **Amélioré** : …
  - **Corrigé** : …
  ```
  Langage simple, sans jargon technique.
- **Non** → ne rien ajouter (l'entrée technique de l'étape 3 suffit).

Pas de mémorisation : la question est reposée à chaque push.

## 5. Finalisation

- Committer les fichiers modifiés (`VERSION`/`package.json`/`package-lock.json`/`pyproject.toml` + `CHANGELOG.md` + dérivés) :
  `git commit -m "chore(release): bump vX.Y.Z + changelog"`.
  Tolérances réelles : le préfixe `v` est parfois omis (`bump 3.60.1 + changelog`), et un suffixe descriptif est accepté (`bump v0.62.0 — HTTPS par défaut flotte`). Ne pas mélanger les deux styles dans un même dépôt — suivre l'historique local (`git log --oneline --grep="chore(release)"`).
- Poursuivre le `git push` vers `main`.
- **Sous-modules** : seuls les 6 composants sont des sous-modules du méta-repo (`HUB_base`, `HUBCSS`, `hub-mcp`, `HUBapp_TEMPLATE_base`, `hubctl_src`, `HUBsocle`). Les apps ne le sont **pas** (`APPS/*` est gitigné) → pour une app, rien à mettre à jour côté POULIDOR.
- Si le dépôt poussé est l'un de ces sous-modules : le pointeur dans POULIDOR a changé → **c'est une release du méta-repo à part entière** : refaire tourner ce skill sur POULIDOR (bump + entrée CHANGELOG documentant le ou les pointeurs, ex. `bump 0.61.1 — pointeurs template 2.25.0 + HUB_base 3.60.1`), puis pousser POULIDOR. Le bump méta peut regrouper plusieurs pointeurs poussés dans la foulée.

## Format de l'entrée CHANGELOG

```
## [X.Y.Z] - 27 juin 2026

### 📣 Pour les utilisateurs        (uniquement si patchnote demandé)
- **Ajouté** : …
- **Amélioré** : …
- **Corrigé** : …

### ⚡ Titre technique               (toujours)
- puce technique…
```

Date au format français. La section « Pour les utilisateurs » se place en tête de l'entrée.

## Garde-fous

- **Re-vérifier `git status` juste avant tout bump/commit de release** : l'activité d'autres sessions (ou d'agents en worktree) peut apparaître en cours de route (incident HUB_base du 17/09/2026 : bump empilé sur une release non commitée d'une autre session). Si le dépôt est sale ou la branche a avancé sur origin → faire le point avant de bump.
- Ne jamais pousser sur `main` sans version incrémentée ni entrée CHANGELOG.
- Une entrée CHANGELOG manquante ou placeholder non complétée = release incomplète.
- Les fichiers dérivés listés par le cas de détection doivent figurer dans le commit de release (sinon bump incomplet — ex. `ff7ec5a`).
- **Version affichée du méta-repo** : le badge README, `guide.js` et les footers `data-parc-version` de `docs/guide-hub/` dérivent vite s'ils sont corrigés à la main (0.66.9 affiché pour un parc en 0.80.x — 14 versions de retard, constaté le 2026-11-04). Passer par `scripts/sync-parc-version.sh` au moment du bump, jamais d'édition manuelle de ces fichiers pendant une release.
- Ne pas committer de secrets, backups, ou artefacts d'environnement.
- Ne pas utiliser de commandes template absentes du dépôt courant (ex. `make sync-env` si non défini).
