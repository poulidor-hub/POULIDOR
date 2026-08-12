---
name: create-hub-app
description: Use when the user wants to create or scaffold a new application on the HUB. Full workflow: collect info (slug, name, type, client profile, ports), run create_app.sh, execute INITIALISE.py, allocate ports, first boot with health check, and review backend conventions. Triggers on any request involving "créer une app", "nouvelle application", "scaffold une app", "démarrer une app Hub", or "générer une app depuis le template".
argument-hint: 'App requirements (slug, name, type, client profile path, ports)'
---

# Create Hub App

Workflow complet pour créer/scaffolder une nouvelle application sur le Hub POULIDOR depuis le template canonique `HUBapp_TEMPLATE_base`. Hybride : **autonome** sur les phases mécaniques (scaffold, INITIALISE, make, tests), **collaboratif** sur les choix métier (modèles, routes, intégration spécifique).

## Checklist

| Phase | Étape | Autonomie |
|-------|-------|-----------|
| **A** | Collecter les infos de l'app | Guide le user, propose valeurs |
| **B** | Scaffolder avec `create_app.sh` | Autonome |
| **C** | Initialiser avec `INITIALISE.py` | Autonome |
| **D** | Premier boot et healthcheck | Autonome |
| **E** | Vérifier les conventions backend | Information |
| **F** | Transition vers l'intégration métier | Information |

## Phase A — Collecter les informations

Avant de lancer le moindre script, collecte auprès de l'utilisateur :

1. **Slug** : identifiant unique de l'app (`^[a-z][a-z0-9-]*[a-z0-9]$`, min 3 caractères). Exemples : `mon-app`, `factures`, `exemple-apps`.
2. **Nom** : nom lisible (ex: « Facturation », « exemple-apps »).
3. **Description** : courte (1-2 phrases).
4. **Type d'app** (`INITIALISE.py` modes) :
   - `client` (défaut) — app livrée à un client. Supporte `--profile fichier.json` pour la fiche client.
   - `tool` — outil interne, config guidée.
   - `other` — saisie manuelle libre.
5. **Ports** (optionnel, laisser vide = allocation automatique par le Hub) :
   - `API_PORT` : backend FastAPI (ex: 9045).
   - `FRONTEND_PORT` : interface React (ex: 4250).
   - Laisser **vide** en général : le Hub alloue automatiquement.
6. **Profil client** (si mode `client`) : chemin vers un fichier JSON structuré au format `docs/client-profile.example.json` dans le template. Contient `app.slug/name/description`, `client.name`, `license.quote_number/quote_date`, `hub.host/api_port/frontend_port`, `ports.api/frontend`.

Si le user n'a pas de préférence explicite : proposer type=`other`, ports=auto.

## Phase B — Scaffolder

```bash
scripts/create_app.sh <slug>
```

Ce que fait le script (`scripts/create_app.sh`, 67 lignes) :
- Valide le slug (regex `^[a-z][a-z0-9_-]*$`).
- Refuse si `APPS/<slug>` existe déjà.
- **Garde-fou** : vérifie que le submodule `HUBapp_TEMPLATE_base` est initialisé (`Makefile` + `backend/` présents). Sinon, suggère :
  ```bash
  git submodule update --init HUBapp_TEMPLATE_base
  ```
- Copie le template vers `APPS/<slug>` **sans `.git`** (rsync `--exclude '.git'` ou `cp -r` + suppression).
- Ajoute aux `.env` des overrides de chemin (car le Makefile est un niveau plus profond) :
  ```
  HUB_STACK_DIR=../..
  HUB_MCP_SRC=../../hub-mcp/hub_mcp
  ```

**Points d'attention :**
- Le script est toujours exécuté depuis la racine du méta-repo.
- Si le submodule n'est pas initialisé, `create_app.sh` échoue avec un message clair — ne pas contourner.
- Le dossier `APPS/` doit exister.

**Mode atelier (dev)** : si `.dev-mode` existe dans `HUB_base/`, l'app est destinée au développement. Le slug est suffixé avec `-ws` et l'atelier tourne via `docker compose -p X-ws` dans `APPS/<slug>` (override `.workshop.env`), sans déplacer les fichiers. Voir aussi le skill `app-workshop-mover` pour le cycle atelier (créer / supprimer).

## Phase C — INITIALISE

```bash
cd APPS/<slug> && python INITIALISE.py [--profile fichier.json] [--clean|--demo]
```

Le script exécute **14 étapes** séquentielles (`HUBapp_TEMPLATE_base/ACTIONS/PYTHON/INITIALISE.py`, ~2294 lignes) :

| # | Étape | Fichier cible |
|---|-------|---------------|
| 1 | Création `.env` | `.env` (depuis `.env.example`, `APP_VERSION=0.0.1`) |
| 2 | MAJ `.env.example` | `.env.example` |
| 3 | MAJ `docker-compose.yml` | slug, ports fallback |
| 4 | MAJ `backend/config.py` | Settings Pydantic |
| 5 | MAJ `Dockerfile.frontend` | ARGs `VITE_*` |
| 6 | MAJ `frontend/index.html` | titre HTML |
| 7 | MAJ `frontend/Header.jsx` | `<h1>` |
| 8 | MAJ `frontend/package.json` | `name` + `version=0.0.1` |
| 9 | MAJ `frontend/src/config.js` | slug fallback |
| 10 | MAJ fixtures de test | `conftest.py`, `test_m2m.py` |
| 11 | Réinit `VERSION` | `VERSION` → `0.0.1` |
| 12 | Réinit doc | `CHANGELOG.md` + `README.md` |
| 13 | Nettoyage obsolètes | supprime `frontend/config.js` vestige |
| 14 | Génération `LICENSE.md` | propriétaire client ou générique |

**Flags importants :**
- `--profile fichier.json` : mode non-interactif, lit les infos depuis un profil client JSON (format `HUBapp_TEMPLATE_base/docs/client-profile.example.json`).
- `--clean` (défaut) : nettoie le contenu de démonstration (modèles `Item`/`TestData`, routes `items.py`/`test_data.py`, composants frontend de démo). Produit un squelette minimal prêt à développer.
- `--demo` : garde le contenu de démo pour explorer/exemple.

Après succès, `INITIALISE.{py,sh,bat}` est **auto-supprimé** (self-destruct) ainsi que les scripts d'initialisation dans `ACTIONS/`. Les scripts d'action (`START`, `STOP`, `RESTART`, `LOGS`, etc.) sont générés dans `ACTIONS/PYTHON/`, `ACTIONS/LINUX/`, `ACTIONS/WINDOWS/`.

## Phase D — Premier boot

```bash
make sync-env        # Alloue les ports via le Hub
make dev             # OU make up si pas de mode dev
make health          # Vérifie GET /api/health
```

**Étape D.1 — Allocation des ports** (`make sync-env`)
Appelle `ACTIONS/PYTHON/allocate_ports.py` (93 lignes) :
- Si `API_PORT`/`FRONTEND_PORT` sont vides dans `.env`, fait `POST http://{HUB_HOST}:{HUB_API_PORT}/api/apps/allocate-ports` avec `{slug, host}`.
- Écrit les ports reçus dans `.env`.
- Synchronise `FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1` et `APP_VERSION` depuis `VERSION`.
- Idempotent : même slug+host = mêmes ports.

**Étape D.2 — Démarrage**
```bash
make dev     # docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d
             # Rebuild + hot-reload + HMR, logs foreground
make up      # docker compose up -d (mode prod, pas de hot-reload)
```
Choix : `make dev` si `.dev-mode` ou workshop, `make up` sinon.

**Étape D.3 — Healthcheck**
```bash
make health             # curl /api/health — retry jusqu'à 5× avec 2s d'intervalle
make logs-api           # Vérifie "Application startup complete"
```

Signatures d'échec au boot (tableau de diagnostic `verify-feature SKILL.md:50-57`) :

| Log fragment | Cause probable | Action |
|--------------|----------------|--------|
| `bind: address already in use` | Collision port | Changer `API_PORT`/`FRONTEND_PORT` dans `.env` |
| `psycopg.OperationalError` | Postgres pas prêt | Vérifier `POSTGRES_*`, `make logs-db` |
| `relation "..." does not exist` | Migration non exécutée | Voir `backend/migrations/` |
| `ImportError` | Dépendance manquante | Ajouter à `backend/requirements.txt`, rebuild |
| Pydantic `ValidationError` | Schéma/modèle mismatch | Réconcilier `models.py` et `schemas.py` |
| `RuntimeError: Hub auth ...` | `HUB_*` env manquant ou Hub injoignable | Vérifier `.env`, `HUB_HOST` |

**Ne pas avancer si le healthcheck échoue.** Le boot doit être 100% propre avant de passer à la suite.

## Phase E — Conventions backend

**Ne pas dupliquer ici** — les conventions obligatoires (`DateTime(timezone=True)`, `TIMESTAMPTZ`, `TZ=UTC`, `datetime.now(timezone.utc)`, SSE `?token=JWT`, refresh proactif, gestion `ExpiredSignatureError`) vivent dans `HUBapp_TEMPLATE_base/README.md` §« Conventions backend » et les `.github/instructions/*.instructions.md`. L'agent qui travaille dans l'app les lira en place.

## Phase F — Transition vers l'intégration métier

L'app tourne. Pour la suite, charger le skill adapté — voir le listing dans `.opencode/agent/jellycode.md` §5 (skills parc + skills app) ou `.github/instructions/` (instructions copilot par domaine : frontend, migrations SQL, etc.).

## Références

| Réf | Chemin |
|-----|--------|
| Template | `HUBapp_TEMPLATE_base/` |
| Script création | `scripts/create_app.sh` |
| INITIALISE | `HUBapp_TEMPLATE_base/ACTIONS/PYTHON/INITIALISE.py` |
| Profil client exemple | `HUBapp_TEMPLATE_base/docs/client-profile.example.json` |
| README template | `HUBapp_TEMPLATE_base/README.md` |
| Conventions backend | `HUBapp_TEMPLATE_base/README.md:240-249` |
| Migrations SQL | `HUBapp_TEMPLATE_base/.github/instructions/migrations-sql.instructions.md` |
| Workshop mover | `.opencode/skills/app-workshop-mover/SKILL.md` |
