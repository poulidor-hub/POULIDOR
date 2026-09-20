---
name: vault-manager
description: "Work with hubctl's encrypted vault (coffre): backup_all (env + secrets + DB dump + PRA replication), restore/restore_all (the explicit coffre-to-disk path: rewrites .env, secrets, DB, re-clones apps), export_recovery, check_divergence, auto-generated passphrase with local key parc.vault.key, change_passphrase, or the coffre UI (view_coffre). Use for any task touching coffre.py, vault_manager.py, pra_config/pra_replicate/pra_restore, or the 'hubctl vault' CLI. sync/backup never modify the disk; restore is the only coffre-to-disk path."
argument-hint: "vault operation, for example: backup_all, restore, export_recovery, check_divergence, change_passphrase, app set-url"
---

# Vault Manager (coffre)

Use this skill when modifying any code that touches the vault (`hubctl_cli/coffre.py`),
the backup manager (`hubctl_cli/vault_manager.py`), the PRA layer
(`hubctl_cli/pra_config.py`, `pra_replicate.py`, `pra_restore.py`), or the coffre UI
(`view_coffre` in `hubctl_cli/menu.py`).

> ⚠️ **Rôle du coffre** : sauvegarde chiffrée dont les chemins de **capture**
> (`sync()`, `backup_all()`) sont **disque → coffre uniquement** — ils ne modifient
> jamais le disque (hors l'artefact de dump DB, cf. tableau « Contenu sauvegardé ») et
> ne poussent jamais rien vers les conteneurs docker.
>
> **Exception assumée** : le chemin de **restauration explicite** `restore()` /
> `restore_all()` (CLI `hubctl vault restore`, menu « Restaurer ») réécrit **depuis le
> coffre vers le disque** : `.env`, secrets, base de données, et re-clone des apps.
> C'est le mécanisme PRA / réinstallation — pas un accessoire de la capture.
>
> Les anciennes API managed (`push_env`/`pull_env`/`managed_env`/`toggle_managed`/
> `auto_import_missing`, supprimées en v0.13.0) restent **interdites** — une
> réintroduction est une régression de design, assertée par
> `test_vault_manager.py::test_managed_api_removed`.

## Architecture

```
Vault (coffre.py)                        # chiffrement Fernet + scrypt (MAGIC=b"HUBCTLV1")
├── unlock(passphrase) / lock()
├── sync()                  # disk → coffre ; capture aussi __apps__ ; purge app:/ws: obsolètes
├── save()                  # écrit vault/parc.vault.enc (chmod 0600) + .bak du coffre précédent
├── set_file(rel, bytes) / get_file(rel) / list_files()    # fichiers base64 (HUB_base/secrets/*)
├── get_entry(key) / list_entries() / set_entry / update_entry / remove_entry
├── reveal(key)             # déchiffre une entrée pour affichage
├── change_passphrase(new_pw)
├── generate_passphrase()   # secrets.token_urlsafe(32) — passphrase auto (≥ hubctl 0.7.0)
├── store_passphrase / load_passphrase / unlock_stored / key_path   # clé locale parc.vault.key
└── restore(...)            # coffre → disque : .env + secrets + DB + git clone apps
                            # (garde anti path-traversal vs PARC_ROOT + validation URL git)

VaultManager (vault_manager.py)
├── backup_all(on_log=)     # sync() + secrets + dump DB + save() + réplication PRA
│                           # → {"env": n, "files": n, "db": bool, "pra": ...}
├── export_recovery()       # recovery/<date>/ en clair (containment is_relative_to(dest))
├── check_divergence()      # sha256(sorted) coffre vs disque → dict informatif
└── restore_all()           # restaure .env + secrets + DB depuis le coffre
```

## Contenu sauvegardé

| Entrée coffre | Source |
|---|---|
| `"hub"` | `HUB_base/.env` |
| `"app:<nom>"` | `APPS/<nom>/.env` |
| `"__files__"` (base64) | `HUB_base/secrets/*` (clés JWT/backup, SA) — récursif, symlinks exclus |
| `"__apps__"` | métadonnées apps (slug, `git_url`, version) — alimentent le re-clone de `restore()` |
| `"HUB_base/backup/hub_dump.sql"` | dump pg_dump (`--data-only --inserts`) de 7 tables critiques : `users`, `applications`, `service_accounts`, `service_account_app_access`, `app_settings`, `user_app_roles`, `schema_migrations` — capturé **dans le coffre** par `backup_all` via `_backup_db` |

> Les entrées legacy `ws:` (anciens `.workshop.env`) ne sont **plus capturées** :
> `sync()` les **purge** du coffre et `export_recovery` les ignore.

## Passphrase & clé locale

- **Création** du coffre : passphrase **auto-générée** (`generate_passphrase()` =
  `secrets.token_urlsafe(32)`), conservée dans `vault/parc.vault.key` (chmod 0600,
  gitigné). Zéro saisie utilisateur.
- **Démarrage** : déverrouillage **silencieux** via `unlock_stored()` (clé locale).
  Le prompt de passphrase n'intervient **qu'en repli** (clé absente/invalide) ;
  Échap → `SystemExit` (on ne démarre pas sans coffre). Une passphrase saisie est
  alors mémorisée (`store_passphrase`).
- `change_passphrase` resynchronise la clé locale ; la clé est **répliquée sur le kit
  PRA** (`pra_replicate` — cf. `test_pra_replicate.py`).
- **Sécurité assumée** : la clé vit en clair à côté du coffre (`coffre.py` l'affirme en
  commentaire) — le coffre n'est **pas** une frontière de sécurité, c'est un filet de
  sauvegarde (snapshot chiffré + restauration out-of-band).

## Règles de cycle

1. **Démarrage** : `unlock_stored()` silencieux → repli prompt passphrase → puis
   **capture automatique** `backup_all()`.
2. **Sauvegarde** (`backup_all`) : disque → coffre uniquement ; ne pousse rien vers
   docker. En UI, « 💾 Sauvegarder maintenant » est un **no-op sans divergence**
   (sinon « ✓ Coffre déjà à jour »).
3. **Restauration** (`hubctl vault restore` / `restore_all` / menu « Restaurer ») :
   chemin **explicite** coffre → disque. Réécrit `.env`/secrets, rejoue la DB,
   re-clone les apps manquantes depuis `__apps__.git_url` (URL validée avant clone).
   À utiliser en PRA / réinstallation — pas comme correctif ordinaire.
4. **Export** (« ⬇ Récupérer » / `export_recovery`) : écrit `recovery/<stamp>/` en
   clair **sans jamais toucher aux fichiers existants** (double garde
   `is_relative_to(dest)`). Note : `export_recovery` lit le **coffre**, jamais le disque.
5. **Divergence** : `check_divergence()` → entrée `[MODIFIÉ]` dans `view_coffre` +
   `hubctl vault status`. La résolution est **explicite** et dans un sens ou l'autre :
   « Sauvegarder maintenant » (disque → coffre) ou « Restaurer » (coffre → disque).
6. **Le coffre ne pousse jamais les `.env` vers les conteneurs docker.** Les
   opérations docker (start/update/...) utilisent les `.env` du disque, inchangés.

## Ajouter une action qui interagit avec le coffre

- Une action qui **modifie un `.env` disque** (rare) : appeler `backup_all()` derrière
  pour rafraîchir la sauvegarde.
- Une action qui **ajoute un secret fichier** (ex. nouveau SA) : `vault.set_file(rel,
  bytes)` puis `vault.save()` — ou simplement `backup_all()` qui capture tout
  `HUB_base/secrets/`.
- **Ne pas** recréer `push_env`/`pull_env`/`managed_env`/`toggle_managed` :
  régression de design. Seul `test_vault_manager.py::test_managed_api_removed`
  asserte leur absence (`test_env_manager.py` ne couvre pas ce point).

## CLI `hubctl vault`

```
hubctl vault backup                          # backup_all (sync + secrets + DB + PRA)
hubctl vault restore                         # restaure .env + secrets + DB depuis le coffre
hubctl vault status                          # état + divergences
hubctl vault export <dest>                   # export du coffre (validation MAGIC + .bak)
hubctl vault import <src>                    # import d'un coffre (validation MAGIC + .bak avant écrasement)
hubctl vault app list                        # apps du coffre (git_url + version)
hubctl vault app set-url <slug> <url>        # corrige le git_url d'une app (__apps__)
```

## Error handling

- Coffre verrouillé / `_data is None` → `backup_all`/`check_divergence` retournent
  vide, aucune écriture. L'UI force le déverrouillage au démarrage.
- `.env` disque absent → ignoré silencieusement par `sync()` ; fichier secret absent → ignoré.
- Path traversal : double garde `is_relative_to(dest)` dans `export_recovery` ;
  garde `PARC_ROOT` + validation d'URL git avant clone dans `restore()`.
- `save()` écrit un **`.bak`** du coffre précédent avant écrasement
  (`parc.vault.enc.bak`).
- Réplication PRA **non bloquante** : un échec n'empêche jamais la sauvegarde de
  réussir (double filet try/except, cf. `pra_replicate.replicate`).

## Fichiers clés

- `hubctl_src/hubctl_cli/coffre.py` — `Vault` (chiffrement, sync + purge, save + .bak,
  restore, passphrase auto + clé locale)
- `hubctl_src/hubctl_cli/vault_manager.py` — `VaultManager` (backup_all + `_backup_db`,
  export_recovery, check_divergence, restore_all)
- `hubctl_src/hubctl_cli/menu.py::view_coffre` — UI (sauvegarder / restaurer /
  récupérer / passphrase / divergence)
- `hubctl_src/hubctl_cli/pra_config.py`, `pra_replicate.py`, `pra_restore.py` — couche PRA
- Coffre : `hubctl_src/hubctl_cli/vault/parc.vault.enc` + `parc.vault.enc.bak` +
  clé `parc.vault.key` — gitignorés (`hubctl_cli/vault/`, `*.vault.enc`). Chemin
  canonique = `<paquet>/vault/` (repli legacy `<PARC_ROOT>/hubctl_cli/vault/`)
- Exports : `hubctl_src/hubctl_cli/recovery/` — gitigné (secrets en clair)
- Tests : `test_vault_manager.py` (dont `test_managed_api_removed`,
  `test_backup_all_does_not_modify_source`), `test_pra_replicate.py`
