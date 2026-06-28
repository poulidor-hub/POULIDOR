---
name: verify-feature
description: 'Standard verification workflow after implementing or modifying a feature in this template: rebuild the right Docker layer, read boot logs, run pytest inside the container, exercise the endpoint via API, and re-read logs to catch runtime errors. Use this every time a backend route, model, migration, hub_auth helper, frontend hook, or component changes — before declaring the task done.'
argument-hint: 'What was changed (e.g. "added GET /api/items/search route", "changed UserPreference schema", "fixed M2M auth bug")'
---

# Verify Feature

Use this skill **immediately after implementing a change** to confirm the app still boots, the change works end-to-end in the real Docker runtime, and no regression slipped through. The cycle is always the same six steps — apply only the ones that match the change scope.

## When To Apply Which Step

| Change type | A (rebuild) | B (boot logs) | C (pytest) | D (API call) | E (runtime logs) | F (frontend) |
|-------------|-------------|---------------|------------|--------------|------------------|--------------|
| Backend Python route/handler/schema | `make restart-api` | yes | `make test-docker` | yes | yes | no |
| New backend dependency or Dockerfile change | `make build && make up` | yes | `make test-docker` | yes | yes | no |
| SQL migration | `make restart-api` | **critical** | `make test-docker` | yes | yes | no |
| Frontend JSX/hook/style | no (Vite HMR via `make dev`) or `make build && make up` if image-baked | only on rebuild | no | smoke check in browser | no | `cd frontend && npm run build` |
| `.env`, ports, `VERSION` | `make sync-env && make up` | yes | optional | `make health` | yes | rebuild required |
| Pure refactor / docs | no | no | `make test` (host) suffit | no | no | no |

## Step A — Rebuild the right layer

Pick the cheapest command that picks up the change:

```bash
make restart-api          # Pure .py change, no new dep, no Dockerfile change
make build && make up     # New pip dep, Dockerfile edit, or stale image suspected
make dev                  # First boot of the session (rebuild + foreground logs)
make sync-env && make up  # .env / VERSION / port change
```

Never skip `make sync-env` after editing `.env` — `FRONTEND_HTTPS_PORT` and `APP_VERSION` are derived there (see [AGENTS.md](../../../AGENTS.md)).

## Step B — Read the boot logs

```bash
make logs-api    # Ctrl+C once you see "Application startup complete"
```

Healthy boot signature:

```
INFO:     Uvicorn running on http://0.0.0.0:8000
INFO:     Application startup complete.
```

Common failure signatures and what they mean:

| Log fragment | Likely cause | Fix |
|--------------|--------------|-----|
| `bind: address already in use` | Port collision on host | Change `API_PORT`/`FRONTEND_PORT` in `.env`, then `make sync-env && make up` |
| `psycopg.OperationalError` / `could not connect to server` | Postgres not ready or wrong creds | Check `make logs-db`; confirm `POSTGRES_*` env vars |
| `relation "..." does not exist` | Migration didn't run / order issue | Inspect `backend/migrations/`, see [.github/instructions/migrations-sql.instructions.md](../../instructions/migrations-sql.instructions.md) |
| `ImportError` / `ModuleNotFoundError` | Forgot dep in `backend/requirements.txt` or missed `make build` | Add dep, then `make build && make up` |
| Pydantic `ValidationError` at startup | Schema/model mismatch | Reconcile [backend/models.py](../../../backend/models.py) and [backend/schemas.py](../../../backend/schemas.py) |
| `RuntimeError: Hub auth ...` | Missing `HUB_*` env or unreachable Hub | Check `.env`, see [backend/hub_auth.py](../../../backend/hub_auth.py) |

If boot fails: fix root cause, repeat Step A. Do not move on.

## Step C — Run pytest inside the container

Two complementary commands:

```bash
make test           # Host pytest, in-memory SQLite — fast unit feedback (~seconds)
make test-docker    # Same suite inside the api container — runtime image, mirrors prod
```

Always run `make test-docker` after backend changes: it executes against the same Python interpreter, dependencies, and OS layer as production, and surfaces issues that SQLite-on-host hides (Postgres-specific SQL, locale, missing system packages).

For coverage:

```bash
make test-docker-cov
```

If a test fails: read the trace, fix code or test, repeat Step C only (no rebuild needed for `.py` test changes since the source is mounted — verify with `docker compose config | grep -A2 volumes`; if not mounted, `make restart-api` first).

## Step D — Exercise the endpoint via API

Smoke check first:

```bash
make health             # GET /api/health
make health-detailed    # GET /api/health/detailed (DB, Hub reachability)
```

Then hit the actual change. Reuse the JWT obtained from a Hub login or set `X-API-Key` for M2M:

```bash
# Public endpoint
curl -sf http://localhost:${API_PORT:-9045}/api/items | python3 -m json.tool

# Authenticated (JWT)
curl -sf -H "Authorization: Bearer $TOKEN" \
  http://localhost:${API_PORT:-9045}/api/items/42 | python3 -m json.tool

# M2M (X-API-Key)
curl -sf -H "X-API-Key: $APP_API_KEY" \
  -X POST http://localhost:${API_PORT:-9045}/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"verify"}' | python3 -m json.tool
```

Or use Swagger UI for interactive testing: `http://localhost:${API_PORT:-9045}/api/docs` (see [docs/API.md](../../../docs/API.md)).

Expected: HTTP 2xx with the documented response shape. A 4xx with the *intended* validation message is also a pass — it means auth/validation works.

## Step E — Re-read runtime logs

The request you just sent may have triggered a warning that did not block the response. Always check:

```bash
docker compose logs --tail=80 api
```

Watch for:

- `WARNING` / `ERROR` lines you did not have before
- Unhandled exception tracebacks (a 500 always logs one)
- SQLAlchemy `SAWarning` (relationship config, implicit IO)
- Slow query notices
- N+1 patterns (many identical `SELECT` lines in a row)

If anything new appears: treat it as a bug and loop back to A or C as appropriate.

## Step F — Frontend validation

After any change under [frontend/src](../../../frontend/src):

```bash
cd frontend && npm run build
```

The built bundle does **not** read runtime env vars — every `VITE_*` change requires `make build && make up` to bake new values into the image.

For interactive UI smoke check, open `http://localhost:${FRONTEND_PORT:-4250}` (or HTTPS on `FRONTEND_PORT + 1`).

## Definition Of Done

A feature is verified only when:

1. `make logs-api` shows `Application startup complete` with no new warnings.
2. `make test-docker` is green (no skipped tests added without justification).
3. The new/changed endpoint returns the expected response via `curl` or Swagger.
4. `docker compose logs --tail=80 api` is clean after the test request.
5. (If frontend touched) `npm run build` succeeds and the affected screen renders.

If any check fails, fix before reporting completion. Do not document "works on my machine" — the cycle above *is* the local proof.
