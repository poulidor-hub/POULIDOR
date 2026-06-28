---
description: "Add a new backend FastAPI endpoint with the repository's route, schema, auth, and pytest patterns. Use when implementing a new API endpoint, CRUD route, or protected backend operation."
name: "Add Backend Endpoint"
argument-hint: "Describe the endpoint: method, path, behavior, auth role, request body, response shape, and whether models/tests/docs must change"
agent: "agent"
---

Implement the requested backend endpoint for this repository.

Follow these repository-specific rules:

- Start from the existing backend structure before editing:
  - routes live in [backend/routes](../../backend/routes)
  - schemas live in [backend/schemas.py](../../backend/schemas.py)
  - models live in [backend/models.py](../../backend/models.py)
  - auth helpers live in [backend/hub_auth.py](../../backend/hub_auth.py)
  - route registration happens in [backend/main.py](../../backend/main.py)
- Reuse existing dependency helpers such as `get_db`, `get_current_user`, `get_optional_user`, `require_role`, `require_any_role`, and `require_service_account` instead of reimplementing auth checks.
- Match the async FastAPI + SQLAlchemy style used in [backend/routes/items.py](../../backend/routes/items.py) and [backend/routes/preferences.py](../../backend/routes/preferences.py).
- Add or update pytest coverage in [backend/tests](../../backend/tests), following patterns from [backend/tests/test_items.py](../../backend/tests/test_items.py) and the shared fixtures in [backend/tests/conftest.py](../../backend/tests/conftest.py).
- If the endpoint changes the public API contract, update [docs/API.md](../../docs/API.md).
- If the endpoint requires a schema or persistence change, update the minimum necessary combination of:
  - [backend/models.py](../../backend/models.py)
  - [backend/schemas.py](../../backend/schemas.py)
  - [backend/migrations](../../backend/migrations)

Execution checklist:

1. Read the relevant route module and adjacent patterns before writing code.
2. Implement the endpoint in the most appropriate existing route module, or create a new route module only if there is no suitable home.
3. Register any new router in [backend/main.py](../../backend/main.py).
4. Add focused tests for success, auth failures, validation failures, and not-found or conflict cases when relevant.
5. Run the smallest useful validation for the touched area and report what was verified.

Keep the change minimal and consistent with the repository's existing conventions.