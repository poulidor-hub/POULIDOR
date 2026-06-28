---
name: release-sync
description: 'Prepare or verify a release by syncing VERSION across the repo, checking CHANGELOG coverage, updating .env version fields, and validating the standard release commands. Use for version bump, release preparation, changelog sync, or version consistency checks.'
argument-hint: 'Requested release action, for example: check consistency, bump patch, set 2.5.0, or prepare release 2.5.0'
---

# Release Sync

Use this skill when the task is about preparing a release, bumping a version, synchronizing versioned files, or checking whether the repository is release-ready.

## What This Repository Uses

- [VERSION](../../../VERSION) is the source of truth.
- The main automation entry point is [scripts/bump_version.py](../../../scripts/bump_version.py).
- Hook installation lives in [scripts/install-hooks.sh](../../../scripts/install-hooks.sh).
- API docs versioning lives in [docs/API.md](../../../docs/API.md).
- Environment synchronization for `.env` uses `make sync-env` from [Makefile](../../../Makefile).

## Procedure

1. Determine the requested release action.
   - For validation only, use the consistency path.
   - For a bump, decide whether it is `patch`, `minor`, `major`, or an explicit version.

2. Verify the current state before changing files.
   - Inspect [VERSION](../../../VERSION).
   - Check whether [CHANGELOG.md](../../../CHANGELOG.md) already contains the target version.
   - Review any uncommitted changes before performing automated synchronization.

3. Use the repository's supported automation instead of hand-editing version files.
   - Validation: run `python scripts/bump_version.py --check`.
   - Synchronize current version: run `python scripts/bump_version.py`.
   - Bump release: run `python scripts/bump_version.py patch`, `minor`, or `major`.
   - Set an explicit version: run `python scripts/bump_version.py --set X.Y.Z`.

4. Confirm the synchronized file set after the script runs.
   - [VERSION](../../../VERSION)
   - [frontend/package.json](../../../frontend/package.json)
   - [backend/main.py](../../../backend/main.py)
   - [.env.example](../../../.env.example)
   - [.env](../../../.env) when present
   - [docs/API.md](../../../docs/API.md)

5. Verify release notes and environment follow-through.
   - Ensure [CHANGELOG.md](../../../CHANGELOG.md) has an entry for the target version.
   - If `.env`, ports, or deployment settings changed during release preparation, run `make sync-env`.
   - If hooks are missing in a fresh clone, install them with [scripts/install-hooks.sh](../../../scripts/install-hooks.sh).

6. Prefer repo-native verification.
   - Backend verification: `make test` or `make test-cov`.
   - Frontend-only verification after version-visible UI changes: `cd frontend && npm run build`.

## Guardrails

- Do not hand-edit multiple versioned files when [scripts/bump_version.py](../../../scripts/bump_version.py) already owns that workflow.
- Treat a missing changelog entry as incomplete release preparation, even if version synchronization succeeded.
- Remember that the built frontend does not pick up runtime env changes automatically; rebuild when release work changes Vite-visible configuration.
