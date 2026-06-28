---
description: "Use when writing or updating backend pytest suites, fixtures, auth mocks, or API tests. Covers async clients, fixture reuse, and storage-related test setup."
name: "Backend Test Guidelines"
applyTo: "backend/tests/**/*.py"
---

# Backend Test Guidelines

- Reuse the fixtures in [backend/tests/conftest.py](../../backend/tests/conftest.py) before introducing new ones: `client`, `authenticated_client`, `admin_client`, `viewer_client`, `m2m_client`, `db_session`, `mock_hub_client`, and `mock_hub_auth` already cover the common cases.
- Keep API tests async and aligned with the existing stack: `AsyncClient`, `ASGITransport`, pytest async fixtures, and mocked Hub boundaries.
- Follow the current organization style from [backend/tests/test_auth.py](../../backend/tests/test_auth.py), [backend/tests/test_items.py](../../backend/tests/test_items.py), and [backend/tests/test_m2m.py](../../backend/tests/test_m2m.py): group cases by endpoint family or access level rather than by helper internals.
- Storage-related tests must preserve the early `UPLOADS_DIR` setup pattern shown in [backend/tests/conftest.py](../../backend/tests/conftest.py); that environment variable must be set before importing the app or storage modules.
- The test suite runs against in-memory SQLite, not PostgreSQL. If a change depends on Postgres-specific SQL or transaction behavior, call that out and add manual verification.
- Preferred verification commands are `make test` and `make test-cov` from the repository root.