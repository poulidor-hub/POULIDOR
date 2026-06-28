---
description: "Use when editing backend FastAPI, SQLAlchemy, JWT auth, route modules, or application configuration. Covers async patterns, role helpers, and backend layering."
name: "Backend Guidelines"
applyTo:
  - "backend/*.py"
  - "backend/routes/**/*.py"
---

# Backend Guidelines

- Keep backend flows async end-to-end: `async def`, `AsyncSession`, awaited Hub calls, and awaited database operations.
- Preserve the existing layering:
  - route handlers in [backend/routes](../../backend/routes)
  - auth and role helpers in [backend/hub_auth.py](../../backend/hub_auth.py)
  - Hub client logic in [backend/hub_client.py](../../backend/hub_client.py)
  - ORM models in [backend/models.py](../../backend/models.py)
  - response and payload schemas in [backend/schemas.py](../../backend/schemas.py)
- Prefer existing dependency helpers such as `get_db`, `require_role`, `require_any_role`, and `require_service_account` over inline auth or session plumbing.
- When adding or changing API behavior, update the matching tests in [backend/tests](../../backend/tests) and treat [docs/API.md](../../docs/API.md) as the source for endpoint documentation.
- Configuration behavior is non-trivial in [backend/config.py](../../backend/config.py): preserve the `APP_HOST`, `HUB_HOST`, and local-IP fallback chain unless the task explicitly changes deployment semantics.
- If the change touches backup, Hub messages, or remote deployment flows, consult the dedicated docs first:
  - [docs/BACKUP_RESTORE.md](../../docs/BACKUP_RESTORE.md)
  - [docs/HUB_MESSAGES.md](../../docs/HUB_MESSAGES.md)
  - [docs/REMOTE_APPS.md](../../docs/REMOTE_APPS.md)