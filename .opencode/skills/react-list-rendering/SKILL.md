---
name: react-list-rendering
description: 'Render and update React lists correctly in this app: enforce state immutability (spread, map, filter instead of push/splice/sort in place), use stable unique keys (never the array index when items can move/insert/delete), and align with TanStack Query cache updates. Use when adding or fixing list/table UI, debugging stale renders, missing re-renders after add/edit/delete, mixed-up Tailwind classes between rows, or wrong key warnings.'
argument-hint: 'List rendering task, for example: fix items not refreshing after delete, add reorderable list, debug duplicated styles after insert'
---

# React List Rendering

Use this skill whenever a component renders a collection (`array.map(...)`) or mutates state that holds an array or object. It exists because two recurring bugs in React UIs are caused by:

1. **Direct mutation of state** — React skips the re-render because the reference did not change.
2. **Wrong `key` prop** — using the array index makes React reuse the wrong DOM nodes (and Tailwind classes, focus, animations) when items are added, removed, or reordered.

Both patterns also interact poorly with the TanStack Query cache used in this repo (see [docs/DATA_FETCHING.md](../../../docs/DATA_FETCHING.md)), where query data must be treated as read-only.

## What This Repository Uses

- Read hook: [frontend/src/hooks/useApiQuery.js](../../../frontend/src/hooks/useApiQuery.js).
- Mutation hook: [frontend/src/hooks/useApiMutation.js](../../../frontend/src/hooks/useApiMutation.js) — relies on `invalidateKeys` to refresh lists, so mutations rarely require local array edits.
- Reference list/table component: [frontend/src/components/DataTable.jsx](../../../frontend/src/components/DataTable.jsx).
- Companion skill for full pages: [frontend-crud-page](../frontend-crud-page/SKILL.md).

## Rule 1 — Treat state as immutable

React compares the previous and next state by reference. If the reference is the same, no re-render happens, even if the contents changed.

Forbidden on state (or on data returned by `useApiQuery`):

- `arr.push(...)`, `arr.pop()`, `arr.shift()`, `arr.unshift(...)`, `arr.splice(...)`
- `arr.sort(...)`, `arr.reverse()` (they mutate in place)
- `obj.field = value` on an object held in state

Use a fresh array or object instead:

```js
// add
setItems((prev) => [...prev, newItem]);

// update by id
setItems((prev) =>
  prev.map((item) => (item.id === id ? { ...item, name: newName } : item))
);

// delete by id
setItems((prev) => prev.filter((item) => item.id !== id));

// sort without mutating
setItems((prev) => [...prev].sort((a, b) => a.name.localeCompare(b.name)));

// nested update
setUser((prev) => ({ ...prev, address: { ...prev.address, city: newCity } }));
```

Always prefer the functional updater form (`setItems((prev) => ...)`) when the next state depends on the previous one — it avoids stale closures inside event handlers and effects.

## Rule 2 — Use a stable, unique `key`

`key` tells React which DOM node corresponds to which item across renders. The wrong key causes:

- styles, inputs values or animation states bleeding from one row to another after an insert/delete,
- unnecessary unmount/remount of children,
- dev warning "Each child in a list should have a unique key prop".

Guidelines:

- Use the backend `id` (or another stable unique field) as the key. Server resources in this repo always expose one — see schemas in [backend/schemas.py](../../../backend/schemas.py).
- Do **not** use the array index when the list can be reordered, filtered, paginated, or items inserted/removed in the middle. Index keys are only acceptable for a static list whose order never changes during the component lifetime.
- Do **not** use `Math.random()` or `Date.now()` inline in render — a new key on every render forces full remount.
- For client-only items not yet persisted, generate the id once when the item is created (e.g. `crypto.randomUUID()`), store it on the item, and reuse it.
- The `key` goes on the outermost element returned by the `.map(...)` callback (or on the `<Fragment>` if you use the long form `<Fragment key={...}>`).

```jsx
// BAD: index key with a list that supports delete/insert/sort
{items.map((item, index) => (
  <Row key={index} item={item} />
))}

// GOOD
{items.map((item) => (
  <Row key={item.id} item={item} />
))}
```

## Interaction With TanStack Query

In this repo the default mutation pattern is **optimistic update + automatic rollback**, exposed by `useApiMutation` via `optimisticUpdate` / `optimisticUpdates`. The hook snapshots the cache before the request, applies your `updater` immediately, restores the snapshot on error, and invalidates the affected keys in `onSettled` (so the server state always wins eventually).

```js
const { data: items = [] } = useApiQuery({ queryKey: ['items'], endpoint: '/api/items' })

// Suppression instantanée dans l'UI, rollback si l'API répond une erreur
const deleteItem = useApiMutation({
  endpoint: ({ id }) => `/api/items/${id}`,
  method: 'DELETE',
  optimisticUpdate: {
    queryKey: ['items'],
    updater: (old, { id }) => (old || []).filter((item) => item.id !== id),
  },
})
```

Rules for the `updater`:

- Must return a **new reference** (`[...arr]`, `arr.map`, `arr.filter`, `{ ...obj }`). Never mutate `old`.
- Must accept `old` being `undefined` (the query may not have loaded yet).
- Receives the exact payload passed to `mutate(...)` (so `{ id, body }` for dynamic endpoints).

Do **not** mutate `data` returned by `useApiQuery` outside of an `updater` either — the cache hands you the same reference on subsequent renders, and a mutation would corrupt other consumers. If you need a local derived view (sorted, filtered), build a new array with `useMemo`:

```js
const sorted = useMemo(() => [...items].sort((a, b) => a.name.localeCompare(b.name)), [items])
```

`invalidateKeys` (without `optimisticUpdate`) is only acceptable for fire-and-forget actions whose result is not on screen (seed, job trigger).

## Quick Checklist Before Submitting

- No `push`, `pop`, `shift`, `unshift`, `splice`, in-place `sort`/`reverse` on values held in `useState` or returned by `useApiQuery`.
- Every `.map(...)` that renders elements has a `key` from a stable unique id, not the index.
- No `key={Math.random()}` or `key={Date.now()}` in render.
- Mutations use `optimisticUpdate` with an immutable `updater` by default; `invalidateKeys` alone only for fire-and-forget actions.
- Optimistic items are flagged (e.g. `__optimistic: true`) when the UI needs to disable actions or dim them while pending.
- For non-trivial changes, run `cd frontend && npm run build`.
