---
name: release-on-main
description: 'Avant tout push ou merge vers la branche main d''un dépôt du parc POULIDOR, préparer la release : déduire et appliquer un bump de version (patch/minor/major), mettre à jour le CHANGELOG technique, et rédiger sur demande un patchnote utilisateur. Utiliser pour : push main, release, bump de version, changelog, patchnote, notes de version.'
argument-hint: 'Dépôt et action, ex: prépare la release avant push main de HUB_base'
---

# Release on main

À invoquer **avant tout `git push` (ou merge) vers la branche `main`** d'un dépôt du parc. Deux actions :

1. **Toujours** : bump de version + entrée CHANGELOG technique.
2. **Sur demande** : patchnote rédigé pour les utilisateurs finaux.

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
2. **Sinon, fichier `VERSION` présent** (fallback manuel) :
   - Lire `VERSION` (`MAJOR.MINOR.PATCH`).
   - Incrémenter : `patch`→PATCH+1 ; `minor`→MINOR+1, PATCH=0 ; `major`→MAJOR+1, MINOR=0, PATCH=0.
   - Écrire la nouvelle valeur dans `VERSION` (avec saut de ligne final).
   - **Prépendre** une nouvelle entrée en tête du `CHANGELOG.md` (après le header `---`), au format de la section « Format ».
   - Synchroniser tout fichier dérivé présent (ex. `INTEGRATION.md`) ; absent → ignorer.
3. **Sinon, `package.json` avec `"version"`** (ex. HUBCSS) :
   - `npm version <level> --no-git-tag-version` (met à jour `package.json` + `package-lock.json`).
   - Prépendre l'entrée CHANGELOG comme ci-dessus.
4. **Sinon (aucune source de version)** :
   - Créer `VERSION` = `0.1.0` et un `CHANGELOG.md` initial, puis traiter comme cas 2.

## 4. Patchnote utilisateur — UNIQUEMENT sur demande explicite

Par défaut, le CHANGELOG reste **purement technique** (étape 3 seule). Ne **jamais** demander ni proposer de patchnote utilisateur.

Seulement si l'utilisateur le demande **explicitement** (ex: « rédige le patchnote », « ajoute une section utilisateur », « pour les utilisateurs »), ajouter dans la **même entrée** CHANGELOG, en tête :

```
### 📣 Pour les utilisateurs
- **Ajouté** : …
- **Amélioré** : …
- **Corrigé** : …
```

Langage simple, sans jargon technique. Cette section se place **avant** la section technique.

## 5. Finalisation

- Committer les fichiers modifiés (`VERSION`/`package.json`/`package-lock.json` + `CHANGELOG.md` + dérivés) :
  `git commit -m "chore(release): bump vX.Y.Z + changelog"`.
- Poursuivre le `git push` vers `main`.
- Si le dépôt est un sous-module de POULIDOR (`git submodule status` non vide côté parent), mettre à jour le pointeur du sous-module dans POULIDOR après le push.

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

- Ne jamais pousser sur `main` sans version incrémentée ni entrée CHANGELOG.
- Une entrée CHANGELOG manquante ou placeholder non complétée = release incomplète.
- Ne pas committer de secrets, backups, ou artefacts d'environnement.
- Ne pas utiliser de commandes template absentes du dépôt courant (ex. `make sync-env` si non défini).
