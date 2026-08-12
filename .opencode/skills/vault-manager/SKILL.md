---
name: vault-manager
description: "Work with hubctl's encrypted vault (coffre) which is a READ-ONLY backup of all .env files and HUB_base/secrets/* . Use for any task touching vault_manager.py, coffre.py, backup_all, export_recovery, check_divergence, passphrase, or the coffre UI. The vault NEVER writes .env files to disk."
argument-hint: "vault operation, for example: backup_all, export_recovery, check_divergence, change_passphrase, add file to backup set"
---

# Vault Manager (coffre)

Use this skill when modifying any code that touches the vault (`hubctl_cli/coffre.py`),
the backup manager (`hubctl_cli/vault_manager.py`), or the coffre UI
(`view_coffre` in `hubctl_cli/menu.py`).

> ⚠️ **Rôle du coffre (depuis v0.13.0) : sauvegarde chiffrée EN LECTURE SEULE sur le disque.**
> Le coffre **ne réécrit jamais** les `.env` : pas de `push_env`/`pull_env`/`managed_env`/
> `toggle_managed`/`auto_import_missing` (ces fonctions ont été **supprimées** en v0.13.0).
> Le disque reste la source de vérité ; le coffre n'est qu'une **copie de sauvegarde**.

## Architecture

```
Vault (coffre.py)                       # chiffrement Fernet + scrypt (MAGIC=b"HUBCTLV1")
├── unlock(passphrase) / lock()
├── sync()                # disk → coffre (LECTURE seule, jamais d'écriture disque)
├── save()                # chiffre et écrit hubctl_cli/vault/parc.vault.enc (chmod 0600)
├── set_file(rel, bytes)  # ajoute un fichier (base64) — utilisé pour HUB_base/secrets/*
├── get_file(rel) / list_files()
├── get_entry(key) / list_entries()
└── change_passphrase(new_pw)

VaultManager (vault_manager.py)
├── backup_all(on_log=)        # sync() + capture HUB_base/secrets/* + save()
├── export_recovery()          # écrit hubctl_cli/recovery/<date>/ (secrets en clair, path-contained)
└── check_divergence()         # hash coffre vs disque → dict informatif (badge [MODIFIÉ])
```

## Contenu sauvegardé

| Entrée coffre | Source disque |
|---|---|
| `"hub"` | `HUB_base/.env` |
| `"app:<nom>"` | `APPS/<nom>/.env` |
| `"__files__"` (base64) | `HUB_base/secrets/*` (clés JWT/backup, SA) |

## Règles de cycle (NON-négociables)

1. **Passphrase obligatoire à chaque démarrage** (prod ET dev). Création forcée si aucun coffre.
   Si l'utilisateur fait Échap → `SystemExit` (on ne démarre pas sans coffre).
2. **Capture automatique au démarrage** : après déverrouillage, `backup_all()` est appelé.
3. **Bouton « 💾 Sauvegarder maintenant »** (coffre UI) → `backup_all()`.
4. **Bouton « ⬇ Récupérer (export) »** → `export_recovery()` écrit `hubctl_cli/recovery/<stamp>/`
   reproduisant l'arborescence, **sans jamais toucher aux fichiers existants** (garde de
   containment `is_relative_to(dest)`).
5. **Divergence = informatif uniquement.** `check_divergence()` marque `[MODIFIÉ]` et le
   dashboard affiche `⚠ N .env divergents`. **Aucune résolution automatique** : pas
   d'écrasement du disque par le coffre, ni l'inverse.
6. **Le coffre ne pousse/jamais les `.env` vers les conteneurs docker.** Les opérations
   docker (start/update/...) utilisent les `.env` du disque, inchangés.

## Ajouter une action qui interagit avec le coffre

- Une action qui **modifie un `.env` disque** (rare) : après modification, appeler
  `vault_mgr.backup_all()` pour rafraîchir la sauvegarde. Ne **jamais** écrire le coffre
  vers le disque.
- Une action qui **ajoute un secret fichier** (ex. nouveau SA) : `vault.set_file(rel, bytes)`
  puis `vault.save()` — ou simplement `backup_all()` qui capture tout `HUB_base/secrets/`.
- Ne **pas** recréer de `push_env`/`pull_env`/`managed_env` : c'est une régression de
  design. Les tests `test_vault_manager.py` et `test_env_manager.py` assertent leur absence.

## Divergence (workflow lecture seule)

1. `check_divergence()` compare `sha256(sorted(disk))` vs `sha256(sorted(coffre))`.
2. Si divergent → entrée marquée `[MODIFIÉ]` dans la vue coffre + badge dashboard.
3. L'utilisateur peut : **Sauvegarder maintenant** (rafraîchit le coffre depuis le disque)
   ou **Récupérer (export)** (écrit le coffre dans `recovery/` sans écraser le disque).

## Error handling

- Coffre verrouillé / `_data is None` → `backup_all`/`check_divergence` retournent vide,
  aucune écriture. L'UI force le déverrouillage au démarrage.
- `.env` disque absent → `sync()` l'ignore silencieusement ; `export_recovery` saute l'entrée.
- Fichier secret absent → ignoré.
- Path traversal dans `export_recovery` → bloqué par `is_relative_to(dest)` (double garde).

## Fichiers clés

- `hubctl_cli/coffre.py` — `Vault` (chiffrement, sync lecture-seule, save)
- `hubctl_cli/vault_manager.py` — `VaultManager` (backup_all, export_recovery, check_divergence)
- `hubctl_cli/menu.py::view_coffre` — UI (sauvegarder / récupérer / passphrase / divergence)
- `hubctl_cli/vault/parc.vault.enc` — le coffre (gitignoré via `*.vault.enc`)
- `hubctl_cli/recovery/` — exports en clair (**gitignoré** depuis v0.13.x — secrets)
