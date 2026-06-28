---
description: "Use when writing or updating SQL migrations, schema changes, or backend/migrations files. Covers filename format, idempotent statements, and this project's automatic migration runner."
name: "SQL Migration Guidelines"
applyTo:
  - "backend/migrations/*.sql"
  - "backend/migrations/**/*.sql"
---

# SQL Migration Guidelines

- Name migration files with the existing numeric prefix format used by the runner in [backend/database.py](../../backend/database.py): `NNN_description.sql` such as `001_add_column.sql`.
- Keep migrations safe to replay in partially migrated environments. The runner records only the numeric prefix in `schema_migrations`, and executes each statement separately with a savepoint in [backend/database.py](../../backend/database.py).
- Write statements so they tolerate already-applied schema changes when practical, because a failing statement is logged and skipped rather than aborting the whole migration file.
- Keep each SQL statement terminated by `;`. The runner splits file content on semicolons before executing statements.
- Prefer additive, forward-only changes that match the current startup flow: migrations are applied automatically during app startup via [backend/main.py](../../backend/main.py) and [backend/database.py](../../backend/database.py).
- If a schema change affects ORM models or API payloads, update the matching Python layers in the same task:
  - [backend/models.py](../../backend/models.py)
  - [backend/schemas.py](../../backend/schemas.py)
  - [backend/routes](../../backend/routes)
  - [backend/tests](../../backend/tests)
- Call out PostgreSQL-specific behavior explicitly when tests only cover SQLite, because the automated test suite does not exercise migrations against the production engine.
