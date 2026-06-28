---
name: backup-restore-ops
description: 'Run or implement Hub backup, restore, and sync operations on this app: estimate size, create ZIP backup with data.json + files/, restore with upsert or clear_existing, sync to or from the Hub. Use for admin backup tasks, disaster recovery, ON CONFLICT upsert restores, or wiring new tables into the generic backup flow.'
argument-hint: 'Action to perform, for example: estimate, backup, download, restore file, sync-to-hub, sync-from-hub, or add table to backup'
---

# Backup and Restore Operations

Use this skill when the task involves the generic backup/restore system: creating, downloading, restoring, or synchronizing backups with the Hub. The reference doc is [docs/BACKUP_RESTORE.md](../../../docs/BACKUP_RESTORE.md).

## What This Repository Uses

- All endpoints are admin only and live in [backend/routes/backup.py](../../../backend/routes/backup.py).
- File storage helpers are in [backend/storage.py](../../../backend/storage.py).
- Pydantic shapes are in [backend/schemas.py](../../../backend/schemas.py) (`BackupEstimate`, `BackupMetadata`, `BackupResponse`, `RestoreRequest`, `RestoreResponse`, `SyncToHubRequest`, `SyncFromHubRequest`).
- Auto-discovery of tables is generic; system tables `alembic_version` and `spatial_ref_sys` are excluded.
- Restore uses PostgreSQL `INSERT ... ON CONFLICT ... DO UPDATE` (upsert).

## Prerequisites

- The caller has an admin token on this app.
- For sync to or from the Hub: the app is registered with `IS_SHARED=true` and the M2M service account is functional.
- The database is PostgreSQL in production; the test suite uses SQLite and does not exercise these endpoints.

## Procedure

1. Identify the action.
   - estimate, backup, download, list, delete, restore from file, sync-to-hub, sync-from-hub.

2. Estimate before a large backup.
   - `GET /api/admin/backup/estimate` returns table counts, file count, total size, and an estimated duration.

3. Create a backup.
   - `POST /api/admin/backup` returns a `BackupResponse` with the metadata and a `download_url`.
   - Output ZIP layout:
     - `data.json` with `metadata` and `data` keyed by table name
     - `files/` mirroring uploaded files

4. Download or list.
   - `GET /api/admin/backup/download?backup_id=...` streams the ZIP.
   - `GET /api/admin/backup/list` enumerates local backups.
   - `DELETE /api/admin/backup/{backup_id}` removes a local backup.

5. Restore from a file.
   - `POST /api/admin/restore` with multipart `file=@backup.zip` and `clear_existing=false|true`.
   - Default mode is upsert per primary key.
   - `clear_existing=true` truncates target tables first; treat it as destructive.
   - Missing columns in the live schema are ignored; missing tables surface in `warnings`.

6. Sync with the Hub.
   - Push: `POST /api/admin/sync-to-hub` with optional `description`.
   - Pull: `POST /api/admin/sync-from-hub` with optional `backup_id` and `clear_existing`.
   - The Hub then triggers `POST /api/admin/restore` on this app to apply the data.

7. Adding a new table to the backup flow.
   - Define the model in [backend/models.py](../../../backend/models.py); the generic backup picks it up automatically.
   - For non-trivial column types, confirm serialization in [backend/routes/backup.py](../../../backend/routes/backup.py) (`_serialize_value` / `_deserialize_value`); `datetime`, `date`, `Decimal`, `bytes` are already covered with the `__type__` marker.
   - If the table needs schema migrations, add a file under [backend/migrations](../../../backend/migrations) following the rules in [.github/instructions/migrations-sql.instructions.md](../../instructions/migrations-sql.instructions.md).

## Guardrails

- `clear_existing=true` is destructive; require explicit confirmation in the task before sending it.
- These endpoints are PostgreSQL-specific (`information_schema.tables`, `ON CONFLICT`); do not assume SQLite parity.
- Files larger than the nginx `client_max_body_size` will fail with HTTP 413 during restore uploads; check [nginx.conf](../../../nginx.conf) and [nginx-ssl.conf](../../../nginx-ssl.conf) when needed.
- Never bypass admin auth for these routes, even for scripts; reuse `require_role("admin")` from [backend/hub_auth.py](../../../backend/hub_auth.py).
