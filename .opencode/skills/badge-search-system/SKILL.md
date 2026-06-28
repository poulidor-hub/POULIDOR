---
name: badge-search-system
description: 'Install the badge-based global search system on a list page. The search scans ALL fields (including related items), shows clickable badges indicating which fields matched, and supports per-field exclusion. Replaces per-column header filters with a single powerful search bar + badge toolbar.'
argument-hint: 'Page to install badges on, e.g. "Orders page", "Contracts list", "Budgets view"'
---

# Badge Search System

Use this skill when the task is to add the badge-based global search to a list page, or to expand an existing search to cover all fields. The system replaces per-column DataTable filters with a unified search bar + clickable badges showing which fields matched.

## What It Does

- **One search bar** scans ALL fields of the entity (including related/child records like items, documents).
- **Badge toolbar** below the search shows which fields matched (e.g. "Modèle", "N° Commande", "Fournisseur").
- **Click a badge** to exclude results matched via that field (strikethrough style). Click again to re-include.
- **Exclusion is server-side** — pagination stays correct, total count adjusts.
- **Multi-field matches**: an entity matched on "Modèle" AND "Fournisseur" stays visible when ONLY "Modèle" is excluded — it's still hit via "Fournisseur".
- **Replaces per-column filters** — all columns become `filterable: false`; searching moves to the global bar.

## Architecture Overview

```
┌─ Frontend ──────────────────────────────────────────────────┐
│  TableToolbar (search input)                                │
│  └─ Badge bar (extra prop) ← detectedFields (useMemo)       │
│     └─ Click → toggle excludedFields (Set) → API call       │
│                                                             │
│  DataTable ← orders/assets (from server, already filtered)  │
│  Paginator ← totalRecords (from server, after exclusion)    │
└─────────────────────────────────────────────────────────────┘
        │ GET /api/orders?search=dell&exclude_fields=supplier
        ▼
┌─ Backend ───────────────────────────────────────────────────┐
│  Route: parse exclude_fields csv → List[str]                 │
│  CRUD:                                                        │
│    1. SQL WHERE (all fields + related items via EXISTS)     │
│    2. If exclude_fields + search active:                    │
│       fetch ALL matches → compute match_fields per row      │
│       → filter: keep if any(match_field NOT excluded)       │
│       → repaginate (skip/limit on filtered list)            │
│    3. Return match_fields in response                       │
│  Schema: OrderOut.match_fields: Optional[List[str]]         │
└─────────────────────────────────────────────────────────────┘
```

## Installation Procedure

### Phase 1 — Backend

#### 1.1 Define match fields

In `app/crud.py`, define every searchable field:

```python
_DOMAIN_MATCH_FIELDS = [
    ("field1", "column_or_attr_1"),
    ("field2", "column_or_attr_2"),
    # ... every field that appears in the SQL search OR clause
]

# For fields from child/related records (e.g. items, documents):
_DOMAIN_CHILD_MATCH_FIELDS = [
    ("child_field1", "child_column_1"),
    # ...
]
```

**Rule**: the badge name (first element) must match what you'll use in `FIELD_LABELS` on the frontend. Use snake_case, descriptive names.

#### 1.2 Create match_fields computation functions

```python
def compute_domain_match_fields(entity, search: str,
                                 child_texts: Optional[Dict[str, str]] = None) -> List[str]:
    """Return list of field names from *entity* containing *search*."""
    if not search:
        return []
    term = search.lower()
    matched: List[str] = []
    for field_name, attr in _DOMAIN_MATCH_FIELDS:
        value = getattr(entity, attr, None)
        if value and term in str(value).lower():
            matched.append(field_name)
    # Check child fields
    if child_texts:
        for badge_name, child_attr in _DOMAIN_CHILD_MATCH_FIELDS:
            text = child_texts.get(child_attr, "")
            if text and term in text.lower():
                matched.append(badge_name)
    return matched


def compute_domain_match_fields_map(entities, search, child_texts_map=None):
    """Build dict entity_id → match_fields."""
    if not search:
        return {}
    result = {}
    for entity in entities:
        child_texts = child_texts_map.get(entity.id) if child_texts_map else None
        result[entity.id] = compute_domain_match_fields(entity, search, child_texts)
    return result
```

#### 1.3 Build child text map (if entity has child records)

```python
def _build_child_texts_map(session, entity_ids: List[int]) -> Dict[int, Dict[str, str]]:
    """Build entity_id → {field_name: concatenated_texts} for child records."""
    if not entity_ids:
        return {}
    rows = session.exec(
        select(ChildEntity.parent_id, ChildEntity.field_a, ChildEntity.field_b)
        .where(ChildEntity.parent_id.in_(entity_ids))
    ).all()
    result = {}
    for parent_id, field_a, field_b in rows:
        if parent_id not in result:
            result[parent_id] = {"field_a": "", "field_b": ""}
        if field_a:
            result[parent_id]["field_a"] += " " + field_a
        if field_b:
            result[parent_id]["field_b"] += " " + field_b
    return result
```

#### 1.4 Update the SQL search clause

In the list function, add ALL fields + child EXISTS subquery:

```python
if search:
    search_pattern = f"%{search}%"
    conditions.append(
        or_(
            Entity.field1.ilike(search_pattern),
            Entity.field2.ilike(search_pattern),
            # ... all fields ...
            # Child records search via EXISTS:
            exists().where(
                (ChildEntity.parent_id == Entity.id)
                & or_(
                    ChildEntity.field_a.ilike(search_pattern),
                    ChildEntity.field_b.ilike(search_pattern),
                )
            ),
        )
    )
```

#### 1.5 Implement exclude_fields logic

In the list function, after building the query but before pagination:

```python
# Exclusion par champ
if exclude_fields and search:
    all_entities = session.exec(query).all()
    all_ids = [e.id for e in all_entities]
    child_texts_map = _build_child_texts_map(session, all_ids) if all_ids else {}
    mf_map_all = compute_domain_match_fields_map(all_entities, search, child_texts_map)
    exclude_set = set(exclude_fields)
    filtered = [
        e for e in all_entities
        if not mf_map_all.get(e.id)
        or any(f not in exclude_set for f in mf_map_all[e.id])
    ]
    total = len(filtered)
    entities = filtered[skip:skip + limit]
    match_fields_map = {e.id: mf_map_all.get(e.id) for e in entities}
else:
    total = session.exec(count_query).one()
    entities = session.exec(query.offset(skip).limit(limit)).all()
    entity_ids = [e.id for e in entities]
    child_texts_map = _build_child_texts_map(session, entity_ids) if (search and entity_ids) else {}
    match_fields_map = compute_domain_match_fields_map(entities, search, child_texts_map)
```

**Critical invariant**: The exclusion filter keeps rows where `any(f not in exclude_set for f in match_fields[id])`. Rows with NO match_fields (empty list or not in map) are always kept. This ensures clicking "Modèle" doesn't remove entities that also matched via "Fournisseur".

#### 1.6 Add `match_fields` to the output schema

In `app/schemas.py`:
```python
class EntityOut(BaseModel):
    # ... existing fields ...
    match_fields: Optional[List[str]] = None
```

#### 1.7 Add `exclude_fields` to the route

In `app/api/routes/<domain>.py`:
```python
exclude_fields: Optional[str] = Query(None, description="Champs à exclure (csv: field1,field2)"),

# Parse:
parsed_exclude_fields = None
if exclude_fields:
    parsed_exclude_fields = [f.strip() for f in exclude_fields.split(",") if f.strip()]
```

Return match_fields for each entity:
```python
entity_out.match_fields = match_fields_map.get(entity.id)
```

### Phase 2 — Frontend

#### 2.1 Prerequisites

The page must already use:
- `TableToolbar` component for the filter bar
- `AppDataTable` for the table
- `HighlightText` component (for highlighting matched terms)

#### 2.2 Add state and constants

```javascript
// Labels for badge display — must match badge names from backend _DOMAIN_MATCH_FIELDS
const FIELD_LABELS = {
  field1: 'Label Humain 1',
  field2: 'Label Humain 2',
  child_field1: 'Label Enfant 1',
  // ... all badge names from backend
};

// Inside the component:
const [excludedFields, setExcludedFields] = useState(new Set());

// Detect which fields matched on the current page
const detectedFields = useMemo(() => {
  if (!filters.search) return [];
  const fieldsSet = new Set();
  for (const entity of entities) {  // entities = current page data
    if (entity.match_fields) {
      for (const f of entity.match_fields) {
        fieldsSet.add(f);
      }
    }
  }
  // Sort by priority: most specific/important fields first
  const priority = ['field1', 'child_field1', 'field2', ...];
  return [...fieldsSet].sort((a, b) => {
    const aIdx = priority.indexOf(a);
    const bIdx = priority.indexOf(b);
    return (aIdx === -1 ? 99 : aIdx) - (bIdx === -1 ? 99 : bIdx);
  });
}, [entities, filters.search]);
```

#### 2.3 Send exclude_fields to API

In the data loading function:
```javascript
const params = {
  limit: rowsPerPage,
  offset: first,
  ...(filters.search && { search: filters.search }),
  ...(excludedFields.size > 0 && { exclude_fields: [...excludedFields].join(',') }),
};
```

Add `excludedFields` to the useEffect dependency array that triggers reloading.

#### 2.4 Render badges via TableToolbar extra prop

```jsx
<TableToolbar
  filters={filters}
  onFilterChange={handleFilterChange}
  onReset={handleResetFilters}
  config={[
    { key: 'search', type: 'search', placeholder: 'Rechercher (champ1, champ2, enfant...)' },
    // ... other filters
  ]}
  extra={
    detectedFields.length > 0 && (
      <div className="flex items-center gap-1.5 flex-wrap">
        <span className="text-[10px] text-gray-400 uppercase tracking-wide font-medium">
          Trouvé dans :
        </span>
        {detectedFields.map(field => {
          const isExcluded = excludedFields.has(field);
          return (
            <button
              key={field}
              onClick={() => {
                setExcludedFields(prev => {
                  const next = new Set(prev);
                  next.has(field) ? next.delete(field) : next.add(field);
                  return next;
                });
                setPage(1);
              }}
              className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium border transition-all cursor-pointer ${
                isExcluded
                  ? 'bg-gray-100 text-gray-400 border-gray-200 line-through opacity-60 hover:opacity-80'
                  : 'bg-indigo-50 text-indigo-700 border-indigo-200 hover:bg-indigo-100'
              }`}
              title={isExcluded
                ? `Réactiver « ${FIELD_LABELS[field]} »`
                : `Exclure les résultats via « ${FIELD_LABELS[field]} »`
              }
            >
              {FIELD_LABELS[field] || field}
              <X className={`w-3 h-3 ${isExcluded ? '' : 'opacity-50'}`} />
            </button>
          );
        })}
        {excludedFields.size > 0 && (
          <button
            onClick={() => { setExcludedFields(new Set()); setPage(1); }}
            className="text-[11px] text-gray-500 hover:text-indigo-600 underline ml-1"
          >
            Tout réactiver
          </button>
        )}
      </div>
    )
  }
/>
```

**Imports needed**: `X` icon from `lucide-react`, `useMemo` from React.

#### 2.5 Clear excludedFields on reset

In the reset handler:
```javascript
const handleResetFilters = () => {
  setFilters({ search: '', ... });
  setExcludedFields(new Set());
  setPage(1);
};
```

#### 2.6 Optional: highlight matched text in cells

Use `HighlightText` for cells showing matched content:
```jsx
import HighlightText from '../components/ui/HighlightText';

const cellTemplate = (rowData) => {
  const mf = rowData.match_fields || [];
  const highlight = filters.search && mf.includes('field_name') && !excludedFields.has('field_name');
  return (
    <span>
      {highlight
        ? <HighlightText text={rowData.field_name} term={filters.search} />
        : rowData.field_name
      }
    </span>
  );
};
```

#### 2.7 Remove per-column filters

- Set all columns to `filterable: false` or remove the `filterable` property.
- If the page used `useColumnFilters` and `ColumnFilterInput`, remove them entirely (imports, state, params, useEffect deps).
- Remove `column_filters` from API params.

### Phase 3 — Verification

1. **Frontend build**: `cd frontend && npm run build`
2. **Python syntax**: `python -c "import ast; ast.parse(open('app/crud.py').read())"`
3. **Docker rebuild**: `make build && make up`
4. **Manual test**:
   - Search for a term that appears in multiple fields → see multiple badges
   - Search for a child entity field → see child-field badge
   - Click a badge to exclude → results update, pagination stays correct
   - Entity matched via multiple fields stays when only one is excluded
   - Click "Tout réactiver" → all badges back, all results restored
   - Empty search → no badges shown

## Implementation References

- **Assets page** (complete implementation): `frontend/src/pages/AssetsPage.jsx` + `app/crud.py::list_assets` + `app/api/routes/assets.py`
- **Orders page** (complete implementation): `frontend/src/pages/OrdersPage.jsx` + `app/crud.py::list_orders` + `app/api/routes/orders.py`
- **HighlightText**: `frontend/src/components/ui/HighlightText.jsx`
- **TableToolbar**: `frontend/src/components/ui/TableToolbar.jsx`

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Exclusion is server-side, not client-side | Client-side filtering breaks server-side pagination (totalRecords becomes wrong). The server knows the full result set. |
| Fetch ALL matches when exclude_fields is active | To correctly repaginate after Python-side filtering, we must know all matches. The count query alone can't express the "any match_field not excluded" logic. |
| Rows with no match_fields are always kept | If a row matched the search but no specific field was identified, excluding fields shouldn't hide it. |
| `exclude_fields` is a comma-separated query param | Simpler than repeated `?exclude_fields=a&exclude_fields=b`, works well with URL sharing. |
| Child fields are concatenated into a single text map | Avoids N+1 queries per entity during match_field computation. One batch query loads all children. |

## Anti-Patterns

- **Client-side filtering for exclusion**: creates a pagination mismatch — `filteredAssets.length + offset` is not the real total.
- **Incomplete field list**: if a field appears in the SQL WHERE but not in `_MATCH_FIELDS`, the term matches but no badge shows → confusing UX.
- **Mismatched badge names**: the badge name in Python (`_MATCH_FIELDS` first element) must match exactly the key in `FIELD_LABELS` on the frontend.
- **Forgetting to update the route**: adding `match_fields` to the schema but not setting it in the route handler → badges never appear.
- **excludedFields not in useEffect deps**: search works but exclusion doesn't trigger a reload.

## Optional Extension: "Select All Filtered" for Batch Operations

When a page uses server-side pagination, users can only interact with rows on the current page. This section documents how to add **"select all items matching the active filters"** and apply batch operations (status change, delete, etc.).

### When to Add

- Users need to modify/delete multiple items at once
- The list has actions that apply naturally in batch (status change, reassign, delete)
- Admin users need efficiency beyond per-row actions

### Architecture

```
┌─ Frontend ─────────────────────────────────────────────────────┐
│  Checkbox column (admin only)                                   │
│  └─ Page-level selection → "Select all X filtered" link        │
│     └─ selectAllMode: tracks deselectedIds (not selectedIds)   │
│        └─ Batch action bar (status change, delete...)          │
│           └─ POST /orders/bulk-update (filter params or IDs)   │
│              └─ Backend: resolve target IDs from filters       │
│                 └─ Apply UPDATE/DELETE in single SQL stmt      │
└────────────────────────────────────────────────────────────────┘
```

### Phase 1 — Backend: Bulk operation schemas

In `app/schemas.py`:

```python
class DomainBulkUpdateIn(BaseModel):
    order_ids: Optional[List[int]] = None        # explicit IDs
    select_all: bool = False                      # apply to all filtered
    exclude_order_ids: Optional[List[int]] = None  # IDs to exclude
    # Filters (used if select_all=True)
    search: Optional[str] = None
    year: Optional[int] = None
    status: Optional[str] = None
    # Fields to modify
    set_status: Optional[str] = None
    set_budget_line_id: Optional[int] = None

class DomainBulkDeleteIn(BaseModel):
    order_ids: Optional[List[int]] = None
    select_all: bool = False
    exclude_order_ids: Optional[List[int]] = None
    # ... filter fields ...

class OrderBulkOperationResult(BaseModel):
    success_count: int = 0
    error_count: int = 0
    errors: List[str] = []
```

### Phase 2 — Backend: CRUD helpers

In `app/crud.py`, extract filter logic into a reusable function and add:

```python
def list_domain_ids_by_filters(session, search, year, ...) -> List[int]:
    """Return all matching IDs (no pagination)."""
    conditions = _build_domain_filter_conditions(...)
    return session.exec(select(Domain.id).where(*conditions)).all()

def bulk_update_domains(session, order_ids=None, select_all=False,
                         exclude_order_ids=None, set_status=None, ...) -> int:
    if order_ids:
        target_ids = order_ids
    elif select_all:
        target_ids = list_domain_ids_by_filters(...)
    # Filter out deselected IDs
    if exclude_order_ids:
        target_ids = [id for id in target_ids if id not in set(exclude_order_ids)]
    if not target_ids:
        return 0
    stmt = update(Domain).where(Domain.id.in_(target_ids)).values(...)
    result = session.exec(stmt)
    session.commit()
    return result.rowcount
```

**Key invariant**: `exclude_order_ids` handles items the user explicitly unchecked after "select all". The backend filters them out before the operation.

### Phase 3 — Backend: Route endpoints

In `app/api/routes/<domain>.py`:

```python
@router.post("/bulk-update", response_model=OrderBulkOperationResult)
def bulk_update(payload: DomainBulkUpdateIn, ...):
    try:
        count = crud.bulk_update_domains(session, ...)
        return OrderBulkOperationResult(success_count=count)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
```

### Phase 4 — Frontend: API methods

In `frontend/src/services/api.js`:

```javascript
bulkUpdate: async (data) => {
  const response = await api.post('/domain/bulk-update', data);
  return response.data;
},
bulkDelete: async (data) => {
  const response = await api.post('/domain/bulk-delete', data);
  return response.data;
},
```

### Phase 5 — Frontend: Selection state + handlers

```javascript
// State
const [selectedItems, setSelectedItems] = useState([]);
const [selectAllMode, setSelectAllMode] = useState(false);
const [deselectedIds, setDeselectedIds] = useState(new Set());

// Effective count
const effectiveSelectedCount = selectAllMode
  ? Math.max(0, totalRecords - deselectedIds.size)
  : selectedItems.length;

// Build payload — IDs or filter params
const buildBulkPayload = (extra = {}) => {
  if (selectAllMode) {
    return {
      select_all: true,
      search: filters.search || undefined,
      year: filters.year || undefined,
      // ... other filters ...
      exclude_order_ids: deselectedIds.size > 0 ? [...deselectedIds] : undefined,
      ...extra,
    };
  }
  return { order_ids: selectedItems.map(o => o.id), ...extra };
};

// Selection handler — page-level or deselection tracking
const handleSelectionChange = (e) => {
  const value = e.value || [];
  if (selectAllMode) {
    const newDeselected = new Set(deselectedIds);
    const currentPageIds = new Set(items.map(o => o.id));
    const checkedIds = new Set(value.map(o => o.id));
    for (const id of currentPageIds) {
      checkedIds.has(id) ? newDeselected.delete(id) : newDeselected.add(id);
    }
    setDeselectedIds(newDeselected);
  } else {
    setSelectedItems(value);
  }
};
```

### Phase 6 — Frontend: DataTable + batch bar

Add checkbox column (admin only):
```jsx
<AppDataTable
  selection={isAdmin ? selectedItems : undefined}
  onSelectionChange={isAdmin ? handleSelectionChange : undefined}
  ...
>
  {isAdmin && <Column selectionMode="multiple" headerStyle={{ width: '3rem' }} />}
```

Add batch action bar (shown when selection is active):
```jsx
{isAdmin && (selectedItems.length > 0 || selectAllMode) && (
  <div className="batch-action-bar">
    <span>{effectiveSelectedCount} sélectionné(s)</span>
    {!selectAllMode && totalRecords > rowsPerPage && (
      <button onClick={() => { setSelectAllMode(true); setDeselectedIds(new Set()); }}>
        Sélectionner les {totalRecords} résultats filtrés
      </button>
    )}
    <button onClick={handleBulkAction}>Appliquer</button>
    <button onClick={clearSelection}>Désélectionner</button>
  </div>
)}
```

### Phase 7 — Verification

1. Frontend build: `cd frontend && npm run build`
2. Python syntax check on all modified files
3. Manual tests:
   - Check a few checkboxes → batch bar appears with count
   - Click "Select all X filtered" → shows all selected, deselection hint
   - Navigate to another page → checkboxes reflect select-all state
   - Uncheck an item → excluded (count decreases)
   - Apply batch status change → all filtered updated
   - Apply batch delete → confirmation, all filtered deleted
   - Non-admin: no checkboxes, no batch bar

### Implementation Reference

- **Orders page** (selection + budget line assignment + bulk delete):
  - Frontend: `frontend/src/pages/OrdersPage.jsx` — checkbox column, select-all banner, budget line dialog, bulk delete
  - Backend CRUD: `app/crud.py::bulk_update_orders` / `bulk_delete_orders`
  - Backend routes: `app/api/routes/orders.py::POST /orders/bulk-update` / `POST /orders/bulk-delete`
- **Assets page** (selection + status change):
  - Frontend: `frontend/src/pages/AssetsPage.jsx` — checkbox column, select-all banner, status dialog
  - Backend CRUD: `app/crud.py::bulk_update_assets`
  - Backend routes: `app/api/routes/assets.py::POST /assets/bulk-update`
- **Schemas**: `app/schemas.py::OrderBulkUpdateIn` / `OrderBulkDeleteIn` / `AssetBulkUpdateIn` / `OrderBulkOperationResult`

### Conventions for New Pages

When adding this pattern to a new page:
1. **Batch operations that modify status should be avoided** if status is computed automatically (e.g., order status derived from item receipt). Prefer operations that assign metadata (budget line, site, category, etc.).
2. **Use `canWrite()` or `isAdmin`** to gate the checkbox column — never show checkboxes to users who can't act on them.
3. **Match the existing bulk operation schema pattern**: `DomainBulkUpdateIn` with `ids` + `select_all` + filter params + `set_*` fields.
4. **Backend CRUD functions** should accept both `ids` (explicit) and `select_all` + filter params, and support `exclude_*_ids` for deselection after "select all".
5. **Always clear selection** on page change, filter change, sort change, and after successful batch operations.
