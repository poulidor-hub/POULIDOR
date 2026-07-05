# POULIDOR — Parc applicatif HUB

Stack : **FastAPI** + **React 18 / Vite 5** + **PostgreSQL 15** + **Docker Compose**.
Pilotage centralisé via `./hubctl` (TUI) ou `make` (par app).

```
POULIDOR/
├── hubctl                    ← CLI de pilotage (TUI interactif)
├── hubctl_cli/               ← Code du CLI (menu, actions, coffre, park-export)
├── HUB_base/                 ← Hub SSO (auth JWT/JWKS, registry, messaging, backups)
├── HUBapp_TEMPLATE_base/     ← Template canonique pour toute nouvelle app
├── APPS/                     ← Applications en PRODUCTION
├── APP_Workshop/             ← Applications en DÉVELOPPEMENT (mode dev)
├── 00_INSTRUCTION_BIBLE/     ← Documentation IA (blueprint, skills, instructions)
└── exports/                  ← Archives park-export
```

---

## Schéma des workflows

### 1. Création d'une nouvelle application

```
HUBapp_TEMPLATE_base/
    │
    │ python ACTIONS/PYTHON/INITIALISE.py [--demo] [--profile client.json]
    │    ├─ 14 étapes : .env, docker-compose, config, frontend, tests, VERSION, CHANGELOG
    │    ├─ Par défaut : NETTOIE le contenu de démo (pas de Item/TestData)
    │    └─ --demo : GARDE le contenu de démo (pour explorer)
    │
    ▼
APP_Workshop/mon-app-ws/          ← Développement (slug suffixé -ws)
    │
    │ make dev                     ← rebuild + logs en direct
    │ make test-docker             ← tests dans le conteneur
    │ ... développement ...
    │
    │ # Push en production :
    │ docker compose down
    │ cp -r APP_Workshop/mon-app-ws APPS/mon-app
    │ sed -i 's/APP_SLUG=mon-app-ws/APP_SLUG=mon-app/' APPS/mon-app/.env
    │ docker compose -f APPS/mon-app/docker-compose.yml up -d
    │
    ▼
APPS/mon-app/                     ← PRODUCTION
```

### 2. Mise en atelier d'une app existante (prod → ws → prod)

```
APPS/exemple-apps/               ← PROD (source)
    │
    │ hubctl → 6. Workshop → [→] Mettre en atelier
    │   ou manuellement :
    │   docker compose down
    │   cp -r APPS/exemple-apps APP_Workshop/exemple-apps-ws
    │   docker run alpine cp volume prod → ws    ← clone la DB prod
    │   sed -i 's/exemple-apps/exemple-apps-ws/' .env
    │   docker compose up -d
    │
    ▼
APP_Workshop/exemple-apps-ws/    ← CLONE de prod (données réelles)
    │
    │ ... développement, tests ...
    │
    │ # Retour en production :
    │ hubctl → 6. Workshop → [←] Remettre en production
    │   ou manuellement : même flux inverse
    │   docker run alpine cp volume ws → prod    ← ramène les modifs DB
    │
    ▼
APPS/exemple-apps/               ← PROD (mis à jour)
```

**Règle d'or** : ne JAMAIS faire `docker compose down -v` (détruit les volumes).

### 3. Sauvegarde et restauration

```
┌──────────────────────────────────────────────────────────┐
│                    SAUVEGARDE                             │
│                                                          │
│  Par app : POST /api/admin/backup → ZIP (DB + fichiers)  │
│  Hub     : backup automatique quotidien (self-backup)    │
│  Coffre  : hubctl → 5. Coffre → 💾 Sauvegarder maintenant │
│  Snapshot : S3/MinIO (pg_dump complet, encrypté zstd)    │
│  Park    : ./hubctl park-export → tar.gz                 │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                    RESTAURATION                           │
│                                                          │
│  Par app : POST /api/admin/restore {ZIP}                 │
│  Coffre  : hubctl → 5. Coffre → ⬇ Récupérer (export)     │
│  Park    : ./hubctl park-restore park.tar.gz             │
│            (Hub VIERGE uniquement — pas de --force)       │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 4. Cycle de vie d'une app (commandes make)

```
make sync-env          ← après toute modif de .env ou VERSION
make dev               ← rebuild + logs (développement)
make up                ← démarrage sans rebuild (production)
make down              ← arrêt
make restart-api       ← redémarrage API seulement
make test-docker       ← tests dans le conteneur
make health            ← curl /api/health
make bump-patch        ← incrément version (x.y.Z)
make clean             ← suppression conteneurs + volumes
```

---

## Commandes hubctl

### Lancement

```bash
./hubctl                          # TUI interactif (menu de pilotage)
./hubctl --no-anim                # Sans intro animée
./hubctl --dry-run                # Imprime sans exécuter
./hubctl --init                   # Clone les dépôts du manifest.json
```

### Menu principal

| Touche | Action |
|:------:|--------|
| `1` | **Apps** — update, ajouter, supprimer, logs |
| `2` | **Hub** — update, réparer, start/stop, logs |
| `3` | **Configuration** — setup, réseau, admin, coffre, workshop |
| `4` | **Scénarios** — quick diag, full update, app rescue, health check |
| `5` | **DEV/PROD** — basculer le mode |
| `0` | Quitter |

### Coffre (Secrets) — touche `3` → `5`

| Action | Description |
|--------|-------------|
| Lister | Parcourt les entrées, affiche `[MODIFIÉ]` si divergence |
| 💾 Sauvegarder | Sauvegarde .env et fichiers dans le vault encrypté |
| ⬇ Récupérer (export) | Export de récupération (`.env` déchiffrés) |
| 🔑 Changer passphrase | Rotation de la clé d'accès au coffre |

### Workshop — touche `3` → `6` (mode DEV uniquement)

| Action | Description |
|--------|-------------|
| [→] Mettre en atelier | Déplace une app de APPS/ vers APP_Workshop/ (clone DB prod) |
| [←] Remettre en production | Ramène une app de APP_Workshop/ vers APPS/ (clone DB modifiée) |

### CLI non-interactif

```bash
./hubctl park-export                     # Export tout le parc → tar.gz
./hubctl park-export --app exemple-apps  # Export une seule app
./hubctl park-restore park.tar.gz         # Restaure sur Hub VIERGE uniquement
```

---

## Commandes make (par app)

Chaque app dans APPS/ et APP_Workshop/ dispose d'un Makefile standard.

| Commande | Description |
|----------|-------------|
| `make sync-env` | Alloue les ports via le Hub + synchronise .env |
| `make dev` | Mode développement (rebuild + logs foreground) |
| `make up` | Démarrer en arrière-plan (sans rebuild) |
| `make down` | Arrêter tous les services |
| `make restart-api` | Redémarrer l'API seulement |
| `make restart-frontend` | Redémarrer le frontend seulement |
| `make build` | Construire les images Docker |
| `make logs` | Logs de tous les services |
| `make logs-api` | Logs de l'API |
| `make logs-db` | Logs de PostgreSQL |
| `make test` | Tests sur l'hôte (SQLite, rapide) |
| `make test-docker` | Tests dans le conteneur (miroir prod) |
| `make test-cov` | Tests avec couverture |
| `make health` | `GET /api/health` |
| `make health-detailed` | `GET /api/health/detailed` |
| `make db-shell` | Shell PostgreSQL interactif |
| `make bump-patch` | Incrémenter version (x.y.Z) |
| `make bump-minor` | Incrémenter version (x.Y.0) |
| `make bump-major` | Incrémenter version (X.0.0) |
| `make clean` | Nettoyer conteneurs, volumes, caches |
| `make clean-all` | + supprimer les images Docker |
| `make ssl` | Générer les certificats SSL |

---

## Architecture d'une application

```
mon-app/
├── backend/                    # API FastAPI async
│   ├── main.py                 # Point d'entrée (lifespan, CORS, proxy /hub/)
│   ├── config.py               # Settings Pydantic
│   ├── database.py             # SQLAlchemy 2.x async engine + migrations
│   ├── models.py               # ORM (DateTime(timezone=True) obligatoire)
│   ├── schemas.py              # Pydantic : requête/réponse
│   ├── hub_auth.py             # Validation JWT/JWKS
│   ├── hub_client.py           # Client Hub : auto-registration, M2M
│   ├── routes/                 # Handlers HTTP
│   ├── migrations/             # SQL incrémentales (TIMESTAMPTZ obligatoire)
│   └── tests/                  # Pytest async
├── frontend/                   # React 18 + Vite 5
│   └── src/
│       ├── context/            # AuthContext, ConfigContext
│       ├── hooks/              # useApiQuery, useApiMutation (TanStack Query)
│       ├── pages/              # Pages
│       └── components/         # Composants réutilisables
├── docker-compose.yml          # postgres + api + frontend (TZ=UTC obligatoire)
├── Dockerfile.backend
├── Dockerfile.frontend
├── nginx.conf                  # Reverse proxy (frontend → api + /hub/ → Hub)
├── Makefile
├── VERSION
└── .env
```

### Conventions critiques

| Règle | Détail |
|-------|--------|
| `DateTime(timezone=True)` | **Obligatoire** dans tous les modèles SQLAlchemy |
| `TIMESTAMPTZ` | **Obligatoire** dans toutes les migrations SQL |
| `TZ=UTC` | **Obligatoire** dans le conteneur Postgres du docker-compose |
| `datetime.now(timezone.utc)` | **Obligatoire** dans tout le code Python |
| SSE `?token=JWT` | **Obligatoire** dans AuthContext (EventSource pas de headers) |
| Refresh proactif | **Obligatoire** 2 min avant expiration du token (15 min TTL) |
| `ExpiredSignatureError` | **Jamais** avalé dans `hub_auth.py._try_decode()` |
| `--demo` | Flag INITIALISE.py pour garder le contenu de démo |

---

## Endpoints clés

| Application | Endpoint | Description |
|-------------|----------|-------------|
| Hub | `:8000/api/health` | Santé Hub |
| Hub | `:8000/api/auth/.well-known/jwks.json` | Clés JWKS |
| App | `:{API_PORT}/api/health` | Santé app |
| App | `:{API_PORT}/api/config` | Configuration publique |
| App | `:{API_PORT}/api/health/hub/jwks` | Statut cache JWKS |
| App | `:{frontend_port}` | Frontend (HTTP) |
| App | `:{frontend_port+1}` | Frontend (HTTPS) |

---

## Installation du Hub

```bash
cd HUB_base/
./install.sh                        # Mode interactif
./install.sh --profile client.json  # Mode non-interactif
```

---

## Références

| Document | Contenu |
|----------|---------|
| `00_INSTRUCTION_BIBLE/CLAUDE.md` | Architecture du parc |
| `00_INSTRUCTION_BIBLE/TEMPLATE/CLAUDE.md` | Blueprint développeur (template) |
| `00_INSTRUCTION_BIBLE/TEMPLATE/AGENTS.md` | Conventions projet |
| `HUBapp_TEMPLATE_base/docs/` | API, Backup, HTTPS, Messages, Remote Apps |
| `.opencode/skills/` | Skills IA (verify-feature, workshop-mover, backup-restore-ops, etc.) |
