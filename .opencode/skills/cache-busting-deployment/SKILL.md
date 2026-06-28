---
name: cache-busting-deployment
description: 'Configure, build, or deploy a Single Page Application with strict cache-busting: verify hashed assets, no-store HTML headers, immutable caching for hashed static files, and service-worker invalidation. Use for setup deployment, fix caching, prepare for production, stale frontend, old bundle served, or cache-control header work.'
argument-hint: 'Deployment or caching task, for example: prepare SPA for production, fix stale frontend after deploy, add nginx cache headers'
---

# Cache-Busting and Deployment Protocol

Use this skill whenever the task is to configure, build, deploy, or debug caching for a Single Page Application such as the React frontend in this repository. The goal is simple: users must never stay stuck on an old frontend after a deploy.

This repository already serves the frontend through [nginx.conf](../../../nginx.conf) and [nginx-ssl.conf](../../../nginx-ssl.conf), and builds it with Vite via [frontend/vite.config.js](../../../frontend/vite.config.js). Any deployment or caching work must verify all four checks below.

## The Four Required Checks

1. Asset hashing.
   - Ensure the build emits content-hashed asset filenames for JS, CSS, images, and similar static files.
   - With Vite, production builds normally do this by default; do not replace hashed output names with fixed names.

2. Strict HTML cache control.
   - Apply these headers to `index.html` and any other HTML entry points:
     - `Cache-Control: no-cache, no-store, must-revalidate`
     - `Pragma: no-cache`
     - `Expires: 0`
   - This is the critical protection against browsers serving an outdated app shell.

3. Aggressive caching for hashed assets.
   - Apply these headers to hashed JS, CSS, fonts, and images:
     - `Cache-Control: public, max-age=31536000, immutable`
   - Only do this for assets whose filenames change when content changes.

4. Service worker invalidation.
   - If the app uses a service worker or PWA features, add an explicit update strategy so an older worker cannot pin users to stale assets.
   - At minimum, check for updates on load and activate the new worker promptly (`skipWaiting` / `clientsClaim` or equivalent for the stack in use).
   - If no service worker exists, record that this check is not applicable rather than ignoring it silently.

## What This Repository Uses

- Frontend build: [frontend/vite.config.js](../../../frontend/vite.config.js)
- HTTP frontend serving: [nginx.conf](../../../nginx.conf)
- HTTPS frontend serving: [nginx-ssl.conf](../../../nginx-ssl.conf)
- Frontend container entrypoint that materializes nginx config: [frontend/docker-entrypoint.sh](../../../frontend/docker-entrypoint.sh)

## Procedure

1. Confirm hashed build output.
   - Review [frontend/vite.config.js](../../../frontend/vite.config.js) and keep the Vite production build behavior that emits hashed asset filenames.
   - If a custom Rollup output section is introduced later, verify it still includes content hashes.

2. Set HTML entry points to never be cached.
   - In [nginx.conf](../../../nginx.conf) and [nginx-ssl.conf](../../../nginx-ssl.conf), configure `index.html` (and any future HTML entry points) with:

```nginx
add_header Cache-Control "no-cache, no-store, must-revalidate" always;
add_header Pragma "no-cache" always;
add_header Expires "0" always;
```

3. Cache hashed assets aggressively.
   - In the nginx asset locations, use long-lived immutable caching for hashed static assets:

```nginx
add_header Cache-Control "public, max-age=31536000, immutable" always;
```

   - Do not use a short generic cache like `expires 1d` for production hashed bundles.

4. Check service-worker behavior.
   - Search the frontend for service worker registration, Workbox, PWA plugins, or `navigator.serviceWorker` usage.
   - If present, implement and verify an update path that refreshes clients onto the newest version.
   - If absent, state clearly that the repository currently has no service worker layer.

5. Validate before calling deployment done.
   - Build the frontend with `cd frontend && npm run build`.
   - Inspect the generated asset names in `frontend/dist/` and confirm they are hashed.
   - Verify the server config applies strict HTML headers and immutable asset headers in both HTTP and HTTPS nginx configs.
   - If a service worker exists, test an update flow instead of relying on a cold load only.

## Expected Outcome

After a deploy:

- the browser revalidates `index.html` immediately,
- the HTML points to new hashed bundle filenames,
- old hashed assets may stay cached safely,
- and any service worker update path does not trap the user on a previous release.

## Guardrails

- Never weaken HTML caching for convenience; stale `index.html` is the main cause of users seeing an old SPA after deploy.
- Never give `immutable` caching to non-hashed HTML entry points.
- When editing nginx rules, keep the existing `/api/` and `/hub/` proxy behavior intact.
- If deployment changes touch frontend config or nginx config, finish with a fresh frontend build and a config review rather than assuming defaults are still correct.
