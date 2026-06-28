---
name: frontend-crud-page
description: 'Build or update a React CRUD page that follows this repo''s TanStack Query conventions: useApiQuery for reads, useApiMutation for writes, hierarchical queryKeys, invalidateKeys after mutations, conditional auth. Use for adding a list/detail/create/edit/delete page, paginated tables, or fixing fetch+useState anti-patterns.'
argument-hint: 'CRUD scope, for example: list page for /api/items, detail + edit form, paginated table with filters'
---

# Frontend CRUD Page

Use this skill when the task is to add or rework a React page that reads and writes a backend resource. It enforces the conventions from [docs/DATA_FETCHING.md](../../../docs/DATA_FETCHING.md).

This skill covers the frontend only. For the backend endpoint side, use the prompt [/add-backend-endpoint](../../prompts/add-backend-endpoint.prompt.md).

## What This Repository Uses

- Read hook: [frontend/src/hooks/useApiQuery.js](../../../frontend/src/hooks/useApiQuery.js).
- Mutation hook: [frontend/src/hooks/useApiMutation.js](../../../frontend/src/hooks/useApiMutation.js).
- API base URL via [frontend/src/context/ConfigContext.jsx](../../../frontend/src/context/ConfigContext.jsx); auth token via [frontend/src/context/AuthContext.jsx](../../../frontend/src/context/AuthContext.jsx).
- Reference component for paginated lists with filters: [frontend/src/components/DataTable.jsx](../../../frontend/src/components/DataTable.jsx).

## Procedure

1. Define the queryKey contract for the resource.
   - List: `['<domain>']`
   - Filtered or paginated list: `['<domain>', filter, page, perPage]`
   - Single item: `['<domain>', id]`
   - Include every variable that affects the response in the queryKey.

2. Implement the read with `useApiQuery`.
   - Pass `queryKey`, `endpoint`, and `params` for query string values.
   - Use `auth: true` when the endpoint requires a token, so the query is disabled until login.
   - For polling (status, health), pass `refetchInterval` and consider `retry: false`.

3. Implement writes with `useApiMutation`.
   - Static endpoint: `endpoint: '/api/<resource>'` with `method: 'POST'`; `mutate(body)` sends the body as JSON.
   - Dynamic endpoint: `endpoint: ({ id }) => '/api/<resource>/' + id`; `mutate({ id, body: {...} })` for PUT, `mutate({ id })` for DELETE.
   - **Default to optimistic updates with rollback** via `optimisticUpdate: { queryKey, updater }`. The `updater(old, payload)` must return a new immutable value. The hook handles snapshot, rollback on error, and invalidation in `onSettled` automatically.
   - Use `invalidateKeys` alone only for fire-and-forget actions whose result is not displayed (seed, job trigger, action without list state).
   - For multiple caches in one mutation, use `optimisticUpdates: [{ queryKey, updater }, ...]`.
   - Use `mutation.isPending`, `isError`, `error`, `isSuccess`, and per-call `onSuccess` / `onError` callbacks for UX feedback.

4. Wire the UI.
   - Render loading and error states from the query result.
   - Disable submit buttons while `mutation.isPending` is true.
   - For dependent or conditional rendering, gate on `data` being present rather than negating `isLoading` only.

5. Validate.
   - Confirm the data refresh happens automatically after a mutation (no manual refetch).
   - Open React Query DevTools and verify each unique combination of filters produces its own queryKey.
   - Run `cd frontend && npm run build` for non-trivial changes.

## Anti-Patterns To Avoid

- `fetch + useState + useEffect` for data loading; always go through `useApiQuery`.
- Mutations with neither `optimisticUpdate` nor `invalidateKeys`; the UI will silently go stale.
- Falling back to `invalidateKeys` alone when an `optimisticUpdate` would give a snappier UX (default to optimistic).
- Mutating `old` inside an `updater` (e.g. `old.items.push(...)`); always return a new array/object.
- Variables (filters, page, id) outside the queryKey; the cache will return stale data.
- Bypassing `ConfigContext` or `AuthContext` to hardcode URLs or tokens.

## Guardrails

- Keep endpoints relative to `config.apiUrl`; never hardcode a host.
- Do not introduce a parallel HTTP client or a second TanStack Query instance.
- For protected resources, the matching backend role rules live in [docs/API.md](../../../docs/API.md); align the UI states (hide actions the user cannot perform).
