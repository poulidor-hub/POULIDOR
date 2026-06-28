---
description: "Use when changing how the Hub understands registered applications: registration, discovery/OpenAPI, M2M, app roles, messages, backups, health, Docker sync, or integration docs."
name: "Hub Application Contract Guidelines"
applyTo:
  - "hub/app/routes/apps.py"
  - "hub/app/routes/discovery.py"
  - "hub/app/routes/app_backups.py"
  - "hub/app/routes/messages.py"
  - "hub/app/routes/events.py"
  - "hub/app/routes/service_accounts.py"
  - "hub/app/health_checker.py"
  - "hub/app/docker_scanner.py"
  - "hub/app/models.py"
  - "hub/app/schemas.py"
  - "INTEGRATION.md"
  - "how2endpoint.md"
  - "exemple-app.md"
  - "vaultRestorHUB.md"
---

# Hub Application Contract Guidelines

- The Hub knows an application's behavior through explicit contracts, not guesses: `Application` fields, service-account access, user app roles, pushed OpenAPI specs, Docker metadata, health checks, message activity, backup metadata, and integration documents.
- Keep `slug` as the stable identity across app registration, JWT `apps`, `X-Slug`, audit logs, messages, backups, storage paths, Docker sync, and OpenAPI discovery.
- Registration flows live in [hub/app/routes/apps.py](../../hub/app/routes/apps.py): manual create, Docker discovery, `/api/apps/register`, `/api/apps/auto-register`, `/api/apps/me/credentials`, `/api/apps/me/openapi`, pending approval, and shared-service propagation. Preserve whitelist and approval semantics for auto-registered apps.
- App behavior fields should be persisted and surfaced deliberately. If you add behavior such as a capability flag, URL, role model, backup option, or health signal, update the ORM model, Pydantic schemas, migrations, admin UI, tests, and integration docs together.
- Discovery should prefer stored OpenAPI specs pushed by apps. Keep technical endpoint filtering consistent with [how2endpoint.md](../../how2endpoint.md), and use the internal `hub-discovery` service account for proxy exploration instead of exposing M2M secrets to the browser.
- M2M contracts use service-account JWTs with app access in the `apps` claim. App-originated requests should include `X-Slug`; Hub routes must verify the service account is allowed to act for the relevant app before mutating app-owned state.
- Hub messages are Hub-owned data. Apps may send via `/api/messages/m2m/send`, then consume sync/receipt endpoints when they implement an external notification center. Keep user delivery, read receipts, click tracking, and SSE events in sync.
- App backups are stored by the Hub as application artifacts. Preserve the original ZIP bytes, checksum, metadata, retention, encrypted export flow, and Vaultwarden-specific flags. The Hub must not decrypt app secret bundles.
- Health and Docker sync are observational. They should update Hub status and diagnostics without silently changing security-sensitive app configuration.
- When a change alters how third-party apps should integrate, update [INTEGRATION.md](../../INTEGRATION.md) and add focused tests in [hub/tests](../../hub/tests) that prove the contract the Hub now expects.