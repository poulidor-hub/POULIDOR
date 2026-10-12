# Guide Développement Template — HUB POULIDOR

> Référence centrale pour créer, développer et maintenir une application HUB basée sur le template `HUBapp_TEMPLATE_base`.
> Ce guide complète les documentations déjà présentes dans le template — il ne les duplique pas, il les référence.
>
> Dernière synchronisation : 13/10/2026 — template `2.30.1`, Hub `3.71.4`.

---

## Table des matières

1. [Architecture et flux](#1-architecture-et-flux)
2. [Cycle de vie d'une app](#2-cycle-de-vie-dune-app)
3. [Conventions backend](#3-conventions-backend)
4. [Base de données](#4-base-de-données)
5. [Ajouter une feature de A à Z](#5-ajouter-une-feature-de-a-à-z)
6. [`.env` de référence](#6-env-de-référence)
7. [Makefile de référence](#7-makefile-de-référence)
8. [Tests](#8-tests)
9. [Déploiement et HTTPS](#9-déploiement-et-https)
10. [Dépannage développement](#10-dépannage-développement)
11. [Annexes](#11-annexes)

---

## 1. Architecture et flux

### Composants

```
┌──────────────────────────────────────────────────────┐
│  HUB POULIDOR (HUB_base/)                            │
│  • Auth (JWT, OIDC)  • Registre apps  • Messages     │
│  • Ports allocation  • M2M discovery  • Backups       │
└──────────┬───────────────────────────┬───────────────┘
           │ M2M (JWT client_credentials)
           │ SSE (notifications)
           ▼
┌──────────────────────────────────────────────────────┐
│  Application (template HUBapp_TEMPLATE_base)          │
│                                                       │
│  ┌─────────┐    ┌──────────┐    ┌──────────────────┐ │
│  │ nginx   │◄───│ React    │    │  PostgreSQL:15   │ │
│  │ :80/443 │    │ Vite+HMR │    │  • items          │ │
│  │ proxy   │    │ HUBCSS   │    │  • user_prefs     │ │
│  │ /api/→be│    │ TanStack │    │  • uploads        │ │
│  │ /hub/→H │    │ Query v5 │    │  • outbox_msgs    │ │
│  └────┬────┘    └──────────┘    │  • schema_migrat. │ │
│       │                         └────────▲─────────┘ │
│       ▼                                   │           │
│  ┌────────────────────────────────────────┘           │
│  │ FastAPI (uvicorn)                                  │
│  │ • JWT validation (via Hub)                         │
│  │ • Role-based access (admin/manager/user/viewer)    │
│  │ • M2M client (discovery + call)                    │
│  │ • Outbox (messages inter-apps)                     │
│  │ • StorageManager (uploads)                         │
│  │ • Backup/Restore endpoints                         │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

### Flux d'une requête authentifiée

```
1. Navigateur → GET /api/items
2. nginx → proxy_pass http://backend:8000/api/items
3. FastAPI → dépendance get_current_user()
4. hub_auth.decode_jwt() → valide token avec JWKS du Hub
5. Si valide → injecte user dans la route
6. Route → requête SQLAlchemy async → PostgreSQL
7. Réponse JSON → nginx → navigateur
```

### Flux M2M (machine-to-machine)

```
1. App émettrice → POST /api/apps/token (client_credentials)
2. Hub → vérifie credentials → émet JWT service account
3. App émettrice → GET /api/apps/discover (avec JWT SA)
4. App cible → retourne son catalogue M2M
5. App émettrice → POST /api/apps/call/{slug}/{endpoint}
```

### Cycle SSE (Server-Sent Events)

```
1. Frontend → new EventSource('/hub/api/stream?token=JWT')
   ⚠️ EventSource ne supporte pas les headers HTTP → token en query string obligatoire
2. nginx → proxy /hub/ vers le Hub (proxy_buffering off)
3. Le Hub pousse les notifications en temps réel
4. Refresh proactif du token : 2 min avant expiration (TTL 8 h par défaut)
```

### Pattern Outbox

```
1. Route métier → crée un OutboxMessage(status='pending')
2. Service outbox (tâche périodique) → tente livraison via Hub M2M
3. Succès → status='sent' | Échec → status='failed' (retry plus tard)
```

---

## 2. Cycle de vie d'une app

### 2.1 Scaffold — Du template à l'app

```bash
# Depuis la racine du méta-repo POULIDOR
scripts/create_app.sh mon-app

# Ce que fait le script :
# 1. Valide le slug (regex ^[a-z][a-z0-9_-]*$)
# 2. Refuse si APPS/mon-app existe déjà
# 3. Vérifie que le submodule HUBapp_TEMPLATE_base est initialisé
# 4. Copie le template vers APPS/mon-app (sans .git)
# 5. Injecte les overrides de chemins dans .env
```

**Prérequis** : le submodule doit être initialisé.
```bash
git submodule update --init HUBapp_TEMPLATE_base
```

### 2.2 INITIALISE — Personnalisation

```bash
cd APPS/mon-app
python INITIALISE.py --clean        # Mode standard (sans contenu de démo)
# ou python INITIALISE.py --demo    # Garder la démo pour explorer
# ou python INITIALISE.py "Mon App" --demo   # Mode auto : nom en argument positionnel
python INITIALISE.py --profile client.json --yes   # Non-interactif (scripts/CI)
```

| Mode | Usage |
|------|-------|
| `--clean` (défaut) | Supprime modèles/routes/composants de démo → squelette minimal |
| `--demo` | Conserve `Item`, `TestData`, composants de test → exploration |
| `--profile fic.json` | Mode non-interactif : lit les infos depuis une fiche client JSON |
| `"Mon App"` (positionnel) | Mode auto : nom de l'app en argument positionnel, sans questions |
| `--yes` | Non-interactif : confirme automatiquement (requis si stdin fermé — scripts/CI) |

**Ce que fait INITIALISE (14 étapes) :**

| Étape | Fichier | Action |
|-------|---------|--------|
| 1 | `.env` | Créé depuis `.env.example`, `APP_VERSION=0.0.1` |
| 2 | `.env.example` | Valeurs par défaut personnalisées |
| 3 | `docker-compose.yml` | Slug, ports, hub host injectés |
| 4 | `backend/config.py` | Settings Pydantic mis à jour |
| 5 | `Dockerfile.frontend` | ARGs `VITE_*` des ports |
| 6 | `frontend/index.html` | `<title>` personnalisé |
| 7 | `frontend/Header.jsx` | `<h1>` personnalisé |
| 8 | `frontend/package.json` | `name` + `version=0.0.1` |
| 9 | `frontend/src/config.js` | APP_SLUG |
| 10 | Fixtures de test | `conftest.py`, `test_m2m.py` |
| 11 | `VERSION` | → `0.0.1` |
| 12 | Documentation | `CHANGELOG.md` + `README.md` vierges |
| 13 | Nettoyage obsolètes | `frontend/config.js` vestige |
| 14 | `LICENSE.md` | Propriétaire client ou générique |

**Après INITIALISE :**
- `ACTIONS/` conserve les scripts d'action : `INITIALISE` x3 OS (`LINUX/INITIALISE.sh`, `PYTHON/INITIALISE.py`, `WINDOWS/INITIALISE.bat`) plus les outils `allocate_ports.py` (fallback allocation locale), `check_image_freshness.py` et `sync_hub_host.py`
- Les fichiers `INITIALISE.*` racine sont auto-supprimés
- L'app est prête à être lancée

### 2.3 Allocation des ports

```bash
make sync-env    # Appelé automatiquement par make dev / make up
```

- Si `API_PORT`/`FRONTEND_PORT` sont vides dans `.env` → le Hub alloue dynamiquement
- Idempotent : même slug + même host = mêmes ports à chaque appel
- `FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1` (automatique)

### 2.4 Premier boot

```bash
make dev          # Démarrage avec hot-reload (recommandé en développement)
# ou
make up           # Démarrage production (sans hot-reload)

make health       # Vérification GET /api/health (retry 5×, 2s intervalle)
make logs-api     # Surveiller le démarrage ("Application startup complete")
```

**Signatures d'échec au boot :**

| Log | Cause | Solution |
|-----|-------|----------|
| `bind: address already in use` | Collision port | Changer `API_PORT`/`FRONTEND_PORT` dans `.env` |
| `psycopg.OperationalError` | PostgreSQL pas prêt | `make logs-db`, vérifier `POSTGRES_*` |
| `relation "..." does not exist` | Migration non exécutée | Vérifier `backend/migrations/` |
| `ImportError` | Dépendance manquante | Ajouter à `backend/requirements.txt`, rebuild |
| `Pydantic ValidationError` | Schéma/modèle mismatch | Réconcilier `models.py` et `schemas.py` |
| `RuntimeError: Hub auth ...` | `HUB_*` manquant | Vérifier `.env`, `HUB_HOST` joignable |

### 2.5 Développement quotidien

```bash
make dev          # Lance tout (backend + frontend + postgres) avec hot-reload
                  # Backend : --reload (uvicorn), DEBUG=true
                  # Frontend : Vite HMR sur port 3000

make restart-api  # Redémarre uniquement le backend (plus rapide qu'un rebuild complet)
make logs         # Logs de tous les services
make logs-api     # Logs backend uniquement
make logs-db      # Logs PostgreSQL
```

**Hot-reload** : les modifications dans `backend/` et `frontend/src/` sont détectées automatiquement. Pas besoin de rebuild.

**Rebuild nécessaire** quand on modifie :
- `backend/requirements.txt` (nouvelles dépendances Python)
- `frontend/package.json` (nouvelles dépendances npm)
- `Dockerfile.backend` ou `Dockerfile.frontend`
- Variables `ARG` dans les Dockerfiles

```bash
make down && make dev   # Rebuild complet
```

### 2.6 Release et versionnage

```bash
# Bump de version
make bump-patch    # 1.2.3 → 1.2.4 (bugfix)
make bump-minor    # 1.2.3 → 1.3.0 (nouvelle feature)
make bump-major    # 1.2.3 → 2.0.0 (breaking change)
```

Le script `scripts/bump_version.py` synchronise automatiquement :
- `VERSION`
- `frontend/package.json`
- `backend/main.py`
- `.env.example`
- `.env`
- `docs/API.md`

Un hook Git pre-commit (`scripts/git-hooks/pre-commit`) assure la cohérence.

**Pour le push vers `main`** : toujours passer par le skill `release-on-main` (bump + CHANGELOG obligatoires).

---

## 3. Conventions backend

### 3.1 Structure obligatoire

```
backend/
├── main.py              # Application FastAPI, lifespan, inclusion des routeurs
├── config.py            # Settings Pydantic (lecture .env)
├── models.py            # Modèles SQLAlchemy (TOUTES les tables)
├── schemas.py           # Schémas Pydantic (request/response)
├── database.py          # Engine async, session, runner de migrations
├── hub_client.py        # Client Hub (M2M auth, enregistrement, messages, synchro heure)
├── hub_auth.py          # Dépendances FastAPI (get_current_user, require_role)
├── hub_transfert.py     # Client Hub Transfert — fichiers, OPT-IN (HUB_TRANSFERT_ENABLED=true)
├── storage.py           # StorageManager (uploads)
├── outbox.py            # Service outbox (messages inter-apps)
├── m2m_catalog.py       # Catalogue M2M (auto-introspection)
├── cert_sync.py         # Re-synchro périodique des certificats PKI du Hub (HTTPS)
├── logging_config.py    # Logging horodaté à l'heure du Hub (cf. §3.7)
├── entrypoint.sh        # Boot conteneur : répare les permissions volumes puis gosu (non-root)
├── pytest.ini           # Config pytest (asyncio_mode=auto, testpaths)
├── utils.py             # Utilitaires
├── routes/              # Routeurs FastAPI (un fichier par domaine)
│   ├── items.py         # Exemple : CRUD items (pagination)
│   ├── preferences.py   # Préférences utilisateur
│   ├── m2m.py           # M2M et découverte services
│   ├── hub_data.py      # Découverte de données pour le Hub (M2M : lecture table/colonne)
│   ├── backup.py        # Backup/Restore (ZIP en streaming disque)
│   ├── docs.py          # Documentation et changelog servis par l'API
│   ├── test_data.py     # Données de démo/test partagées (backup/restore)
│   └── tests.py         # Diagnostic services (GET /api/tests/services)
├── migrations/          # Migrations SQL (NNN_description.sql)
└── tests/               # Tests pytest (§8)
```

### 3.2 Routeur FastAPI — Pattern standard

```python
# backend/routes/mon_domaine.py
# ⚠️ Imports ABSOLUS (l'application tourne depuis backend/, pas de paquet parent) :
from fastapi import APIRouter, Depends, HTTPException, status
from database import get_db
from hub_auth import get_current_user, require_role
from models import MonItem
from schemas import MonItemCreate, MonItemResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/api/mon-domaine", tags=["Mon Domaine"])

@router.get("/", response_model=list[MonItemResponse])
async def list_items(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Liste tous les items (tout utilisateur authentifié)."""
    ...

@router.post("/", response_model=MonItemResponse, status_code=201)
async def create_item(
    data: MonItemCreate,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_role("user")),
):
    """Crée un item (rôle user minimum)."""
    ...

@router.delete("/{item_id}", status_code=204)
async def delete_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_role("manager")),
):
    """Supprime un item (rôle manager minimum)."""
    ...
```

### 3.3 Dépendances d'authentification

| Dépendance | Accès requis |
|-----------|-------------|
| `get_current_user()` | N'importe quel token JWT valide (user, service account) |
| `require_role("viewer")` | Au moins viewer |
| `require_role("user")` | Au moins user |
| `require_role("manager")` | Au moins manager |
| `require_role("admin")` | Admin uniquement |
| `get_service_account()` | Token service account (M2M) |

### 3.4 Gestion d'erreurs

```python
from fastapi import HTTPException, status

# Pattern standard :
if not item:
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Item non trouvé"
    )

if item.owner_id != current_user.user_id:
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Vous n'êtes pas propriétaire de cet item"
    )
```

### 3.5 Dates et timezone (OBLIGATOIRE)

| Contexte | Règle | ❌ Interdit |
|----------|-------|------------|
| Modèle SQLAlchemy | `Column(DateTime(timezone=True))` | `DateTime` sans `timezone=True` |
| Migration SQL | Type `TIMESTAMPTZ` | `TIMESTAMP` |
| Docker PostgreSQL | `TZ=UTC` | Autre timezone |
| Code Python | `datetime.now(timezone.utc)` | `datetime.utcnow()` |

```python
# ✅ Correct
from datetime import datetime, timezone
created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

# ❌ Incorrect
created_at = Column(DateTime, default=datetime.utcnow)
```

### 3.6 JWT et SSE — Contraintes

- **SSE via `EventSource`** : le token JWT DOIT être passé en query string (`?token=...`) car `EventSource` ne supporte pas les headers HTTP personnalisés.
- **Refresh proactif** : côté frontend, rafraîchir le token 2 minutes avant son expiration (TTL par défaut : **8 h** — `ACCESS_TOKEN_EXPIRE_MINUTES=480`, défaut déploiement LAN).
- **`ExpiredSignatureError`** : ne JAMAIS avaler cette exception dans `hub_auth._try_decode()`. Elle doit remonter pour que le frontend puisse déclencher un refresh.

### 3.7 Logging

```python
import logging
logger = logging.getLogger(__name__)

logger.info("Opération réussie pour l'utilisateur %s", user_id)
logger.warning("Tentative d'accès non autorisé à la ressource %s", resource_id)
logger.error("Échec de connexion au Hub: %s", exc, exc_info=True)
```

Utiliser le logging structuré (pas de `print()`). Les logs sont visibles via `make logs-api`.

#### Horodatage à l'heure du Hub (parc)

Tous les logs backend du parc (hub, apps, socle) sont horodatés en
**ISO 8601 UTC** à l'**heure du Hub** — autorité temps du parc, pour une
timeline cohérente entre toutes les machines :

```
2026-10-04T12:34:56.789Z | INFO     | app.hub_client | 🔄 Connexion au Hub...
```

- **Mécanique** : module `logging_config` (template : `backend/`,
  socle : `hub_socle/`, hub : `hub/app/`). `HubClock` maintient un offset
  (heure hub − heure locale) synchronisé via `GET /api/system/time`
  (`epoch_ms`, endpoint public) au point médian request/réponse ;
  `hub_client.sync_hub_time()` est appelé au boot après register puis
  périodiquement (`HUB_TIME_SYNC_INTERVAL`, défaut 300 s).
- **Fallback** : hub injoignable → dernier offset conservé ; jamais
  synchronisé → heure locale UTC (conforme règle 10, `datetime.now(timezone.utc)`).
- **Config** (`/.env`) : `LOG_LEVEL=INFO` (niveau applicatif),
  `HUB_TIME_SYNC_INTERVAL=300`.
- **Apps sur socle** : `create_app()` configure le logging par défaut ;
  opt-out avec `create_app(setup_logging=False)` (puis
  `hub_socle.logging_config.setup_logging()` manuellement).
- Les access logs uvicorn portent le même format (loggers reconfigurés
  au boot). Ne pas re-appeler `logging.basicConfig()` : ça casserait
  l'horodatage hub.

---

## 4. Base de données

### 4.1 Migrations SQL

**Convention** : `backend/migrations/NNN_description.sql` (3 chiffres, incrémental).

```sql
-- backend/migrations/003_ajout_colonne_priorite.sql
BEGIN;
    ALTER TABLE items ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 0;
COMMIT;
```

**Exécution** : le runner dans `backend/database.py` :
- Lit tous les fichiers `migrations/*.sql` triés par nom
- Exécute ceux dont le préfixe n'est pas dans la table `schema_migrations`
- Chaque statement est wrappé dans un savepoint → rollback granular en cas d'erreur
- Enregistre le préfixe dans `schema_migrations` après succès

### 4.2 Créer une nouvelle table

**1. Modèle SQLAlchemy** (`backend/models.py`) :

```python
class MonEntite(Base):
    __tablename__ = "mon_entite"

    id = Column(Integer, primary_key=True, index=True)
    nom = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    proprietaire_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), onupdate=lambda: datetime.now(timezone.utc))
```

**2. Migration SQL** (`backend/migrations/NNN_create_mon_entite.sql`) :

```sql
BEGIN;
    CREATE TABLE IF NOT EXISTS mon_entite (
        id SERIAL PRIMARY KEY,
        nom VARCHAR(255) NOT NULL,
        description TEXT,
        proprietaire_id INTEGER NOT NULL REFERENCES users(id),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ
    );
    CREATE INDEX IF NOT EXISTS idx_mon_entite_proprietaire ON mon_entite(proprietaire_id);
COMMIT;
```

**3. Vérifier** : redémarrer l'app (`make restart-api`) et vérifier les logs.

### 4.3 Accès async SQLAlchemy

⚠️ **La session s'obtient par injection de dépendance** (`Depends(get_db)`) — ne jamais
faire `async with get_db() as db:` (c'est un async generator : ce pattern a causé un bug
réel, corrigé en 2.26.4 → 2.27.0).

```python
from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from database import get_db

@router.get("/mon-entite")
async def list_entites(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(MonEntite).where(MonEntite.proprietaire_id == current_user.user_id)
    )
    return result.scalars().all()
```

### 4.4 Accès direct PostgreSQL

```bash
make db-shell     # shell psql interactif dans le conteneur
```

```sql
\dt               -- Lister les tables
\d mon_entite     -- Décrire une table
SELECT * FROM schema_migrations;  -- Voir les migrations exécutées
```

---

## 5. Ajouter une feature de A à Z

Ce fil rouge illustre le processus complet pour ajouter une feature typique : un CRUD « Projets ».

### Étape 1 — Modèle SQLAlchemy (`backend/models.py`)

```python
class Projet(Base):
    __tablename__ = "projets"

    id = Column(Integer, primary_key=True, index=True)
    titre = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    est_archive = Column(Boolean, default=False)
    proprietaire_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), onupdate=lambda: datetime.now(timezone.utc))
```

### Étape 2 — Schéma Pydantic (`backend/schemas.py`)

```python
class ProjetCreate(BaseModel):
    titre: str = Field(..., min_length=1, max_length=255)
    description: str | None = None

class ProjetUpdate(BaseModel):
    titre: str | None = None
    description: str | None = None
    est_archive: bool | None = None

class ProjetResponse(BaseModel):
    id: int
    titre: str
    description: str | None
    est_archive: bool
    proprietaire_id: int
    created_at: datetime
    updated_at: datetime | None

    model_config = ConfigDict(from_attributes=True)
```

### Étape 3 — Migration SQL (`backend/migrations/004_create_projets.sql`)

```sql
BEGIN;
    CREATE TABLE IF NOT EXISTS projets (
        id SERIAL PRIMARY KEY,
        titre VARCHAR(255) NOT NULL,
        description TEXT,
        est_archive BOOLEAN NOT NULL DEFAULT FALSE,
        proprietaire_id INTEGER NOT NULL REFERENCES users(id),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ
    );
    CREATE INDEX IF NOT EXISTS idx_projets_proprietaire ON projets(proprietaire_id);
COMMIT;
```

### Étape 4 — Routeur (`backend/routes/projets.py`)

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from database import get_db
from hub_auth import get_current_user, require_role
from models import Projet
from schemas import ProjetCreate, ProjetUpdate, ProjetResponse

router = APIRouter(prefix="/api/projets", tags=["Projets"])

@router.get("/", response_model=list[ProjetResponse])
async def list_projets(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(Projet)
        .where(Projet.proprietaire_id == current_user.user_id)
        .order_by(Projet.created_at.desc())
    )
    return result.scalars().all()

@router.post("/", response_model=ProjetResponse, status_code=201)
async def create_projet(
    data: ProjetCreate,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_role("user")),
):
    projet = Projet(
        titre=data.titre,
        description=data.description,
        proprietaire_id=current_user.user_id,
    )
    db.add(projet)
    await db.commit()
    await db.refresh(projet)
    return projet

@router.put("/{projet_id}", response_model=ProjetResponse)
async def update_projet(
    projet_id: int,
    data: ProjetUpdate,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_role("user")),
):
    result = await db.execute(
        select(Projet).where(Projet.id == projet_id)
    )
    projet = result.scalar_one_or_none()
    if not projet:
        raise HTTPException(status_code=404, detail="Projet non trouvé")
    if projet.proprietaire_id != current_user.user_id:
        raise HTTPException(status_code=403, detail="Non autorisé")

    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(projet, key, value)

    await db.commit()
    await db.refresh(projet)
    return projet

@router.delete("/{projet_id}", status_code=204)
async def delete_projet(
    projet_id: int,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_role("manager")),
):
    result = await db.execute(
        select(Projet).where(Projet.id == projet_id)
    )
    projet = result.scalar_one_or_none()
    if not projet:
        raise HTTPException(status_code=404, detail="Projet non trouvé")

    await db.delete(projet)
    await db.commit()
```

### Étape 5 — Enregistrer le routeur (`backend/main.py`)

Imports absolus, même convention que les routeurs existants :

```python
from routes.projets import router as projets_router
app.include_router(projets_router)
```

### Étape 6 — Test backend (`backend/tests/test_projets.py`)

Fixtures prêtes dans `conftest.py` : `client` (anonyme), `authenticated_client`
(rôle user), `admin_client`, `viewer_client`, `m2m_client` — cf. §8.2.
`asyncio_mode = auto` est actif (`pytest.ini`) ; le marqueur `@pytest.mark.asyncio`
reste accepté pour la lisibilité.

```python
from httpx import AsyncClient


async def test_create_projet_requires_auth(client: AsyncClient):
    """La création requiert une authentification."""
    response = await client.post(
        "/api/projets/",
        json={"titre": "Projet Test", "description": "Un projet"},
    )
    assert response.status_code == 401


async def test_create_projet_success(authenticated_client: AsyncClient):
    response = await authenticated_client.post(
        "/api/projets/",
        json={"titre": "Projet Test", "description": "Un projet"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["titre"] == "Projet Test"
```

### Étape 7 — Hooks TanStack Query (`frontend/src/hooks/useProjets.js`)

Signatures actuelles : options en **objet unique**, hooks séparés
`useApiQuery.js` / `useApiMutation.js`.

```javascript
import { useApiQuery } from './useApiQuery';
import { useApiMutation } from './useApiMutation';

const PROJETS_KEY = ['projets'];

export function useProjets() {
  return useApiQuery({
    queryKey: PROJETS_KEY,
    endpoint: '/api/projets/',
  });
}

export function useCreateProjet() {
  return useApiMutation({
    endpoint: '/api/projets/',
    method: 'POST',
    invalidateKeys: [PROJETS_KEY],
  });
}

export function useDeleteProjet() {
  return useApiMutation({
    endpoint: ({ id }) => `/api/projets/${id}`,
    method: 'DELETE',
    invalidateKeys: [PROJETS_KEY],
  });
}
```

> `useApiMutation` gère aussi les **mises à jour optimistes** (norme du projet :
> `optimisticUpdate` / `optimisticUpdates` avec rollback automatique en cas
> d'erreur — cf. `docs/DATA_FETCHING.md`).

**Référence** : `docs/DATA_FETCHING.md` pour les patterns TanStack Query obligatoires.

### Étape 8 — Composant React (`frontend/src/components/ProjetList.jsx`)

Depuis la phase CSS-first (template 2.30.0), la structure canonique d'une page est
`PageHeader → toolbar unique → hub-panel`, avec les classes `hub-*` du seed HUBCSS
(zéro CSS ad hoc). Les 4 règles : un seul bouton retour, une seule toolbar, une
modal n'est pas une page, pas de carte dans carte.

```jsx
import PageHeader from './PageHeader';
import { useProjets, useCreateProjet, useDeleteProjet } from '../hooks/useProjets';

export default function ProjetList() {
  const { data: projets, isLoading, error } = useProjets();
  const createProjet = useCreateProjet();
  const deleteProjet = useDeleteProjet();

  return (
    <>
      <PageHeader
        title="Projets"
        badge={projets?.length}
        actions={
          <button
            type="button"
            className="hub-button"
            onClick={() => createProjet.mutate({ titre: 'Nouveau projet' })}
            disabled={createProjet.isPending}
          >
            + Nouveau
          </button>
        }
      />
      <div className="hub-panel">
        {isLoading && <p>Chargement…</p>}
        {error && <p className="help-text">Erreur : {error.message}</p>}
        <table className="hub-table hub-table--striped">
          <tbody>
            {projets?.map((p) => (
              <tr key={p.id}>
                <td>{p.titre}</td>
                <td>
                  <button
                    type="button"
                    className="hub-icon-button"
                    title="Supprimer"
                    onClick={() => deleteProjet.mutate({ id: p.id })}
                  >
                    🗑
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
```

**Références** : `HUBCSS/docs/HOW2USE.md` (classes & tokens), `frontend/README.md`
(recette de page canonique + directive de consommation HUBCSS), et
`components/ExampleList.jsx` dans le template (exemple complet de référence).

### Étape 9 — Vérification

```bash
make test                         # Tests backend
make health                       # Vérifier que l'API répond
make lint-classes                 # Classes HUBCSS du frontend (aucune classe fantôme)
# Puis dans le navigateur : accéder à la nouvelle page
```

---

## 6. `.env` de référence

### Variables obligatoires

| Variable | Description | Exemple |
|----------|-------------|---------|
| `APP_SLUG` | Identifiant unique de l'app | `mon-app` |
| `APP_NAME` | Nom affiché | `Mon Application` |
| `HUB_HOST` | IP ou hostname du Hub | `192.0.2.11` |
| `HUB_API_PORT` | Port API du Hub | `8000` |
| `POSTGRES_HOST` | Nom du service PostgreSQL (Docker) | `mon-app-postgres` |
| `POSTGRES_USER` | Utilisateur PostgreSQL | `app_user` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `app_password` |
| `POSTGRES_DB` | Nom de la base | `app_db` |

### Variables optionnelles

| Variable | Défaut | Description |
|----------|--------|-------------|
| `API_PORT` | *(alloué par le Hub)* | Port backend. Laisser vide = allocation automatique |
| `FRONTEND_PORT` | *(alloué par le Hub)* | Port frontend. Laisser vide = allocation automatique |
| `FRONTEND_HTTPS_PORT` | `FRONTEND_PORT + 1` | Port HTTPS (généré automatiquement) |
| `APP_HOST` | *(auto-détecté)* | IP de l'app. Auto-détecté si même serveur que le Hub |
| `HUB_INTERNAL_HOST` | *(vide)* | Host interne Docker vers le Hub (utile si réseau Docker custom) |
| `HUB_FRONTEND_PORT` | `80` | Port frontend du Hub |
| `APP_VERSION` | *(synchro depuis VERSION)* | Version actuelle |
| `APP_DESCRIPTION` | *(vide)* | Description de l'app |
| `DEBUG` | `false` | Mode debug (true en dev) |
| `HTTPS_ENABLED` | `true` | HTTPS activé par défaut (2.23.7) — `false` pour du HTTP explicite |
| `ENABLE_DEMO_ENDPOINTS` | `false` | Activer les endpoints de démo |
| `IS_SHARED` | `false` | App accessible en M2M par les autres apps |
| `LOG_LEVEL` | `INFO` | Niveau de log applicatif (logging horodaté Hub, cf. §3.7) |
| `HUB_TIME_SYNC_INTERVAL` | `300` | Période (s) de resynchro de l'heure Hub (fallback : heure locale UTC) |
| `HUB_INSTANCE_ID` | *(mémorisé par sync-env)* | Identité du Hub alloueur — garde anti-croisement (2.19.0) |
| `APP_SUBNET` | *(alloué par le Hub)* | Sous-réseau Docker de l'app (CIDR), pris du pool `APP_SUBNET_POOL` du Hub lors de `make up`/`make build` |
| `POSTGRES_PORT` | `5432` | Port PostgreSQL alloué dynamiquement par le Hub (depuis 2.18.2), propagé à l'API et au conteneur postgres |

### Interdépendances

- `FRONTEND_HTTPS_PORT` = `FRONTEND_PORT + 1` (calculé par `sync-env`, ne pas modifier manuellement)
- `APP_VERSION` est synchronisé depuis `VERSION` par `sync-env`
- `POSTGRES_HOST` dans `.env` doit correspondre au `container_name` du service postgres dans `docker-compose.yml`
- Si l'app et le Hub sont sur la même machine, `APP_HOST` est auto-détecté par `entrypoint.sh` au démarrage

### Features template récentes

- **Structure canonique CSS-first** (2.30.0-2.30.1) : `components/PageHeader.jsx` + `ExampleList.jsx` (remplace `DataTable.jsx`, supprimé), purge du CSS ad hoc de `app.css` → classes `hub-*` du seed HUBCSS (0.3.0) ; directive de consommation dans `frontend/README.md` ; rebranding INITIALISE robuste (échec explicite si motif absent).
- **Skill `data-generate`** (2.29.0) : données de test sans données réelles — synthétiques ou anonymisation `exemple-app` obligatoire avant tout usage de données réelles.
- **Logging horodaté à l'heure du Hub** (2.29.3) : cf. §3.7.
- **Gardes `sync_hub_host`** (2.28.1, 2.29.1) : l'IP du Hub annoncée n'est adoptée que si joignable (garde legacy + fallback IP LAN) ; cible `make sync-hub-host`.
- **Entrypoint non-root auto-réparant** (2.28.3) : `entrypoint.sh` démarre root, répare le propriétaire des volumes (`chown -R 1000:1000`) puis bascule `gosu` (uid 1000) — un volume créé par root ne bloque plus l'app (fix incident prod `PermissionError`/readonly).
- **Allocation ports avec fallback local** (2.28.0) : `ACTIONS/PYTHON/allocate_ports.py` — hubs legacy sans `POST /api/apps/allocate-ports` : ports figés conservés + subnet local.
- **Audit socle P0/P1** (2.27.0-2.27.1) : fetch JWKS asynchrone (le Hub lent ne gèle plus l'event loop), backup/restore en streaming (RAM bornée), +36 tests.
- **Backup ZIP en streaming disque** (2.25.0) : fin des OOM au-delà de ~150 Mo de données ; `mem_limit` api 512M → 1G, nginx `client_max_body_size` 50M → 1G.
- **MCP hub off par défaut** (2.26.4) : le serveur MCP `hub` (~63 outils) est désactivé par défaut dans `opencode.json` ; bascule à la demande via les commandes opencode `/hub-on` / `/hub-off`.
- **HTTPS par défaut** (2.23.7 / 2.26.0) : `HTTPS_ENABLED=true` dans `.env.example` et Settings — génération auto des certificats au premier `make up` ; opt-out explicite `HTTPS_ENABLED=false`.
- **Tests parallèles** (2.24.0) : `make test` en pytest-xdist (`-n auto`, variable `XDIST_WORKERS`) ; `make test-seq` pour le séquentiel (debug flaky).
- **Ports dynamiques `POSTGRES_PORT`** (2.18.2) : le port PostgreSQL est alloué par le Hub (défaut `5432`) et propagé à l'API et au conteneur — idem `APP_SUBNET` pour le sous-réseau Docker.
- **`VITE_APP_SLUG`** (2.17.0) : injecté dans le frontend ; l'URL SSE porte `&app=<slug>` (présence utilisateur par app côté Hub, HUB ≥ 3.36.0).
- **Re-sync automatique des certificats** (2.12.0) : `backend/cert_sync.py` — boucle de fond démarrée au lancement, resynchronise les certificats PKI du Hub toutes les 6 h ; no-op si `HTTPS_ENABLED=false`.
- **Garde `HUB_INSTANCE_ID`** (2.19.0) : `sync-env` mémorise l'identité du Hub dans `.env` et refuse un `.env` pointant vers un autre Hub (protection contre les allocations croisées).
- **Fusion `.env` après montée de template** (2.20.0) : `scripts/update_env.py` + cible `make update-env` — ajoute au `.env` existant les nouvelles clés du `.env.example` sans jamais toucher aux valeurs existantes ni aux clés propres à l'app ; sauvegarde horodatée (`.env.pre-update-<stamp>`) et rapport détaillé. À lancer après chaque montée de template (le skill `migrate-app-template` l'orchestre — étape B.0).
- **Restore robuste** (2.20.5 → 2.20.8) : tri topologique des tables + SAVEPOINT, cycles de FK (`session_replication_role=replica`), resync des séquences avec pré-checks — un restore de backup ne rollback plus en cascade (validé terrain sur exemple-app).
- **Verrou inter-onglets sur le refresh token** (2.21.0) : Web Locks API (`hub-token-refresh`) — un seul onglet rotate, le rival adopte le token ; synchronisation via événement `storage`. Complémentaire de la grâce 60 s côté Hub (3.50.0).
- **Self-healing M2M sur Hub legacy** (2.21.1) : si le ré-enregistrement trusted ne retourne pas de secret (Hubs pré-H9), fallback `POST /api/apps/me/regenerate-secret` — plus de déconnexion Hub après perte de credentials sur un Hub legacy.

---

## 7. Makefile de référence

### Développement

| Cible | Commande Docker | Usage |
|-------|----------------|-------|
| `make dev` | `docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d && docker compose logs -f` | Lancement hot-reload avec logs en direct |
| `make up-dev` | `docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d` | Lancement hot-reload en arrière-plan |
| `make build` | `docker compose build` | Build des images production |
| `make up` | `docker compose up -d` (overlay `docker-compose.https.yml` si HTTPS activé) | Démarre en prod (sync-env préalable, HTTPS si activé) |
| `make down` | `docker compose down` | Arrêt des services |
| `make down-dev` | `docker compose -f docker-compose.yml -f docker-compose.dev.yml down` | Arrêt des services dev |
| `make restart` | `docker compose restart` | Redémarrage de tous les services |
| `make restart-api` | `docker compose restart api` | Redémarrage backend uniquement |
| `make restart-frontend` | `docker compose restart frontend` | Redémarrage frontend uniquement |

### Diagnostic

| Cible | Usage |
|-------|-------|
| `make help` | Affiche l'aide (toutes les cibles documentées) |
| `make logs` | Logs de tous les services (`-f`) |
| `make logs-api` | Logs backend uniquement |
| `make logs-db` | Logs PostgreSQL uniquement |
| `make health` | `curl /api/health` (retry 5×, 2s intervalle) |
| `make health-detailed` | Health check détaillé |
| `make version` | Affiche la version actuelle (`cat VERSION`) |
| `docker compose ps` | Statut des conteneurs |

### Tests

| Cible | Usage |
|-------|-------|
| `make test` | Tests pytest sur l'hôte (SQLite mémoire, **parallèles** via pytest-xdist `-n auto`) |
| `make test-seq` | Tests séquentiels (debug flaky / ordre-dépendant) |
| `make test-cov` | Tests avec couverture HTML |
| `make test-docker` | Tests dans le conteneur API |
| `make test-docker-cov` | Tests + couverture dans le conteneur API |

### Qualité UI (HUBCSS)

| Cible | Usage |
|-------|-------|
| `make lint-classes` | Détecte les classes fantômes (JSX vs build HUBCSS — voir `HUBCSS/docs/CASCADE.md`) |
| `make verify-ui` | Smoke UI par styles calculés (Playwright) — `make verify-ui APP=../MON_APP/frontend` |

### Base de données

| Cible | Usage |
|-------|-------|
| `make db-shell` | Shell psql interactif dans le conteneur PostgreSQL |

### Version et release

| Cible | Usage |
|-------|-------|
| `make bump-patch` | `bump_version.py patch` (1.2.3 → 1.2.4) |
| `make bump-minor` | `bump_version.py minor` (1.2.3 → 1.3.0) |
| `make bump-major` | `bump_version.py major` (1.2.3 → 2.0.0) |

### Maintenance

| Cible | Usage |
|-------|-------|
| `make clean` | Supprime conteneurs, volumes, caches Python |
| `make clean-all` | Nettoyage complet (+ images Docker) |
| `make ssl` | Génère certificats SSL auto-signés |
| `make sync-env` | Alloue les ports via le Hub + synchronise `FRONTEND_HTTPS_PORT` et `APP_VERSION` |
| `make sync-hub-host` | Synchronise l'IP du Hub (découverte auto, gardes legacy/LAN ; `make sync-hub-host HUB_HOST=x.x.x.x`) |
| `make update-env` | Fusionne les nouvelles clés du `.env.example` dans le `.env` (après montée de template ; valeurs existantes préservées) |
| `make ai-index` | Régénère `AI_INDEX.md` |
| `make refresh-design-seed` | Copie HUBCSS dist → `frontend/public/design-system/current` |
| `make sync-hub-tooling` | Synchronise `hub_mcp/` + plugin OpenCode |
| `make sync-hub-tooling-check` | Vérifie que la copie `hub_mcp` + plugin est synchro avec les sources (CI) |
| `make init` | ⚠️ Déprécié — utiliser les scripts `INITIALISE` (cf. §2.2) |

---

## 8. Tests

### 8.1 Structure

```
backend/tests/
├── conftest.py                  # Fixtures partagées (§8.2)
├── test_auth.py                 # Authentification
├── test_auth_tagging.py         # Tagging __auth_level__ des closures d'auth
├── test_backup.py               # Backup/Restore
├── test_backup_restore_order.py # Ordre de restore (tri topologique, savepoints)
├── test_backup_streaming.py     # Streaming backup/restore (RAM bornée)
├── test_cert_sync.py            # Re-synchro périodique des certificats PKI
├── test_config_env.py           # Tolérance aux variables Hub vides (settings)
├── test_hub_auth_async.py       # JWKS fetch async (hub_auth hors event loop)
├── test_hub_client_binary.py    # Transferts binaires via le Hub
├── test_hub_client_depends.py   # Dépendances FastAPI liées au Hub
├── test_hub_client_register_version.py # Ré-enregistrement au changement de version
├── test_hub_client_selfheal.py  # Auto-récupération des credentials M2M
├── test_hub_data.py             # Routes /api/hub/data (découverte de données Hub)
├── test_hub_depends.py          # Résolution du fichier depends.yaml
├── test_hub_transfert.py        # Client Hub Transfert (opt-in)
├── test_items.py                # CRUD Items (démo)
├── test_logging_config.py       # Logging horodaté heure Hub (§3.7)
├── test_m2m.py                  # M2M communication
├── test_m2m_catalog.py          # Catalogue M2M
├── test_migrations.py           # Runner de migrations SQL
├── test_outbox.py               # Pattern outbox
├── test_outbox_recovery.py      # Recovery outbox
├── test_preferences.py          # Préférences utilisateur
├── test_services.py             # Tests services Hub
├── test_socle_2232_alignment.py # Alignement template ↔ HUBsocle 2.23.2
├── test_storage_security.py     # Sécurité StorageManager (anti-traversée)
└── test_sync_hub_host.py        # Gardes + fallback sync_hub_host
```

### 8.2 Fixtures essentielles (`conftest.py`)

La base de tests est une app FastAPI avec DB SQLite en mémoire et Hub **mocké**
(`mock_hub_client`, `mock_hub_auth` + helper `create_mock_token`) :

| Fixture | Rôle |
|---------|------|
| `settings` | Settings de l'app (`get_settings()`) |
| `db_session` | Session SQLAlchemy async (SQLite mémoire) |
| `app_with_db` | App FastAPI avec session DB injectée (`dependency_overrides[get_db]`) |
| `client` | Client HTTP `httpx.AsyncClient` **non authentifié** |
| `authenticated_client` | Client authentifié, rôle `user` |
| `admin_client` | Client authentifié, rôle `admin` |
| `viewer_client` | Client authentifié, rôle `viewer` |
| `mock_m2m_token` / `m2m_client` | Token service account + client M2M |

### 8.3 Tester les routes protégées

```python
async def test_admin_endpoint_requires_admin(viewer_client):
    """Un viewer ne peut pas accéder à un endpoint admin."""
    response = await viewer_client.get("/api/admin/stats")
    assert response.status_code == 403
```

### 8.4 Tester le M2M

Les tests M2M (`test_m2m.py`) utilisent des mocks du Hub pour simuler :
- La découverte de services
- Les appels inter-apps
- La validation de tokens service account

### 8.5 Exécution

```bash
make test              # Tests parallèles (SQLite mémoire, sur l'hôte, xdist -n auto)
make test-seq          # Séquentiel — debug flaky / ordre-dépendant
make test-docker       # Tests dans le conteneur (PostgreSQL)
make test-cov          # Avec couverture (rapport HTML dans htmlcov/)
```

### 8.6 Convention

- Un fichier de test par domaine (`test_projets.py` pour les routes `projets.py`)
- Nom des fonctions : `test_<action>_<contexte>_<resultat_attendu>`
- Chaque test est indépendant (pas de dépendance entre tests) — obligatoire avec xdist
- `asyncio_mode = auto` (`pytest.ini`) : les tests async n'exigent pas de marqueur ;
  `@pytest.mark.asyncio` reste accepté (ne PAS utiliser `@pytest.mark.anyio`)

---

## 9. Déploiement et HTTPS

> **Références détaillées** :
> - `HUBapp_TEMPLATE_base/docs/REMOTE_APPS.md` — déploiement même serveur ou distant
> - `HUBapp_TEMPLATE_base/docs/HTTPS.md` — configuration SSL, certificats, proxy Hub

### 9.1 Résumé

| Étape | Commande/action |
|-------|----------------|
| Configurer `.env` | Définir `HUB_HOST`, laisser `API_PORT`/`FRONTEND_PORT` vides |
| Allouer les ports | `make sync-env` (appel au Hub) |
| Démarrer | `make up` (production) ou `make dev` (développement) |
| HTTPS | Actif **par défaut** (2.23.7) — certificats auto-signés générés au premier démarrage ; désactivation : `HTTPS_ENABLED=false` |

### 9.2 Déploiement distant

Si l'app est sur un serveur différent du Hub :
- Définir `APP_HOST` avec l'IP publique du serveur applicatif
- Le Hub doit whitelister cette IP
- Voir `HUBapp_TEMPLATE_base/docs/REMOTE_APPS.md` pour la procédure complète

### 9.3 HTTPS en développement

HTTPS est activé par défaut : `make dev` / `make up` génèrent automatiquement les
certificats auto-signés (`scripts/generate-ssl.sh`, couvre localhost + IP locale)
puis chargent `docker-compose.https.yml` (port HTTPS = `FRONTEND_PORT + 1`).

```bash
make ssl               # (Re)générer les certificats manuellement
make dev               # Démarre avec HTTPS sur FRONTEND_HTTPS_PORT

# Opt-out HTTP explicite (à mettre dans .env) :
HTTPS_ENABLED=false
```

---

## 10. Dépannage développement

### Erreurs au démarrage

| Symptôme | Cause probable | Solution |
|----------|---------------|----------|
| `bind: address already in use` | Port déjà utilisé | `lsof -i :<port>` puis changer dans `.env` |
| `psycopg.OperationalError` | PostgreSQL pas prêt | `make logs-db`, vérifier `POSTGRES_*` |
| `relation "xxx" does not exist` | Migration manquante | Créer et exécuter la migration (`backend/migrations/`) |
| `ImportError: No module named 'xxx'` | Dépendance manquante | `pip install xxx` + mettre dans `requirements.txt` + rebuild |
| `Pydantic ValidationError` | Schéma incohérent avec le modèle | Réconcilier `models.py` et `schemas.py` |
| `RuntimeError: Hub auth failed` | Hub injoignable ou credentials invalides | Vérifier `HUB_HOST`, `HUB_API_PORT`, Hub en ligne |

### Erreurs en développement

| Symptôme | Cause probable | Solution |
|----------|---------------|----------|
| Hot-reload ne détecte pas les changements | Fichier hors du volume monté | Vérifier `docker-compose.dev.yml` (volumes) |
| `401 Unauthorized` sur toutes les routes | Token expiré | Se reconnecter (`/api/auth/login`) |
| `403 Forbidden` | Rôle insuffisant | Vérifier le rôle dans `require_role()` |
| CORS errors dans le navigateur | `APP_HOST` mal configuré | Vérifier l'auto-détection dans `entrypoint.sh` |
| Modifications frontend invisibles | Cache navigateur | Hard refresh (Ctrl+Shift+R), vider le cache |
| `EventSource` failed | Token SSE expiré | Implémenter le refresh proactif (2 min avant expiration) |

### Erreurs Base de données

| Symptôme | Cause probable | Solution |
|----------|---------------|----------|
| `schema_migrations` manquante | Première migration non exécutée | Le runner crée la table automatiquement au premier run |
| Migration déjà appliquée qui échoue | Ajout manuel dans `schema_migrations` | Supprimer l'entrée, corriger la migration, redémarrer |
| `ForeignKey` violation | Ordre des migrations incorrect | Les tables référencées doivent exister avant les FK |

### Logs et diagnostic

```bash
make logs-api       # Logs backend (erreurs, démarrage, requêtes)
make logs-db        # Logs PostgreSQL
make health         # Vérifier que l'API répond
make db-shell       # Inspecter la base directement

# Dans le conteneur API :
docker compose exec api bash
python -c "from backend.database import engine; print('OK')"
```

---

## 11. Annexes

### A. Tableau de correspondance

| J'ai besoin de… | Voir |
|----------------|------|
| Comprendre l'architecture | [§1 Architecture et flux](#1-architecture-et-flux) |
| Créer une nouvelle app | [§2.1 Scaffold](#21-scaffold--du-template-à-lapp) |
| Initialiser une app après scaffold | [§2.2 INITIALISE](#22-initialise--personnalisation) |
| Lancer l'app pour la première fois | [§2.4 Premier boot](#24-premier-boot) |
| Connaître les règles de code backend | [§3 Conventions backend](#3-conventions-backend) |
| Créer une table en base | [§4.2 Créer une nouvelle table](#42-créer-une-nouvelle-table) |
| Ajouter une feature complète | [§5 Ajouter une feature de A à Z](#5-ajouter-une-feature-de-a-à-z) |
| Comprendre une variable `.env` | [§6 .env de référence](#6-env-de-référence) |
| Trouver la bonne commande make | [§7 Makefile de référence](#7-makefile-de-référence) |
| Écrire des tests | [§8 Tests](#8-tests) |
| Déployer en production | [§9 Déploiement et HTTPS](#9-déploiement-et-https) |
| Résoudre une erreur | [§10 Dépannage développement](#10-dépannage-développement) |
| Référence API REST | `HUBapp_TEMPLATE_base/docs/API.md` |
| Design system HUBCSS (classes, tokens, perfs) | `HUBCSS/docs/HOW2USE.md` + `HUBCSS/docs/PERFORMANCE.md` |
| Data fetching frontend (TanStack Query) | `HUBapp_TEMPLATE_base/docs/DATA_FETCHING.md` |
| Notifications et messages Hub | `HUBapp_TEMPLATE_base/docs/HUB_MESSAGES.md` |
| Backup et restore | `HUBapp_TEMPLATE_base/docs/BACKUP_RESTORE.md` |
| Déploiement distant | `HUBapp_TEMPLATE_base/docs/REMOTE_APPS.md` |
| HTTPS et certificats | `HUBapp_TEMPLATE_base/docs/HTTPS.md` |
| Migrations SQL (détail) | `HUBapp_TEMPLATE_base/.github/instructions/migrations-sql.instructions.md` |
| Créer une app (skill IA) | `.opencode/skills/create-hub-app/SKILL.md` |

### B. Référence croisée des docs existantes

| Document | Lignes* | Contenu |
|----------|--------|---------|
| `HUBapp_TEMPLATE_base/README.md` | 590 | Onboarding, endpoints, tests, versionnage, backup, place dans le parc |
| `HUBapp_TEMPLATE_base/docs/API.md` | 1116 | Référence exhaustive de tous les endpoints |
| `HUBapp_TEMPLATE_base/docs/DATA_FETCHING.md` | 421 | Patterns TanStack Query obligatoires |
| `HUBapp_TEMPLATE_base/docs/HUB_MESSAGES.md` | 584 | Intégration notifications et messages |
| `HUBapp_TEMPLATE_base/docs/BACKUP_RESTORE.md` | 481 | Backup/restore générique |
| `HUBapp_TEMPLATE_base/docs/REMOTE_APPS.md` | 227 | Déploiement distant |
| `HUBapp_TEMPLATE_base/docs/HTTPS.md` | 207 | Configuration SSL/HTTPS (défaut activé) |
| `HUBapp_TEMPLATE_base/docs/MIGRATION_M2M_CANARY.md` | 60 | Activation M2M renforcé |
| `HUBapp_TEMPLATE_base/docs/client-profile.example.json` | 31 | Exemple fiche client |

\* Nombres de lignes indicatifs (template 2.30.1) — à re-vérifier avant de s'y fier.

### C. Commandes rapides

```bash
# --- Cycle quotidien ---
make dev               # Démarrer en mode développement
make logs              # Voir les logs
make restart-api       # Redémarrer le backend après modif

# --- Base de données ---
make db-shell          # Accès psql interactif
make test              # Lancer les tests

# --- Diagnostic ---
make health            # Vérifier que l'API répond
make version           # Voir la version actuelle
docker compose ps      # Statut des conteneurs

# --- Release ---
make bump-patch        # Bump version patch
make bump-minor        # Bump version minor
make bump-major        # Bump version major

# --- Nettoyage ---
make down              # Arrêter les services
make clean             # Nettoyer conteneurs + volumes
make clean-all         # Nettoyage complet (+ images)

# --- SSL ---
make ssl               # Générer certificats auto-signés
```
