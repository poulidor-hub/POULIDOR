---
name: deploy-troubleshoot
description: 'Deploy or troubleshoot a Hub-connected app: enable HTTPS with auto-signed certs and the /hub/ proxy, deploy on a remote server with auto IP detection and Hub whitelist, diagnose registration failures, mixed content, SSE drops, and JWT/JWKS issues. Use for HTTPS rollout, remote deployment, network whitelist problems, or post-deploy health diagnostics.'
argument-hint: 'Deployment task, for example: enable HTTPS, deploy on remote server, fix auto-registration, debug mixed content, debug SSE'
---

# Deploy and Troubleshoot

Use this skill when the task involves deploying a Hub-connected app, switching to HTTPS, deploying on a remote server, or diagnosing connectivity issues with the Hub. References: [docs/HTTPS.md](../../../docs/HTTPS.md) and [docs/REMOTE_APPS.md](../../../docs/REMOTE_APPS.md).

For SPA cache headers, stale frontend bundles, or production cache-busting rules, also use the [cache-busting-deployment](../cache-busting-deployment/SKILL.md) skill.

## What This Repository Uses

- Orchestration: [docker-compose.yml](../../../docker-compose.yml), [Makefile](../../../Makefile).
- HTTPS frontends: [nginx.conf](../../../nginx.conf), [nginx-ssl.conf](../../../nginx-ssl.conf), [scripts/generate-ssl.sh](../../../scripts/generate-ssl.sh), [ssl/openssl.cnf](../../../ssl/openssl.cnf).
- Frontend bootstrap: [frontend/docker-entrypoint.sh](../../../frontend/docker-entrypoint.sh), [frontend/src/config.js](../../../frontend/src/config.js).
- Host and IP detection logic: [backend/config.py](../../../backend/config.py).
- Health and registration state: `GET /api/health` and `GET /api/health/detailed` in [backend/main.py](../../../backend/main.py).

## Procedure

1. Pick the deployment lane.
   - Same server as the Hub: leave `APP_HOST` empty so it falls back through `APP_HOST -> HUB_HOST -> detected local IP`.
   - Remote server: set `HUB_HOST` to the Hub IP and, if auto-detection is wrong, set `APP_HOST` explicitly.

2. Enable HTTPS (when required).
   - Set `HTTPS_ENABLED=true` in `.env`.
   - Run `make ssl` once to generate `ssl/server.crt` and `ssl/server.key`.
   - Run `make sync-env` so `FRONTEND_HTTPS_PORT` stays equal to `FRONTEND_PORT + 1`.
   - Start with `make up` (or `make dev`); the entrypoint switches nginx to [nginx-ssl.conf](../../../nginx-ssl.conf).
   - Access the app at `https://<host>:<FRONTEND_PORT + 1>`.

3. Confirm the `/hub/` proxy is in place.
   - In HTTPS mode the frontend talks to the Hub via `${origin}/hub`, configured in [frontend/src/config.js](../../../frontend/src/config.js) and [frontend/src/context/ConfigContext.jsx](../../../frontend/src/context/ConfigContext.jsx).
   - Nginx must proxy `/hub/` with `proxy_buffering off`, `proxy_cache off`, and a long `proxy_read_timeout` for SSE.

4. Hub-side prerequisites for remote apps.
   - The Hub must allow the app's network in `APP_WHITELIST_NETWORKS` (defaults cover `172.,192.,10.`).
   - Restart the Hub after changing the whitelist.

5. Verify the app is healthy after deploy.
   - `curl http://<host>:<API_PORT>/api/health` returns `hub_connected: true` once registered.
   - `curl http://<host>:<API_PORT>/api/health/detailed` shows JWKS cache state, M2M token availability, and discovered services.

## Common Diagnostics

- Auto-registration refused: the Hub IP whitelist rejected this server. Update `APP_WHITELIST_NETWORKS` on the Hub or set `APP_HOST` to a whitelisted IP.
- Wrong detected IP (e.g. `172.x`): set `APP_HOST` explicitly in `.env`.
- Browser blocks Hub calls in HTTPS (mixed content): confirm the frontend is using `/hub/...` and that [nginx-ssl.conf](../../../nginx-ssl.conf) defines the `/hub/` location.
- SSE disconnects fast: check `proxy_buffering off`, `proxy_cache off`, and a long `proxy_read_timeout` in the `/hub/` block.
- JWT validation fails after Hub restart: JWKS cache may be stale; the lifespan loop in [backend/main.py](../../../backend/main.py) re-initializes Hub auth, but a manual `make restart-api` forces it.
- Frontend env changes not visible after restart: the build is static, run `cd frontend && npm run build` (or rebuild the frontend container) when Vite-visible config changes.

## Guardrails

- Never break the invariant `FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1`; rely on `make sync-env`.
- Do not commit real `ssl/server.key`; the generated cert is local and self-signed.
- Do not point the backend at HTTPS for internal Hub calls; backend ↔ Hub stays on HTTP inside the Docker network.
- When changing `.env` ports or `VERSION`, always re-run `make sync-env` before `make up`.
