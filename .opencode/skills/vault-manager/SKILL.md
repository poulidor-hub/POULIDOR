---
name: vault-manager
description: "Work with hubctl's encrypted vault manager: push/pull .env files, check divergence, toggle managed_env mode. Use for any task touching vault_manager.py, coffre.py, or .env lifecycle (add/remove/start/update apps, setup wizard, workshop moves)."
argument-hint: "vault operation, for example: push env before start, pull after update, check divergence, add edit-env to coffre view"
---

# Vault Manager

Use this skill when modifying any code that touches the .env lifecycle or the vault
(coffre). The vault (`hubctl_cli/vault/parc.vault.enc`) is the **single source of truth**
for all `.env` files in the park.

## Architecture

```
VaultManager
├── vault: Vault          # chiffrement Fernet+scrypt (coffre.py)
├── push_env(target)      # coffre → disque
├── pull_env(target)      # disque → coffre
├── check_divergence()    # compare hash coffre vs disque
├── auto_import_missing() # importe les .env absents du coffre
├── toggle_managed()      # active/désactive le mode managé
└── managed_env: bool     # lu depuis __meta__.managed_env
```

## Schema

```json
{
  "__meta__": { "managed_env": true, "version": 1 },
  "hub": { "KEY": "value", ... },
  "app:<name>": { "KEY": "value", ... },
  "ws:<name>": { "KEY": "value", ... }
}
```

## Target mapping

| Target key | Chemin disque |
|-----------|---------------|
| `"hub"` | `HUB_base/.env` |
| `"app:<nom>"` | `APPS/<nom>/.env` |
| `"ws:<nom>"` | `APP_Workshop/<nom>/.env` |

## Lifecycle rules

1. **Before any docker operation** (start, restart, update): call `push_env(target)`
   to write .env from vault to disk.
2. **After any docker operation**: call `pull_env(target)` to read .env from disk
   back into vault (captures runtime values like ports, version).
3. **On add_app**: `pull_env("app:<name>")` after INITIALISE.py runs.
4. **On remove_app**: do NOT pull — keep vault entry as history.
5. **On preload**: `auto_import_missing()` + `check_divergence()`.
6. **If managed_env is OFF**: skip all push/pull. Apps manage their own .env.

## Adding a new action that needs push/pull

1. The hook is in `_run_action()` in menu.py. Ensure the action goes through it.
2. `_target_from_args()` must be able to deduce the vault target from the action's args.
3. If the action doesn't use `_run_action` (e.g., `_workshop_menu`, `setup_wizard`),
   add explicit `push_env`/`pull_env` before/after docker operations.

## Divergence workflow

1. `check_divergence()` compares `sha256(sorted(vault_data))` vs `sha256(sorted(disk_data))`.
2. If divergent, the entry is marked `[MODIFIÉ]` in coffre view.
3. The dashboard shows `⚠ N .env divergents` in the resources column.
4. User resolves via coffre: import (disk→vault) or overwrite (vault→disk).

## Toggle managed_env

- Default: `true` if `APP_ENV=production`, `false` if `development` or absent.
- Toggle accessible from coffre submenu.
- Persisted in vault `__meta__.managed_env`.
- When OFF, hubctl never touches .env files on disk — same behavior as before this feature.

## Error handling

- If vault is locked → `managed_env` is temporarily OFF, no push/pull.
- If disk .env is missing → `push_env` creates it, `pull_env` skips silently.
- If vault file is corrupted → alert user, disable managed mode until recreated.
- Push/pull failures are non-fatal: the docker operation still proceeds.
