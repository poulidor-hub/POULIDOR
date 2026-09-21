---
name: migrate-app-template
description: Use when a Hub app must be synced to the current HUBapp_TEMPLATE_base template version. Triggers on "mettre à jour/migrer l'app vers le nouveau template", "upgrade/sync template app", VERSION en retard sur le template, ajout de features template manquantes (M2M, SSE, backup/restore, bulk, badge search), PermissionError /app/uploads, ou .env obsolète après migration.
argument-hint: 'Path to the app to migrate (e.g., APPS/mon-app)'
---

# Migrate App Template

Workflow end-to-end pour auditer et mettre à jour une application existante créée avec une ancienne version de `HUBapp_TEMPLATE_base` vers le template canonique actuel. **Ne jamais écraser à l'aveugle** : chaque fichier du template est comparé, les modifications métier de l'app sont préservées, les ajouts du template sont fusionnés — et le `.env` suit la même règle que le code : **fusion, jamais régénération** (étape B.0).

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
| **B** | Infrastructure — **`.env` (B.0)**, Docker, nginx, Makefile | B.0 : `update_env.py` exit 0 + données accessibles ; puis `make build && make up && make health` |
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

### B.0 — ⚠️ Migration du `.env` (OBLIGATOIRE, avant tout rebuild)

Le `.env` d'une app existante contient des valeurs que le `.env.example` ne liste **pas toutes** (ex. `HUB_INSTANCE_ID`) et il lui manque les nouvelles clés du template. `make sync-env` ne crée le `.env` depuis `.env.example` qu'au **premier démarrage** et ne recalcule ensuite que `FRONTEND_HTTPS_PORT` et `APP_VERSION` — il ne fusionne **rien**. Si la fusion n'est pas faite : l'app tourne avec un `.env` obsolète (variables du nouveau compose non définies, ex. `APP_SUBNET`) — ou pire, un `.env` régénéré dont le `POSTGRES_PASSWORD` ne correspond plus au volume → base inaccessible, données « perdues ».

> **Anti-rationalisation** : « le `.env` est bon, ne pas y toucher » est FAUX. Il faut le **mettre à jour** (ajouter les nouvelles clés) tout en **préservant** les valeurs existantes. « Ne pas toucher » et « régénérer » (`cp .env.example .env`) sont tous deux des erreurs.

**Voie automatisée (recommandée — le script vit dans le template, copie-le d'abord s'il n'est pas encore dans l'app)** :

```bash
cd APPS/<slug>

# 0. Le script fait partie du template : le copier dans l'app s'il y est absent
cp ../../HUBapp_TEMPLATE_base/scripts/update_env.py scripts/   # + cible update-env dans le Makefile

# Fusion : sauvegarde horodatée + ajout des clés manquantes + vérification
# des variables requises par le compose (${VAR:?}) — valeurs existantes inchangées.
# Pendant une migration, pointer sur l'exemple DU TEMPLATE (celui de l'app
# peut encore être ancien à ce stade) :
python3 scripts/update_env.py --example ../../HUBapp_TEMPLATE_base/.env.example

# En exploitation courante (l'app pullée a son .env.example à jour) :
make update-env            # ou : python3 scripts/update_env.py
```

L'outil recalcule aussi les valeurs dérivées (`FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1`, `APP_SUBNET` lu sur le réseau Docker existant de l'app si détectable) et sort en erreur (exit 1) avec un message explicite si une variable requise reste vide — **ne passe pas à la suite tant qu'il n'est pas en 0**. Fonctionne sans `make` (serveur de déploiement : `python3 scripts/update_env.py`).

> **Incident typique** (réel, déploiement client) : le serveur tire le nouveau compose par git alors que son `.env` est ancien → `error while interpolating ... APP_SUBNET is missing a value`. Mauvais réflexe vu sur le terrain : `cp .env.example .env` (injecte les valeurs de démo : mot de passe DB, slug, ports vides). Bon réflexe : repartir de l'ancien `.env` (`.env.old` / `.env.pre-update-*` / coffre) puis `python3 scripts/update_env.py` — le subnet réel est relu sur le réseau Docker existant.

Penser aussi à **fusionner le `.env.example` de l'app** (ajouter les nouvelles clés du template, garder les valeurs INITIALISE : slug, nom, ports, version) — c'est lui que `update_env.py` utilisera lors des prochaines mises à jour tirées par `git pull` sur les serveurs de déploiement.

**Voie manuelle (apps plus anciennes sans le script)** (depuis `APPS/<slug>/`) :

```bash
# 1. SAUVEGARDE horodatée de l'ancien .env (référence de restauration)
cp .env ".env.pre-migration-$(date +%Y%m%d-%H%M)"

# 2. DIFF DES CLÉS uniquement (jamais les valeurs dans un log/commit)
grep -oE '^[A-Z_]+' .env | sort > /tmp/env_old.txt
grep -oE '^[A-Z_]+' ../../HUBapp_TEMPLATE_base/.env.example | sort > /tmp/env_new.txt
comm -13 /tmp/env_old.txt /tmp/env_new.txt   # clés du template à AJOUTER au .env
comm -23 /tmp/env_old.txt /tmp/env_new.txt   # clés orphelines à CONSERVER

# 3. FUSION : ajouter chaque clé manquante au .env avec la valeur par défaut
#    du nouveau .env.example. NE JAMAIS régénérer le .env complet.
#    (éditer .env — une clé par ligne, en fin de fichier)

# 4. VÉRIFIER que les valeurs critiques sont identiques à la sauvegarde
#    (le diff doit être VIDE) :
diff <(grep -E '^(POSTGRES_|APP_SLUG|API_PORT|FRONTEND_PORT|APP_SUBNET|HUB_)' .env) \
     <(grep -E '^(POSTGRES_|APP_SLUG|API_PORT|FRONTEND_PORT|APP_SUBNET|HUB_)' .env.pre-migration-*)

# 5. Recalculer les valeurs dérivées, redémarrer, vérifier
make sync-env && make up && make health
```

**Valeurs critiques — à ne JAMAIS changer** (le diff de l'étape 4 doit être vide) :

| Variable | Pourquoi |
|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Le volume `postgres_data` a été initialisé avec ces valeurs au premier boot. Les changer rend la base **inaccessible** : les données existent toujours mais plus personne ne peut les lire. |
| `POSTGRES_HOST` | Contient le slug (`<slug>-postgres`) — doit correspondre au service du compose. |
| `APP_SLUG` | Identité Hub, noms de volumes/conteneurs, URLs enregistrées. |
| `API_PORT` / `FRONTEND_PORT` | Enregistrés dans le Hub (liens du dashboard) ; les changer casse les URLs publiées. |
| `APP_SUBNET` | Réseau Docker de l'app ; le changer force une recréation du réseau (conflits VPN/pool). |
| `HUB_INSTANCE_ID` / secrets d'enregistrement | Identité de l'app auprès du Hub — absents du `.env.example`, donc perdus si régénération. |
| `FRONTEND_HTTPS_PORT` | Dérivé (`FRONTEND_PORT + 1`) — recalculé par `make sync-env`, ne pas le deviner. |

**Récupération « au cas où »** : le coffre (`skill parc` `vault-manager`) capture `APPS/<slug>/.env` en lecture seule (automatique au démarrage de hubctl, ou `backup_all`). Pour récupérer une ancienne version : `export_recovery` écrit une copie en clair sous `hubctl_cli/recovery/<stamp>/` **sans jamais toucher au disque**. La sauvegarde horodatée de l'étape 1 reste la référence la plus directe.

**Vérification données après redémarrage** (obligatoire quand un volume existe) :

```bash
# La base répond avec les identifiants d'origine :
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\dt'
# + un endpoint métier avec des données attendues (l'app doit retrouver SES données)
```

Le reste de la phase met à jour les fichiers Docker, nginx et Makefile. Ces fichiers sont **majoritairement template** (peu/pas de code métier), donc le remplacement est généralement sûr.

### B.1 — Fichiers à copier depuis le template (safe replace)

```bash
cp HUBapp_TEMPLATE_base/Dockerfile.backend    APPS/<slug>/Dockerfile.backend
cp HUBapp_TEMPLATE_base/Dockerfile.frontend   APPS/<slug>/Dockerfile.frontend
cp HUBapp_TEMPLATE_base/Dockerfile.frontend.dev APPS/<slug>/Dockerfile.frontend.dev
cp HUBapp_TEMPLATE_base/nginx.conf            APPS/<slug>/nginx.conf
cp HUBapp_TEMPLATE_base/nginx-ssl.conf        APPS/<slug>/nginx-ssl.conf
cp HUBapp_TEMPLATE_base/.dockerignore         APPS/<slug>/.dockerignore
cp HUBapp_TEMPLATE_base/docker-compose.dev.yml  APPS/<slug>/docker-compose.dev.yml
cp HUBapp_TEMPLATE_base/docker-compose.https.yml APPS/<slug>/docker-compose.https.yml
```

**Dépendances du Makefile 2.20** (à copier aussi, sinon `sync-env`/`ensure-api-fresh` cassés) :
```bash
# ACTIONS nouvelle génération (allocation ports Hub, synchro HUB_HOST, fraîcheur image)
cp -r HUBapp_TEMPLATE_base/ACTIONS/PYTHON/{sync_hub_host,allocate_ports,check_image_freshness,INITIALISE}.py APPS/<slug>/ACTIONS/PYTHON/
cp HUBapp_TEMPLATE_base/INITIALISE.{py,sh,bat} APPS/<slug>/
# Scripts : fusion .env (B.0), bump, SSL, index IA
cp HUBapp_TEMPLATE_base/scripts/{update_env.py,test_update_env.py,bump_version.py,generate_ai_index.py,generate-ssl.sh,install-hooks.sh} APPS/<slug>/scripts/
cp -r HUBapp_TEMPLATE_base/scripts/git-hooks APPS/<slug>/scripts/
```

⚠️ **Allocation locale (station de dev sans Hub gérant l'app)** : `APP_SUBNET` est
requis par le compose (`${APP_SUBNET:?}`) et les ports doivent être libres.
Avant d'allouer : `ss -tlnp | grep :<port>` + `docker network inspect` (subnets pris).
Tenir un **registre** par station : subnets du pool Hub `10.50.N.0/24` (N incrémenté)
et paires API/FRONTEND ports. Le premier boot (pas de `.env` existant) se fait par :
`cp .env.example .env` puis `APP_SUBNET=<alloué>` puis `make sync-env`/`update_env.py`
(→ v0.53.4 : `update_env.py` ne lit le subnet que sur un réseau Docker **existant** ;
première install = allocation manuelle).

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

**Points à vérifier dans le template actuel** (version : lire `HUBapp_TEMPLATE_base/VERSION`) :
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

### B.6 — ⚠️ Volumes pré-existants possédés par root et image non-root (re-chown obligatoire)

Depuis le durcissement sécurité du template (≥ 2.15), le conteneur API tourne en
**`appuser` (uid 1000)** avec `cap_drop: ALL` (cf. `Dockerfile.backend` : `USER appuser`).
Un volume nommé créé **avant** ce durcissement (quand l'API tournait en root) reste
possédé par `root:root` : le montage masque le `/app/uploads` chown-é de l'image →
**toute écriture échoue** (`PermissionError: [Errno 13]`) : uploads de fichiers,
backups… avec un HTTP 500 côté client. Le bug est **latent** : il ne se manifeste
qu'à la première écriture, souvent bien après la migration.

**Incident de référence** (2026-08-22, exemple-app) : upload d'un message vocal mp3
→ 500 « Échec de l'upload du message vocal », stack trace
`PermissionError: [Errno 13] Permission denied: '/app/uploads/voicemail_….mp3'`.
Le volume datait du 14/08 (créé quand l'API tournait en root), le durcissement était
arrivé le 21/08 avec la migration template — l'app semblait saine pendant une semaine.

**Re-chown après `make up`** — l'API n'a plus `CAP_CHOWN`, un `docker exec -u 0` ne
fonctionne pas : passer par un conteneur one-shot sur le volume nommé.

```bash
# 1. Détection : le process est appuser mais le montage est-il encore root ?
docker exec <slug>-api id                          # uid=1000(appuser)
docker exec <slug>-api ls -ld /app/uploads         # si "root root" → re-chown requis

# 2. Re-chown du volume nommé (nom : <slug>-uploads-data, cf. docker volume ls)
docker run --rm -v <slug>-uploads-data:/data alpine chown -R 1000:1000 /data

# 3. Vérification — test d'écriture réel en appuser (un simple ls ne suffit pas)
docker exec <slug>-api touch /app/uploads/.rw_test \
  && docker exec <slug>-api rm /app/uploads/.rw_test && echo "ECRITURE OK"
```

**Non concerné** : `postgres_data` — l'image postgres conserve CHOWN/FOWNER/SETGID/SETUID
(cf. compose) et corrige son datadir seule. Seuls les volumes montés dans le service
`api` (typiquement `uploads_data`) sont impactés. Si le volume n'existe pas encore
(première création par `make up`), il hérite du chown de l'image → rien à faire.

## Phase C — Backend core

### C.1 — Requirements

Comparer `backend/requirements.txt`. Le template actuel a potentiellement de nouvelles dépendances. Ajouter celles qui manquent :

```bash
diff HUBapp_TEMPLATE_base/backend/requirements.txt APPS/<slug>/backend/requirements.txt
```

Dépendances critiques du template (vérifier présence) :
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
cp HUBapp_TEMPLATE_base/backend/cert_sync.py    APPS/<slug>/backend/cert_sync.py
cp HUBapp_TEMPLATE_base/backend/storage.py      APPS/<slug>/backend/storage.py
cp HUBapp_TEMPLATE_base/backend/utils.py        APPS/<slug>/backend/utils.py
cp HUBapp_TEMPLATE_base/backend/database.py     APPS/<slug>/backend/database.py
cp HUBapp_TEMPLATE_base/backend/entrypoint.sh   APPS/<slug>/backend/entrypoint.sh
cp HUBapp_TEMPLATE_base/backend/pytest.ini      APPS/<slug>/backend/pytest.ini
```

> **v2.24.0+** : `make test` est parallèle par défaut (pytest-xdist, `-n auto`, variable
> `XDIST_WORKERS`) ; `make test-seq` pour le debug séquentiel. `make test-docker` requiert
> le rebuild d'image (gardé par `ensure-api-fresh`, automatique).

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
cp HUBapp_TEMPLATE_base/backend/routes/items.py       APPS/<slug>/backend/routes/items.py
cp HUBapp_TEMPLATE_base/backend/routes/test_data.py   APPS/<slug>/backend/routes/test_data.py
```

⚠️ `items.py` et `test_data.py` sont importés par le `main.py` template (le second
sous gating `ENABLE_DEMO_ENDPOINTS`) : les copier **même si l'app les avait
supprimés**, sinon `ModuleNotFoundError: No module named 'routes.items'` au boot.
Exception : si `routes/preferences.py` de l'app est une **variante métier**
(ex. `DIPECUserPreference` + CRUD lieux), la conserver — ne pas écraser par le
template — et retirer `test_preferences.py` du socle si inapplicable (le documenter).

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
| `password authentication failed for user` (postgres) | `.env` régénéré depuis `.env.example` : `POSTGRES_PASSWORD` ne correspond plus au volume existant | Restaurer les `POSTGRES_*` depuis `.env.pre-migration-*` (B.0) — les données sont intactes |
| Compose warning `The "X" variable is not set` / variable vide dans le conteneur | Nouvelle clé du `.env.example` jamais fusionnée dans le `.env` | Compléter la fusion B.0, `make sync-env && make up` |

## Phase D — Frontend core

### D.1 — package.json

Comparer les dépendances. Le template utilise (versions indicatives — comparer réellement) :

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

#### D.3.1 — ⚠️ Bug auth legacy « onglet qui se referme au lancement » (à corriger par la migration)

Les `AuthContext.jsx` antérieurs au template 2.11.2 portent un bug visible depuis que les
access tokens HUB durent 30 min (`ACCESS_TOKEN_EXPIRE_MINUTES=30`, ex-480) : au clic sur
l'app dans le HUB, l'onglet s'ouvre puis **se referme aussitôt** — il faut recliquer pour
que ça fonctionne.

**Mécanisme** (vérifié en prod, cf. incident 2026-08-14) :
1. Le flux de lancement HUB livre `?access_token=<frais>` **sans** `refresh_token` dans l'URL.
2. L'app conserve en localStorage un refresh token d'une session précédente, **consommé par
   la rotation** du HUB (l'onglet HUB refresh toutes les ~28 min).
3. Variante aggravante (ex. exemple-app avant 2.15.3) : état initial lu depuis le localStorage
   **seulement**, avec le token URL traité dans un effet *après* le mount → si le token
   localStorage est expiré, `logout()` est déclenché **avant** que le token frais de l'URL
   ne soit pris en compte.
4. `logout()` redirige vers le HUB `?action=logout` → `window.close()` → onglet fermé.
   Au 2e clic, le localStorage a été purgé par le logout → le token URL est accepté.

**Le AuthContext du template actuel corrige les deux points** :
- lecture du token **URL-first synchrone** au mount (`getInitialToken` en initializer de
  `useState`, jamais dans un effet) ;
- **purge du refresh token localStorage** quand un token de lancement arrive **sans**
  `refresh_token` associé (périmé par construction).

**Vérification post-migration** (obligatoire) :
```bash
grep -n "getInitialToken" APPS/<slug>/frontend/src/context/AuthContext.jsx   # doit exister
grep -n "removeItem(config.storageKeys.refreshToken)" APPS/<slug>/frontend/src/context/AuthContext.jsx  # purge au lancement
```
Puis test manuel : dans l'app ouverte, laisser la session HUB se rafraîchir (> 30 min ou
forcer un refresh HUB), puis relancer l'app depuis le dashboard → le 1er clic doit ouvrir
l'app sans fermeture. Vérifier aussi l'absence de `POST /api/auth/token/refresh 401` dans
les logs hub-api juste après un launch.

#### D.3.2 — ⚠️ SSE du Hub sans token (spam du journal d'erreurs HUB)

Les `AuthContext.jsx` legacy connectent le flux SSE du HUB **sans authentification** :

```js
// ❌ legacy — 401 depuis l'audit #12 (SSE authentifié obligatoire)
const sseUrl = `${hubApiUrl}/api/events/stream`
```

Le HUB rejette en 401 → le client reconnected en boucle toutes les 10 s → **~14 000
entrées/jour** dans le journal d'erreurs du HUB (incident 2026-08-15), qui masquent les
vrais incidents. Depuis HUB_base 3.29.1, ces 401 ne sont plus enregistrés en base (bruit
attendu), mais les apps concernées **n'ont pas de notifications SSE fonctionnelles** tant
que le token n'est pas envoyé.

**Le AuthContext du template corrige** (EventSource ne supporte pas les headers) :
```js
// ✅ pattern template
const sseUrl = `${hubApiUrl}/api/events/stream?token=${encodeURIComponent(token)}`
console.log('🔌 Connexion SSE au Hub:', sseUrl.replace(token, '***'))
```
avec `token` dans les dépendances du `useEffect` SSE (reconnexion avec le token rafraîchi).

**Vérification post-migration** (obligatoire) :
```bash
grep -n "events/stream?token=" APPS/<slug>/frontend/src/context/AuthContext.jsx  # doit exister
```
Et dans les logs hub-api : `GET /api/events/stream?token=... 200 OK` (plus de boucle 401)
quand l'app est ouverte.

### D.4 — main.jsx — fusionner

Le `main.jsx` de l'app peut avoir des providers ou routes customs. Le template actuel a l'arbre de providers suivant :

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

Copier les skills manquants depuis le template. Les 13 skills du template :

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

Après migration réussie, mettre à jour `VERSION` et `CHANGELOG.md`. Procédure de release complète : skill parc **`release-on-main`** (gate obligatoire avant tout push main).

```bash
# Bump de version (la migration est un feat → minor)
cd APPS/<slug> && make bump-minor   # ou : python3 scripts/bump_version.py minor
```

⚠️ `bump_version.py` **valide** l'entrée CHANGELOG mais ne la crée pas : prépender l'entrée soi-même (format ci-dessous, date en français), puis vérifier `python3 scripts/bump_version.py --check` (exit 0).

Ajouter une entrée dans `CHANGELOG.md` :
```markdown
## [X.Y.0] - 19 septembre 2026

### Migrated
- Template mis à jour de [ancienne_version] vers <version lue dans HUBapp_TEMPLATE_base/VERSION>
- [Liste des features ajoutées : M2M, notifications SSE, backup, etc.]
```

### G.2 — Checklist de non-régression

Avant de déclarer la migration terminée, vérifier :

- [ ] `make build` réussit sans erreur
- [ ] `make up` démarre tous les conteneurs
- [ ] `make health` retourne `{"status":"healthy"}`
- [ ] `make test-docker` tous les tests passent (0 failed)
- [ ] Le frontend est accessible et fonctionnel
- [ ] **Bug « onglet qui se referme » corrigé** : AuthContext URL-first + purge refresh token (cf. D.3.1) — 1er clic depuis le dashboard ouvre l'app sans fermeture, pas de `refresh 401` dans les logs hub-api après un launch
- [ ] **SSE authentifié** : `events/stream?token=` présent dans l'AuthContext (cf. D.3.2) — SSE 200 dans les logs hub-api quand l'app est ouverte, pas de boucle 401
- [ ] **Volumes re-chown-és** : `/app/uploads` appartient à `appuser:appuser` et le test d'écriture passe (cf. B.6) — pas de `PermissionError` dans les logs api au premier upload/backup
- [ ] **`.env` migré (B.0)** : sauvegarde horodatée `.env.pre-migration-*` présente ; toutes les clés du nouveau `.env.example` présentes dans le `.env` (diff de clés vide dans le sens template → app) ; `POSTGRES_*`, ports, `APP_SLUG`, `APP_SUBNET`, `HUB_INSTANCE_ID` **identiques** à la sauvegarde ; données accessibles (endpoint métier ou comptage SQL sur la base existante)
- [ ] Les composants métier de l'app sont préservés
- [ ] Les nouvelles fonctionnalités template sont opérationnelles
- [ ] Les skills `.opencode/` sont chargeables
- [ ] `VERSION` et `CHANGELOG.md` sont à jour
- [ ] Aucune erreur dans les logs

## Annexe — Retour d'expérience des migrations réelles (sept. 2026, 8 apps APPS/MIGRATION)

### Règle d'or des fusions : TEMPLATE D'ABORD, métier réinjecté ensuite

Pour `main.py`, `config.py`, `schemas.py`, `conftest.py`, `config.js`, `vite.config.js`,
`docker-compose.yml` : **partir du fichier template et y réinjecter les blocs métier**,
jamais patcher l'original. Patch incremental sur l'original = il manque silencieusement
worker outbox, cert_sync, items_router, endpoints démo gated, validateurs → symptômes :
`Settings has no attribute ENABLE_DEMO_ENDPOINTS`, `main has no attribute outbox_service`,
404 sur `/api/items`, suite de tests socle en échec. (Erreur commise 3× sur 8 apps.)

### Qualification A/B : échec pré-existant vs régression de migration

Tout test métier qui échoue après migration doit être qualifié **avant** d'être corrigé :
```bash
git worktree add /tmp/ab_head HEAD            # code d'avant migration
docker cp /tmp/ab_head/backend/. <slug>-api:/app/   # écrase le code du conteneur
docker compose exec api sh -c "cd /app && find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null; python -m pytest <tests> -q"
git worktree remove --force /tmp/ab_head
docker compose up -d --force-recreate api     # le docker cp survit au restart : recréer depuis l'image
```
- Échec aussi sur HEAD → **pré-existant** : ne pas corriger dans la migration, documenter au CHANGELOG.
- Échec seulement sur fusionné → **régression** : la corriger avant de finir.
Attention : `docker compose restart` ne recharge pas le code baked dans l'image ; utiliser
`--build` ou `--force-recreate`.

### Table symptôme → cause → correction (observés en réel)

| Symptôme (boot/tests) | Cause | Correction |
|---|---|---|
| `ModuleNotFoundError: cert_sync` / `routes.items` | fichier template oublié dans les copies (C.2/C.4) | compléter les copies (cf. listes) |
| `Settings has no attribute ENABLE_DEMO_ENDPOINTS` | `config.py` original patché au lieu de template+patchs | refaire : template puis injecter slug/ports/champs métier |
| `main has no attribute outbox_service`, endpoints `/api/public` etc. 404 | `main.py` original patché au lieu de template+patchs | idem |
| `NameError: date/Union/List/Any/Decimal/Literal/timezone/JSON/Index/enum/re` au boot | imports « union » non complétés après fusion de blocs métier | compléter `from typing`/`datetime`/`decimal`/`sqlalchemy`/`pydantic`/`import re/enum` en scannant les symboles des blocs injectés |
| `Table 'app_settings'/'items' already defined` | modèle réinjecté en double (bloc métier + template) | retirer le doublon ; ne réinjecter que les classes absentes |
| `ImportError: cannot import name '_validate_email_format'` etc. | l'extraction des blocs schemas par `^class` rate les **fonctions et constantes** top-level métier | extraire aussi `def ...` et `CONST = ...` du HEAD (bornes : jusqu'à la prochaine définition top-level) |
| `NameError: BeneficiaireSearchResult is not defined` | blocs réinjectés dans un ordre qui casse les références | conserver l'**ordre original** du fichier app (git show HEAD) |
| 307/404 inexpliqués sur routes métier dans les tests | pré-existant (tests obsolètes) — qualifier par A/B | documenter, corriger hors migration |
| `TypeError: TokenPayload got unexpected keyword 'roles'` | le TokenPayload 2.20 n'a pas de champ `roles` | retirer `roles=` des fixtures/tests métier ; garder `UserInfo.roles` (schemas) |
| 403 « Accès réservé aux service accounts » sur test multi-clients | fixtures partageant `mock_hub_auth.decode_token` — la dernière fixture écrase le token | réassigner `decode_token.return_value = mock_m2m_token` avant l'appel M2M dans le test |
| `TypeError: unhashable type: 'list'` dans `require_any_role` | appels métier `require_any_role(["a","b"])` (liste) vs variadique template | tolérance locale : déplier `roles[0]` si list/tuple (patch documenté) |
| `TypeError: a coroutine was expected, got AsyncGeneratorContextManager` | `@asynccontextmanager` orphelin collé à une fonction après extraction de blocs | retirer le décorateur orphelin |
| `Bind for 0.0.0.0:9045 failed: port is already allocated` | conflit avec une autre app locale (ou l'app elle-même pré-migrée) | vérifier `ss -tlnp` avant allocation ; ports uniques par app sur la station |
| `FRONTEND_HTTPS_PORT=4251, attendu=4146` (frontend en boucle) | `FRONTEND_HTTPS_PORT` ≠ `FRONTEND_PORT + 1` après changement de ports | `FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1` dans `.env` (le entrypoint frontend valide) |
| `host not found in upstream "backend"` (frontend en boucle) | section `links: api:backend` perdue pendant la fusion compose (proxy nginx `/api` → `backend`) | rétablir `links: - api:backend` sur le service frontend + `up -d --force-recreate frontend` |
| `make health` échoue juste après `up` | boot long (migrations, RGPD, seed) | attendre/retry avant de conclure à un crash ; vérifier `docker logs` |
| CHANGELOG.md « not found » au build frontend/backend | `.dockerignore` template exclut `*.md` | ajouter `!CHANGELOG.md` si l'app le copie dans l'image (route `/api/docs`) |

### Conftest : fusion en 4 éléments

`conftest.py` fusionné = **template** + (1) slug app dans les `apps={...}` des mocks,
(2) `import models  # noqa` après `from config import get_settings` (enregistrement
Base.metadata pour les tests isolés), (3) **restaurer les fixtures métier** du conftest
app (`manager_client`, `global_roles`, `mock_m2m_token` avec `token_type="service"`),
(4) adapter les tests socle au slug (`test_m2m.py` contient le slug en dur). Ne jamais
écraser un test app enrichi (ex. `test_m2m.py` métier) par la version template sans diff
préalable — vérifier ce que contient la version app (`grep -c mon-app`, fixtures utilisées).

### Frontend : les 6 vérifications

1. `package.json` : `@tanstack/react-query` + `lucide-react` **`^0.460.0`** (corriger les
   `^1.x` incohérents) + devtools ; garder tailwind/router métier si présents.
2. `config.js` : remplacer par le template (sinon `"APP_VERSION" is not exported` au build)
   puis réinjecter le slug INITIALISE.
3. `main.jsx` : arbre `ErrorBoundary > ConfigProvider > AuthProvider > QueryClientProvider`
   autour de l'`App` métier + imports `index.css` **et** `app.css`.
4. `index.html` : 3 `<link>` `/design-system/current/*` ; `App.jsx` : monter `<MessageBanner />`.
5. `vite.config.js` : template (proxy `/api` + `/hub`, `loadEnv`) + plugin tailwind app.
6. Seed HUBCSS : si `HUBCSS/dist` absent du submodule, copier le seed depuis une app déjà
   migrée (`APPS/<app>/frontend/public/design-system/current/`) — le seed est commité.

### Bump final

`bump_version.py minor` (migration = feat) puis **vérifier** que `/api/health` affiche la
nouvelle version — sinon rebuild api (APP_VERSION est baked au build).

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
