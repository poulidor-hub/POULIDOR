---
name: migrate-app-template
description: Use when a Hub app was created with an older version of HUBapp_TEMPLATE_base and needs to be updated to the current template version. Triggers on "mettre à jour l'app avec le template", "migrer l'app vers le nouveau template", "mon app est en retard sur le template", "upgrade template app", "sync app with template", or when you notice an app's VERSION is far behind the template's VERSION (2.8.0). Also use when adding template features (M2M, notifications SSE, backup/restore, bulk operations, badge search) to an app that lacks them.
argument-hint: 'Path to the app to migrate (e.g., APPS/mon-app)'
---

# Migrate App Template

Workflow end-to-end pour auditer et mettre à jour une application existante créée avec une ancienne version de `HUBapp_TEMPLATE_base` vers le template canonique actuel. **Ne jamais écraser à l'aveugle** : chaque fichier du template est comparé, les modifications métier de l'app sont préservées, les ajouts du template sont fusionnés.

## Prérequis

Avant toute migration, vérifier :

1. **Le submodule `HUBapp_TEMPLATE_base` est à jour** :
   ```bash
   git submodule update --remote HUBapp_TEMPLATE_base
   ```
2. **L'app est dans un état git propre** (commit ou stash avant de commencer).
3. **L'app tourne OU peut être démarrée** — les vérifications se font en live sur Docker.
4. **Le Makefile de l'app est fonctionnel** (`make health` répond).

## Checklist

| Phase | Étape | Vérification |
|-------|-------|-------------|
| **A** | Audit — diff complet template vs app | Analyse catégorisée des écarts |
| **B** | Infrastructure — Docker, nginx, Makefile | `make build && make up && make health` |
| **C** | Backend core — config, auth, hub_client, outbox | `make test-docker` |
| **D** | Frontend core — package.json, vite, providers, hooks | Frontend accessible, pas d'erreur console |
| **E** | Features — M2M, notifications, backup, bulk, badges | Test feature-by-feature sur Docker |
| **F** | Tooling — skills `.opencode/`, MCP, scripts, docs | Skills chargeables, MCP fonctionnel |
| **G** | Vérification finale — cycle complet | `make test-docker-cov && make health` |

## Phase A — Audit

L'audit produit un rapport structuré des différences. Exécuter depuis la racine du méta-repo :

```bash
diff -rq HUBapp_TEMPLATE_base/ APPS/<slug>/ \
  --exclude='.git' --exclude='node_modules' --exclude='__pycache__' \
  --exclude='*.pyc' --exclude='package-lock.json' --exclude='dist' \
  --exclude='.env' --exclude='postgres_data' --exclude='uploads_data' \
  --exclude='ssl' --exclude='backups' --exclude='uploads' \
  --exclude='storage' --exclude='.superpowers'
```

Les résultats se classent en 4 catégories :

### A.1 — Fichiers template absents de l'app

Ce sont les fichiers que le template possède mais que l'app n'a pas (généralement parce qu'ils ont été supprimés par `INITIALISE --clean`, ou ajoutés dans une version plus récente du template).

**Critiques** (bloquent le fonctionnement) :
- `.opencode/skills/` — skills applicatifs (13 skills, dont `verify-feature`)
- `hub_mcp/` — serveur MCP
- `scripts/` — `bump_version.py`, hooks git

**Importants** (nouvelles features) :
- `backend/routes/hub_data.py` — endpoint config Hub
- `backend/routes/m2m.py` — découverte M2M
- `backend/outbox.py` — outbox messages Hub
- `backend/storage.py` — gestion uploads
- `backend/migrations/002_create_outbox.sql`
- `frontend/src/components/MessageBanner.jsx` — notifications SSE
- `frontend/src/components/MessageArchive.jsx` — archive messages
- `frontend/src/components/M2MTests.jsx` — tests M2M
- `frontend/src/components/EndpointTests.jsx` — tests endpoints
- `frontend/src/components/LoginPrompt.jsx` — écran login
- `frontend/src/context/AuthContext.jsx` — contexte auth
- `frontend/src/context/ConfigContext.jsx` — contexte config
- `frontend/src/hooks/useApiQuery.js` — hook query avec refresh token
- `frontend/src/hooks/useApiMutation.js` — hook mutation avec rollback
- `frontend/src/lib/queryClient.js` — QueryClient global
- `docs/HUB_MCP.md`

**Optionnels** (contenu démo, généralement nettoyé) :
- `backend/routes/items.py`, `backend/routes/test_data.py`
- `backend/tests/test_items.py`
- `frontend/src/components/DataTable.jsx`, `UserCard.jsx`, `TokenCard.jsx`
- `INITIALISE.{py,sh,bat}`, `ACTIONS/*/INITIALISE.*`

### A.2 — Fichiers modifiés (versions divergentes)

Le fichier existe des deux côtés mais le contenu diffère. Classer chaque diff en :

| Type de diff | Cause probable | Action |
|---|---|---|
| **INITIALISE** | Slug, nom, ports personnalisés par `INITIALISE.py` | Conserver la version app, porter les NOUVELLES sections du template |
| **Métier** | Code métier ajouté par le développeur (modèles, routes, composants) | Conserver intégralement, ne jamais écraser |
| **Template obsolète** | L'app a une ancienne version du code template (hooks, context, config) | Remplacer par la version template actuelle |
| **Mixte** | Fichier contenant à la fois du code template et du code métier | Fusion manuelle : nouveau template + code métier préservé |

Fichiers typiquement impactés par INITIALISE (slug/ports) :
- `backend/config.py`, `backend/main.py`, `backend/tests/conftest.py`
- `docker-compose.yml`, `docker-compose.dev.yml`
- `.env.example`
- `frontend/index.html`, `frontend/package.json`
- `frontend/src/components/Header.jsx`, `frontend/src/config.js`
- `VERSION`, `CHANGELOG.md`, `README.md`, `LICENSE.md`

Fichiers typiquement modifiés par le métier (préserver) :
- `backend/models.py`, `backend/schemas.py`
- `backend/routes/*.py` (sauf routes template)
- `frontend/src/App.jsx`, composants customs

Fichiers template qui ont évolué (remplacer) :
- `Dockerfile.backend`, `Dockerfile.frontend`, `Dockerfile.frontend.dev`
- `nginx.conf`, `nginx-ssl.conf`
- `frontend/vite.config.js`
- `frontend/src/main.jsx`, `frontend/src/config.js` (parties template)
- `frontend/src/styles/app.css`
- `Makefile`
- `backend/hub_client.py`, `backend/hub_auth.py`
- `backend/routes/tests.py` (template)

### A.3 — Fichiers ajoutés par l'app (absents du template)

Fichiers propres à l'app, les conserver tels quels. Exemples typiques :
- `ACTIONS/LINUX/{START,STOP,RESTART,...}.sh`
- `ACTIONS/PYTHON/{START,STOP,...}.py`
- `backend/routes/` — routes métier custom
- `backend/models.py` — modèles métier (partiellement)
- `backend/storage/`, `backups/`, `uploads/`
- `frontend/src/components/` — composants métier

### A.4 — Fichiers identiques

Aucune action nécessaire. Les lister pour confirmer l'alignement.

## Phase B — Infrastructure

Mettre à jour les fichiers Docker, nginx et Makefile. Ces fichiers sont **majoritairement template** (peu/pas de code métier), donc le remplacement est généralement sûr.

### B.1 — Fichiers à copier depuis le template (safe replace)

```bash
cp HUBapp_TEMPLATE_base/Dockerfile.backend    APPS/<slug>/Dockerfile.backend
cp HUBapp_TEMPLATE_base/Dockerfile.frontend   APPS/<slug>/Dockerfile.frontend
cp HUBapp_TEMPLATE_base/Dockerfile.frontend.dev APPS/<slug>/Dockerfile.frontend.dev
cp HUBapp_TEMPLATE_base/nginx.conf            APPS/<slug>/nginx.conf
cp HUBapp_TEMPLATE_base/nginx-ssl.conf        APPS/<slug>/nginx-ssl.conf
cp HUBapp_TEMPLATE_base/.dockerignore         APPS/<slug>/.dockerignore
cp HUBapp_TEMPLATE_base/opencode.json         APPS/<slug>/opencode.json
```

### B.2 — Makefile : comparer et fusionner

Le Makefile de l'app a été initialisé par INITIALISE mais le template a de nouvelles cibles (par exemple `sync-env`, `refresh-design-seed`, `sync-hub-tooling`, `test-docker-cov`).

**Méthode** : faire un diff ciblé, repérer les cibles qui manquent dans l'app et les ajouter manuellement. Les variables d'environnement (`APP_SLUG`, `API_PORT`, etc.) sont déjà bonnes dans l'app — ne pas les changer.

Nouvelles cibles template à vérifier :
- `sync-env` — allocation ports + synchro VERSION
- `refresh-design-seed` — MAJ HUBCSS
- `sync-hub-tooling` — MAJ hub_mcp + plugin
- `test-docker-cov` — tests avec couverture
- `ssl` — génération certificats
- `bump-patch / bump-minor / bump-major` — versionnement

### B.3 — docker-compose.yml : fusion ciblée

Le `docker-compose.yml` de l'app a les bons slugs/ports (INITIALISE). Comparer avec le template pour les ajouts structurels :

**Points à vérifier dans le template actuel (2.8.0)** :
- Présence du `healthcheck` sur chaque service (`postgres`, `api`, `frontend`)
- `extra_hosts: host.docker.internal:host-gateway` sur le service `api`
- `link: api:backend` sur le service `frontend` (pour nginx proxy)
- Volumes nommés `postgres_data` et `uploads_data`
- Réseau bridge `app-network`
- `FRONTEND_HTTPS_PORT` si le support HTTPS est présent

### B.4 — docker-compose.dev.yml : fusion ciblée

Vérifier que le fichier existe et qu'il est à jour. Points clés :
- Service `frontend-dev` avec `Dockerfile.frontend.dev`, port `3000`
- Volumes montés pour hot-reload (`./backend:/app/backend`, `./frontend/src:/app/src`)
- Variables `DEBUG=true`, `HUB_MCP_*`

### B.5 — Vérification infrastructure

```bash
cd APPS/<slug>
make build          # Rebuild les images avec les nouveaux Dockerfiles
make up             # Démarrage production
make health         # Doit répondre {"status":"healthy","version":"..."}
make logs-api       # Vérifier "Application startup complete"
```

**Si `make build` échoue** : vérifier que les Dockerfiles n'ont pas de variables manquantes héritées de l'ancien `.env`. Comparer `ARG` dans le nouveau Dockerfile avec le `.env` de l'app.

## Phase C — Backend core

### C.1 — Requirements

Comparer `backend/requirements.txt`. Le template 2.8.0 a potentiellement de nouvelles dépendances. Ajouter celles qui manquent :

```bash
diff HUBapp_TEMPLATE_base/backend/requirements.txt APPS/<slug>/backend/requirements.txt
```

Dépendances critiques du template 2.8.0 (vérifier présence) :
- `fastapi`, `uvicorn`, `sqlalchemy[asyncio]`, `asyncpg`, `psycopg2-binary`
- `pydantic`, `pydantic-settings`
- `httpx` (hub_client)
- `PyJWT`, `cryptography` (hub_auth)
- `python-multipart` (uploads)

### C.2 — Fichiers à copier depuis le template (safe replace)

Ces fichiers contiennent exclusivement du code template (pas de métier) :

```bash
cp HUBapp_TEMPLATE_base/backend/hub_client.py   APPS/<slug>/backend/hub_client.py
cp HUBapp_TEMPLATE_base/backend/hub_auth.py     APPS/<slug>/backend/hub_auth.py
cp HUBapp_TEMPLATE_base/backend/m2m_catalog.py  APPS/<slug>/backend/m2m_catalog.py
cp HUBapp_TEMPLATE_base/backend/outbox.py       APPS/<slug>/backend/outbox.py
cp HUBapp_TEMPLATE_base/backend/storage.py      APPS/<slug>/backend/storage.py
cp HUBapp_TEMPLATE_base/backend/utils.py        APPS/<slug>/backend/utils.py
cp HUBapp_TEMPLATE_base/backend/database.py     APPS/<slug>/backend/database.py
cp HUBapp_TEMPLATE_base/backend/entrypoint.sh   APPS/<slug>/backend/entrypoint.sh
cp HUBapp_TEMPLATE_base/backend/pytest.ini      APPS/<slug>/backend/pytest.ini
```

### C.3 — Fichiers à fusionner

**`backend/config.py`** — contient les Settings Pydantic. L'app a son slug/description (INITIALISE). Le template a potentiellement de nouveaux champs (ex: `hub_mcp_enabled`, `backup_enabled`). Procédure :

1. Diff les deux fichiers
2. Identifier les nouveaux champs dans le template
3. Les ajouter à la classe `Settings` de l'app
4. NE PAS changer les valeurs spécifiques à l'app (slug, ports, etc.)

**`backend/main.py`** — l'app a ses routes métier montées. Le template a de nouvelles routes et middlewares. Procédure :

1. Diff les deux fichiers
2. Repérer les nouveaux imports et `app.include_router()` dans le template
3. Les ajouter au `main.py` de l'app
4. NE PAS retirer les routes métier existantes

Routes template à vérifier :
```python
from backend.routes import m2m, preferences, backup, hub_data, tests as test_routes
app.include_router(m2m.router)
app.include_router(preferences.router)
app.include_router(backup.router)
app.include_router(hub_data.router)
app.include_router(test_routes.router)
```

**`backend/models.py`** — préserver les modèles métier, ajouter les nouveaux modèles template :
- `OutboxMessage` — table pour l'outbox
- `UserPreference` — préférences utilisateur
- `UploadedFile` — métadonnées fichiers uploadés

**`backend/schemas.py`** — même logique : schémas métier préservés, nouveaux schémas template ajoutés.

### C.4 — Nouvelles routes template

Copier les routes template manquantes :
```bash
cp HUBapp_TEMPLATE_base/backend/routes/m2m.py         APPS/<slug>/backend/routes/m2m.py
cp HUBapp_TEMPLATE_base/backend/routes/preferences.py APPS/<slug>/backend/routes/preferences.py
cp HUBapp_TEMPLATE_base/backend/routes/backup.py      APPS/<slug>/backend/routes/backup.py
cp HUBapp_TEMPLATE_base/backend/routes/hub_data.py    APPS/<slug>/backend/routes/hub_data.py
cp HUBapp_TEMPLATE_base/backend/routes/tests.py       APPS/<slug>/backend/routes/tests.py
cp HUBapp_TEMPLATE_base/backend/routes/docs.py        APPS/<slug>/backend/routes/docs.py
```

### C.5 — Migrations SQL

Copier les migrations template manquantes dans `backend/migrations/`. Ne pas supprimer les migrations existantes de l'app.

### C.6 — Tests backend

Copier les tests template manquants :
```bash
cp HUBapp_TEMPLATE_base/backend/tests/test_auth.py        APPS/<slug>/backend/tests/test_auth.py
cp HUBapp_TEMPLATE_base/backend/tests/test_auth_tagging.py APPS/<slug>/backend/tests/test_auth_tagging.py
cp HUBapp_TEMPLATE_base/backend/tests/test_backup.py      APPS/<slug>/backend/tests/test_backup.py
cp HUBapp_TEMPLATE_base/backend/tests/test_hub_client_depends.py APPS/<slug>/backend/tests/test_hub_client_depends.py
cp HUBapp_TEMPLATE_base/backend/tests/test_m2m_catalog.py APPS/<slug>/backend/tests/test_m2m_catalog.py
cp HUBapp_TEMPLATE_base/backend/tests/test_outbox.py      APPS/<slug>/backend/tests/test_outbox.py
cp HUBapp_TEMPLATE_base/backend/tests/test_preferences.py APPS/<slug>/backend/tests/test_preferences.py
cp HUBapp_TEMPLATE_base/backend/tests/test_services.py    APPS/<slug>/backend/tests/test_services.py
```

Fusionner `conftest.py` (fixtures template + fixtures métier).

### C.7 — Vérification backend

```bash
cd APPS/<slug>
make restart-api          # Redémarre l'API avec le nouveau code
make health               # Vérifie /api/health
make test-docker          # Lance les tests dans Docker
```

Si les tests échouent : vérifier les imports, les dépendances manquantes, les migrations non exécutées.

**Checklist échecs fréquents backend :**

| Symptôme | Cause probable | Action |
|----------|----------------|--------|
| `ImportError: cannot import 'outbox'` | Fichier copié mais pas importé dans `main.py` | Ajouter l'include_router |
| `ImportError: No module named 'xyz'` | Dépendance manquante dans `requirements.txt` | Ajouter et rebuild |
| `psycopg.OperationalError` | Postgres pas prêt | Attendre le healthcheck, `make logs-db` |
| `sqlalchemy.exc.ProgrammingError` | Migration non exécutée | Vérifier `backend/migrations/`, exécuter manuellement |
| `RuntimeError: Hub auth failed` | `HUB_*` manquant dans `.env` | Vérifier `.env` vs `.env.example` |

## Phase D — Frontend core

### D.1 — package.json

Comparer les dépendances. Le template 2.8.0 utilise :

```json
{
  "dependencies": {
    "@tanstack/react-query": "^5.62.0",
    "lucide-react": "^0.460.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@tanstack/react-query-devtools": "^5.62.0",
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  }
}
```

NE PAS écraser le `"name"` et `"version"` (propres à l'app). Mettre à jour les dépendances si elles sont plus anciennes.

Après mise à jour : `cd APPS/<slug>/frontend && npm install`.

### D.2 — Fichiers à copier (safe replace)

```bash
cp HUBapp_TEMPLATE_base/frontend/vite.config.js       APPS/<slug>/frontend/vite.config.js
cp HUBapp_TEMPLATE_base/frontend/docker-entrypoint.sh APPS/<slug>/frontend/docker-entrypoint.sh
cp HUBapp_TEMPLATE_base/frontend/.instructions.md     APPS/<slug>/frontend/.instructions.md
```

### D.3 — src/ providers et hooks

```bash
# Contexte (remplacer — code template pur)
cp HUBapp_TEMPLATE_base/frontend/src/context/AuthContext.jsx   APPS/<slug>/frontend/src/context/AuthContext.jsx
cp HUBapp_TEMPLATE_base/frontend/src/context/ConfigContext.jsx APPS/<slug>/frontend/src/context/ConfigContext.jsx

# Hooks (remplacer — code template pur)
cp HUBapp_TEMPLATE_base/frontend/src/hooks/useApiQuery.js    APPS/<slug>/frontend/src/hooks/useApiQuery.js
cp HUBapp_TEMPLATE_base/frontend/src/hooks/useApiMutation.js APPS/<slug>/frontend/src/hooks/useApiMutation.js

# lib (remplacer)
cp HUBapp_TEMPLATE_base/frontend/src/lib/queryClient.js APPS/<slug>/frontend/src/lib/queryClient.js
```

### D.4 — main.jsx — fusionner

Le `main.jsx` de l'app peut avoir des providers ou routes customs. Le template 2.8.0 a l'arbre de providers suivant :

```
React.StrictMode
  └── ErrorBoundary
       └── ConfigProvider
            └── AuthProvider
                 └── QueryClientProvider
                      ├── App
                      └── ReactQueryDevtools
```

Vérifier que l'app a tous ces providers. Les ajouter s'ils manquent. Préserver les providers métier supplémentaires.

### D.5 — App.jsx — fusion prudente

L'`App.jsx` est le fichier le plus modifié par le métier. Comparer avec le template pour :

1. **Gestion du thème** (light/dark) : si absente, ajouter depuis le template.
2. **Timeout chargement config** : ajouter si absent.
3. **MessageBanner + MessageArchive** : ajouter si absents (notifications SSE).
4. **Composants template manquants** : LoginPrompt, M2MTests, EndpointTests.
5. **Wrapper d'erreur** : ErrorBoundary.

Ne JAMAIS retirer les composants métier ni le routage custom.

### D.6 — Composants template manquants

```bash
cp HUBapp_TEMPLATE_base/frontend/src/components/MessageBanner.jsx  APPS/<slug>/frontend/src/components/MessageBanner.jsx
cp HUBapp_TEMPLATE_base/frontend/src/components/MessageArchive.jsx APPS/<slug>/frontend/src/components/MessageArchive.jsx
cp HUBapp_TEMPLATE_base/frontend/src/components/LoginPrompt.jsx    APPS/<slug>/frontend/src/components/LoginPrompt.jsx
cp HUBapp_TEMPLATE_base/frontend/src/components/ErrorBoundary.jsx  APPS/<slug>/frontend/src/components/ErrorBoundary.jsx
```

### D.7 — Styles app.css

Le `app.css` de l'app a probablement des styles métier ajoutés. Le template a évolué (tokens HUBCSS, dark mode, classes). Procédure :

1. Diff les deux fichiers
2. Repérer les nouveaux tokens/classes dans le template
3. Les ajouter au `app.css` de l'app
4. NE PAS retirer les styles métier

### D.8 — config.js

Comparer. L'app a son slug (INITIALISE). Le template a potentiellement de nouvelles variables d'environnement ou URLs. Fusionner les nouveaux exports sans changer le slug.

### D.9 — Design system (HUBCSS)

Vérifier que `frontend/public/design-system/current/` est à jour :

```bash
# Depuis l'app :
make refresh-design-seed
```

Ou manuellement :
```bash
rm -rf APPS/<slug>/frontend/public/design-system/current/
cp -r HUBCSS/dist/ APPS/<slug>/frontend/public/design-system/current/
```

### D.10 — Vérification frontend

```bash
cd APPS/<slug>
make build              # Rebuild l'image frontend
make up                 # Redémarrage
make health             # Vérifier le healthcheck API
# Accéder au frontend : http://localhost:<FRONTEND_PORT>
# Vérifier dans la console navigateur : pas d'erreur JS, pas de 404 sur les assets
```

Points à vérifier manuellement dans le navigateur :
- La page charge sans erreur console
- Le thème light/dark fonctionne
- Les boutons d'authentification apparaissent
- Les composants métier sont toujours présents

## Phase E — Features

Chaque feature du template est testée individuellement après activation.

### E.1 — M2M Communication

**Fichiers requis** : `backend/hub_client.py`, `backend/hub_auth.py`, `backend/m2m_catalog.py`, `backend/routes/m2m.py`, `frontend/src/components/M2MTests.jsx`

**Vérification** :
```bash
cd APPS/<slug>
# Le frontend doit afficher la section M2M (si authentifié)
# Tester l'endpoint de découverte :
curl -s http://localhost:<API_PORT>/api/m2m/discover | python3 -m json.tool
```

### E.2 — Notifications SSE (Hub)

**Fichiers requis** : `backend/outbox.py`, `backend/routes/preferences.py`, `frontend/src/components/MessageBanner.jsx`, `frontend/src/components/MessageArchive.jsx`

**Vérification** :
- Le `MessageBanner` s'affiche dans le header (cloche + compteur)
- L'endpoint SSE répond : `curl -N http://localhost:<API_PORT>/api/hub/events?token=<JWT>`
- Envoyer un message test via le Hub et vérifier qu'il apparaît

### E.3 — Backup/Restore

**Fichiers requis** : `backend/routes/backup.py`, `backend/tests/test_backup.py`

**Vérification** :
```bash
# Déclencher un backup :
curl -X POST http://localhost:<API_PORT>/api/backup/trigger
# Vérifier dans les logs :
make logs-api | grep -i backup
```

### E.4 — Bulk Operations

**Fichiers requis** : `.opencode/skills/bulk-operations/SKILL.md`, composants frontend associés

**Vérification** : charger le skill `bulk-operations` et suivre sa procédure de test.

### E.5 — Badge Search System

**Fichiers requis** : `.opencode/skills/badge-search-system/SKILL.md`

**Vérification** : charger le skill `badge-search-system` et vérifier que les composants sont présents.

### E.6 — Cache Busting

**Fichiers requis** : `.opencode/skills/cache-busting-deployment/SKILL.md`, configuration nginx 3 tiers

**Vérification** :
```bash
# Vérifier les headers cache sur les assets :
curl -sI http://localhost:<FRONTEND_PORT>/index.html | grep -i cache
curl -sI http://localhost:<FRONTEND_PORT>/assets/ | grep -i cache
```

## Phase F — Tooling & skills

### F.1 — Skills applicatifs (.opencode/skills/)

Copier les skills manquants depuis le template. Les 13 skills du template 2.8.0 :

```bash
# Lister ceux déjà présents :
ls APPS/<slug>/.opencode/skills/
# Copier les manquants :
cp -r HUBapp_TEMPLATE_base/.opencode/skills/<skill-manquant>/ APPS/<slug>/.opencode/skills/
```

Skills critiques (toujours copier) :
- `verify-feature` — cycle de vérification Docker
- `cache-busting-deployment` — procédure cache nginx
- `deploy-troubleshoot` — diagnostic déploiement
- `hub-m2m-communication` — M2M discovery
- `hub-notifications` — notifications SSE
- `release-sync` — cohérence VERSION

### F.2 — Plugin OpenCode

```bash
mkdir -p APPS/<slug>/.opencode/plugins/
cp HUBapp_TEMPLATE_base/.opencode/plugins/hub.ts APPS/<slug>/.opencode/plugins/hub.ts
```

### F.3 — MCP Server

```bash
# Synchroniser hub_mcp/ depuis le template :
cp -r HUBapp_TEMPLATE_base/hub_mcp/ APPS/<slug>/hub_mcp/
```

**Vérification** : le MCP doit être importable :
```bash
cd APPS/<slug> && python -c "from hub_mcp.server import main; print('OK')"
```

### F.4 — Scripts

```bash
# Scripts manquants :
cp HUBapp_TEMPLATE_base/scripts/bump_version.py APPS/<slug>/scripts/bump_version.py
cp HUBapp_TEMPLATE_base/scripts/generate_ai_index.py APPS/<slug>/scripts/generate_ai_index.py
cp -r HUBapp_TEMPLATE_base/scripts/git-hooks/ APPS/<slug>/scripts/git-hooks/
```

### F.5 — Documentation

```bash
cp HUBapp_TEMPLATE_base/docs/HUB_MCP.md APPS/<slug>/docs/HUB_MCP.md
cp HUBapp_TEMPLATE_base/docs/HUB_MESSAGES.md APPS/<slug>/docs/HUB_MESSAGES.md
```

### F.6 — GitHub instructions

```bash
mkdir -p APPS/<slug>/.github/instructions/
cp HUBapp_TEMPLATE_base/.github/instructions/*.instructions.md APPS/<slug>/.github/instructions/
```

## Phase G — Vérification finale

Cycle complet de validation :

```bash
cd APPS/<slug>

# 1. Tests complets
make test-docker-cov

# 2. Healthchecks
make health
make health-detailed

# 3. Vérifier les logs (0 erreur)
make logs-api | grep -i "error\|exception\|traceback"  # Doit être vide
make logs      | grep -i "error\|exception\|traceback"  # Doit être vide

# 4. Vérifier la version
make version   # Doit refléter la version de l'app

# 5. Frontend accessible
curl -sI http://localhost:<FRONTEND_PORT>/ | head -1  # HTTP/1.1 200 OK

# 6. Si tests frontend dans le navigateur :
# - Pas d'erreur console
# - Les composants métier sont présents
# - Les nouvelles features (M2M, notifications) fonctionnent
```

### G.1 — Mise à jour de VERSION

Après migration réussie, mettre à jour `VERSION` et `CHANGELOG.md` :

```bash
# Bump de version (la migration est un feat → minor)
cd APPS/<slug> && python scripts/bump_version.py minor
```

Ajouter une entrée dans `CHANGELOG.md` :
```markdown
## [X.Y.0] - YYYY-MM-DD

### Migrated
- Template mis à jour de [ancienne_version] vers 2.8.0
- [Liste des features ajoutées : M2M, notifications SSE, backup, etc.]
```

### G.2 — Checklist de non-régression

Avant de déclarer la migration terminée, vérifier :

- [ ] `make build` réussit sans erreur
- [ ] `make up` démarre tous les conteneurs
- [ ] `make health` retourne `{"status":"healthy"}`
- [ ] `make test-docker` tous les tests passent (0 failed)
- [ ] Le frontend est accessible et fonctionnel
- [ ] Les composants métier de l'app sont préservés
- [ ] Les nouvelles fonctionnalités template sont opérationnelles
- [ ] Les skills `.opencode/` sont chargeables
- [ ] `VERSION` et `CHANGELOG.md` sont à jour
- [ ] Aucune erreur dans les logs

## Références

| Réf | Chemin |
|-----|--------|
| Template canonique | `HUBapp_TEMPLATE_base/` |
| Version template | `HUBapp_TEMPLATE_base/VERSION` |
| Skills app | `HUBapp_TEMPLATE_base/.opencode/skills/` |
| Skills parc | `.opencode/skills/` |
| HUBCSS | `HUBCSS/dist/` |
| Create app (référence inverse) | `.opencode/skills/create-hub-app/SKILL.md` |
| Agent jellycode | `.opencode/agent/jellycode.md` |
