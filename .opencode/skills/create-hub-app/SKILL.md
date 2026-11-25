---
name: create-hub-app
description: Use when the user wants to create or scaffold a new application on the HUB. Full workflow: collect info (slug, name, type, client profile, ports), run create_app.sh, execute INITIALISE.py, allocate ports, first boot with health check, and review backend conventions. Triggers on any request involving "créer une app", "nouvelle application", "scaffold une app", "démarrer une app Hub", or "générer une app depuis le template". Also covers the Rust backend variant (`--backend rust` : crate axum avec hub-client embarquée, pour proxy/dataplane/haut débit).
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

1. **Slug** : identifiant unique de l'app (`^[a-z][a-z0-9-]*[a-z0-9]$`, min 3 caractères). Exemples : `mon-app`, `factures`, `exemple-app`.
2. **Nom** : nom lisible (ex: « Facturation », « Gestion documentaire »).
3. **Description** : courte (1-2 phrases).
4. **Type d'app** (`INITIALISE.py` modes) :
   - `client` (défaut) — app livrée à un client. Supporte `--profile fichier.json` pour la fiche client.
   - `tool` — outil interne, config guidée.
   - `other` — saisie manuelle libre.
   - ⚠️ Le mode **auto** (nom d'app en argument positionnel) force type=`tool`.
5. **Ports** (optionnel, laisser vide = allocation automatique par le Hub) :
   - `API_PORT` : backend FastAPI (ex: 9045).
   - `FRONTEND_PORT` : interface React (ex: 4250).
   - Laisser **vide** en général : le Hub alloue automatiquement.
6. **Profil client** (si mode `client`) : chemin vers un fichier JSON structuré au format `docs/client-profile.example.json` dans le template. Contient `app.slug/name/description`, `client.name`, `license.quote_number/quote_date`, `hub.host/api_port/frontend_port`, `ports.api/frontend`.
7. **Backend** (`--backend`, INITIALISE v2) : `python` (défaut) ou `rust`. Critères de choix par profil :

   | Profil | Backend |
   |--------|---------|
   | Proxy, dataplane, transfert haut débit, taux de requêtes élevé | **Rust** (`--backend rust`) — mémoire prévisible, CPU maîtrisé, footprint < 100 Mo |
   | CRUD métier, apps à forte intégration socle, vélocité dev prioritaire | **Python** (défaut) — goulot = DB/réseau, accès natif au socle, écosystème de skills existant |
   | Engine externe wrappé (Gotenberg, Nominatim…) | **Python** — pattern historique inchangé |

   En cas de doute : **Python** (défaut). Seuils à réévaluer après quelques mois d'apps Rust en usage réel (spéc « Variante Rust » §9). Détails : `HUBsocle/docs/REFERENCE-APP-FINE.md` §9.

Si le user n'a pas de préférence explicite : proposer type=`other`, ports=auto, backend=`python`.

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
- Le script crée `APPS/` si absent (`mkdir -p`).

**Mode atelier (dev)** : une app se crée toujours dans `APPS/<slug>`. Le bac à sable est un cycle séparé, créé après coup : `./hubctl atelier <slug>` (ou la vue Santé du Hub) démarre un 2e projet compose `<slug>-ws` avec un clone de la DB, piloté par `APPS/<slug>/.workshop.env`. Voir le skill `app-workshop-mover`.

## Phase C — INITIALISE

```bash
cd APPS/<slug> && python INITIALISE.py [--profile fichier.json] [--backend {python,rust}] [--clean|--demo]
```

Le script exécute **12 étapes** séquentielles (`HUBapp_TEMPLATE_base/ACTIONS/PYTHON/INITIALISE.py`, 2466 lignes — un wrapper racine `INITIALISE.py` délègue via `os.execv`) :

| # | Étape | Fichier cible |
|---|-------|---------------|
| 1 | Création `.env` | `.env` (depuis `.env.example`, `APP_VERSION=0.0.1`) |
| 2 | MAJ `.env.example` | `.env.example` |
| 3 | MAJ `docker-compose.yml` | slug, ports fallback |
| 4 | MAJ `Dockerfile.frontend` | ARGs `VITE_*` |
| 5 | MAJ `frontend/index.html` | titre HTML |
| 6 | MAJ `frontend/package.json` | `name` + `version=0.0.1` |
| 7 | **Personnalisation des tests backend** | `backend/tests/*.py` — `APP_SLUG` conftest + motifs `mon-app`/`Mon Application` ; `EXPECTED_TYPE` du test certificat mappé sur le kind |
| 8 | Réinit `VERSION` | `VERSION` → `0.0.1` |
| 9 | Réinit doc | `CHANGELOG.md` + `README.md` |
| 10 | Nettoyage obsolètes | supprime `frontend/config.js` vestige + `__pycache__` |
| 11 | **Certificat Hub** | `hub-app.yaml` — name/slug/description substitués ; kind `tool` → `spec.type: tool`, sinon `business` |
| 12 | Génération `LICENSE.md` | propriétaire client ou générique |

> **Historique** : les étapes ciblant l'ancienne génération (`backend/config.py`,
> `Header.jsx`, `src/config.js`) ont été retirées en 2.38.0 — depuis 2.35.0
> (app fine sur socle) ces fichiers n'existent plus dans le gabarit, et leur
> absence faisait échouer tout scaffold (exit 1, pas de scripts d'action ni
> de self-destruct) pendant 18 jours. Filet E2E ajouté : `backend/tests/test_initialise_e2e.py`.

**Flags importants :**
- `--profile fichier.json` : lit les infos depuis un profil client JSON (format `HUBapp_TEMPLATE_base/docs/client-profile.example.json`). ⚠️ **Seul ne suffit pas** : le récap `confirm_settings()` attend quand même une confirmation stdin → pour un flux réellement non-interactif (agent), ajouter `--yes`.
- `--yes` / `-y` : saute la confirmation du récapitulatif — indispensable en non-interactif.
- `--force-slug <slug>` : override du slug (utile avec `--profile`).
- `--interactive` : force le mode guidé.
- Mode auto : `python INITIALISE.py <nom>` (nom positionnel) — crée l'app sans questions mais **force type=`tool`**.
- `--clean` (défaut) : nettoie le contenu de démonstration (modèles `Item`/`TestData`, routes `items.py`/`test_data.py`, composants frontend de démo). Produit un squelette minimal prêt à développer.
- `--demo` : garde le contenu de démo pour explorer/exemple.
- `--backend rust` : backend Rust (crate axum + `hub-client` embarquée) au lieu du socle FastAPI Python — cf. sous-section ci-dessous.

### Backend Rust (`--backend rust`)

Le tableau des 12 étapes ci-dessus décrit le backend **Python** ; en Rust, les
étapes backend sont remplacées par la génération de la crate (VERSION,
CHANGELOG, README, `.env.example`, compose, frontend — inférences identiques).
Le reste du workflow (Phase B, allocation des ports, premier boot, healthcheck)
est inchangé. Différences post-génération :

- **`backend/`** : crate Rust (`main.rs` + routes métier) dépendant de
  `backend/hub-client/` — la crate `hub-client` (contrat Hub, parité stricte
  `hub_socle`) est **embarquée par copie** + `Cargo.lock` committé (build
  reproductible). Squelette de référence : `HUBsocle/rust/app-skeleton`.
- **`Dockerfile.backend`** : multi-stage (`rust:1-slim` builder →
  `bookworm-slim` runtime, binaire strippé) au lieu de
  `FROM poulidor/socle-api`.
- **`.env`** : `BACKEND_KIND=rust`, `APP_HUB_CLIENT_VERSION` (version de la
  crate embarquée), `APP_SOCLE_TARGET` (version socle visée).
- **Makefile patché** : `make sync-env` appelle d'abord
  `scripts/sync_hub_client.py` (aligne `APP_HUB_CLIENT_VERSION` sur la crate
  embarquée — divergence → première commande en échec avec message
  actionnable, rebuild image requis, la suivante passe) ; `make test` →
  `cargo test` (l'image runtime ne contient pas de toolchain de test — pas de
  pytest Docker, pas de couverture v1).
- **Identique au backend Python** : infra (compose durci, nginx, scripts,
  ACTIONS), frontend React (`@poulidor/hub-socle` + HUBCSS), migrations SQL
  (auto-appliquées, `schema_migrations` partagée), contrat Hub (register,
  JWKS, M2M, outbox, backup format coffre). Limites v1 : pas de `cert_sync`,
  pas de runner de validation canari — cf. `HUBsocle/docs/REFERENCE-APP-FINE.md` §9.
- **Filet de parité** : suite de contrat `HUBsocle/tests/contract/`
  (`make test-contract` dans HUBsocle, `CONTRACT_BASE_URL` +
  `CONTRACT_ADMIN_TOKEN`) ; matrice de compatibilité
  `HUBsocle/rust/CHANGELOG.md`. La mise à jour d'une app Rust passe par
  `sync_hub_client.py` + matrice (pas par `migrate-app-to-socle`).
- Les conventions **Phase E** ci-dessous sont spécifiques au backend Python ;
  une app Rust suit les conventions du workspace `HUBsocle/rust/` (tests
  miroir `app-skeleton`).

Après succès, `INITIALISE.{py,sh,bat}` est **auto-supprimé** (self-destruct) ainsi que les scripts d'initialisation dans `ACTIONS/`. Les scripts d'action (`START`, `STOP`, `RESTART`, `LOGS`, etc.) sont générés dans `ACTIONS/PYTHON/`, `ACTIONS/LINUX/`, `ACTIONS/WINDOWS/`.

**Certificat Hub (étape 11)** : l'app générée naît avec un `hub-app.yaml` valide à sa racine (schéma `hub.poulidor/v1`) — c'est lui qui rend l'app **visible dans le catalogue « Apps GitHub » du Hub** (Hub_base ≥ 3.94 ; sans manifeste valide, le repo est masqué et refusé à l'ajout, sauf bypass admin). Après création du dépôt GitHub, renseigner le champ optionnel `metadata.repository` (cross-checké par le Hub). Contrat détaillé : `HUB_base/docs/superpowers/specs/2026-11-16-github-apps-certification-design.md`.

**Environnement opencode embarqué** : l'app scaffoldée est immédiatement un environnement Jellycode autonome — `opencode.json` (`default_agent: jellycode`, plugin `superpowers` pinné, MCP `hub`), `.opencode/agent/jellycode.md` et les **skills app** (`.opencode/skills/`) sont copiés tels quels du template par `create_app.sh`. `INITIALISE.py` ne les modifie pas (aucun conflit). Pour le mettre à jour plus tard : `make sync-hub-tooling` (MCP + plugin) et le skill `migrate-app-template` (skills + persona).

## Phase D — Premier boot

```bash
make sync-env        # Alloue les ports via le Hub
make dev             # OU make up si pas de mode dev
make health          # Vérifie GET /api/health
```

**Étape D.1 — Allocation des ports** (`make sync-env`)
La cible Makefile orchestre plusieurs scripts :
1. `ACTIONS/PYTHON/sync_hub_host.py` — découverte/synchro du `HUB_HOST`.
2. `ACTIONS/PYTHON/allocate_ports.py` (97 lignes) :
   - Si `API_PORT`/`FRONTEND_PORT`/`APP_SUBNET` sont vides dans `.env`, fait `POST http://{HUB_HOST}:{HUB_API_PORT}/api/apps/allocate-ports` avec `{slug, host}`.
   - Écrit dans `.env` les valeurs **reçues du Hub** : `API_PORT`, `FRONTEND_PORT`, `FRONTEND_HTTPS_PORT`, `APP_SUBNET`.
   - Idempotent : même slug+host = mêmes valeurs (skip seulement si `API_PORT`, `FRONTEND_PORT` **et** `APP_SUBNET` sont déjà définis).
3. La cible Makefile calcule ensuite les **dérivés locaux** :
   - `FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1` (si absent — c'est le Makefile qui le recalcule, pas `allocate_ports.py`).
   - `APP_VERSION` depuis `VERSION`.

**Étape D.2 — Démarrage**
```bash
make dev     # docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d
             # Rebuild + hot-reload + HMR, logs foreground
make up      # mode prod — bascule HTTPS selon HTTPS_ENABLED :
             #   HTTPS_ENABLED != "false" → generate-ssl.sh + docker-compose.https.yml up -d (défaut flotte)
             #   HTTPS_ENABLED = "false"  → docker compose up -d (HTTP pur)
```
Choix : `make dev` pour développer avec hot-reload, `make up` pour un démarrage en mode prod. (Le bac à sable atelier est un cycle séparé : `./hubctl atelier <slug>`, cf. skill `app-workshop-mover`.)

**Étape D.3 — Healthcheck**
```bash
make health             # UN SEUL curl /api/health (pas de retry intégré) — relancer à la main
                        # tant que le boot n'est pas terminé, ou surveiller `make logs-api`
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

## Phase E — Conventions backend critiques

Rappeler au développeur ces conventions **obligatoires** du template. Sources de vérité (le README ne les documente plus) :

| Règle | Détail | Référence |
|-------|--------|-----------|
| `DateTime(timezone=True)` | Obligatoire côté SQLAlchemy ORM | `backend/models.py` |
| `TIMESTAMPTZ` | Obligatoire dans les migrations SQL | `backend/migrations/001_fix_datetime_timezone.sql` |
| `TZ=UTC` | Obligatoire dans le conteneur Postgres | `docker-compose.yml` |
| `datetime.now(timezone.utc)` | Obligatoire en Python (jamais `datetime.utcnow()`) | `backend/hub_auth.py`, `backend/main.py` |
| SSE `?token=JWT` | Obligatoire — `EventSource` ne supporte pas les headers HTTP | `frontend/src/context/AuthContext.jsx` |
| Refresh proactif | 2 min avant expiration (`expiresIn - 120`, TTL 15 min) | `frontend/src/context/AuthContext.jsx` |
| `ExpiredSignatureError` | Jamais avalé dans `hub_auth` (re-raise) | `backend/hub_auth.py` |

**Migrations SQL** : convention `NNN_description.sql`, exécutées par le runner dans `backend/database.py` (enregistre le préfixe dans `schema_migrations`, savepoint par statement). Documentation : `.github/instructions/migrations-sql.instructions.md`.

## Phase F — Transition vers l'intégration métier

L'app tourne. Pour la suite du développement :

| Besoin | Skill à charger |
|--------|-----------------|
| Faire communiquer deux apps | `hub-m2m-communication` |
| Envoyer des notifications aux utilisateurs | `hub-notifications` |
| Piloter/observer le Hub | `hub-mcp-usage` |
| Créer une page CRUD React | `frontend-crud-page` |
| Vérifier après une modif | `verify-feature` (skill app) |
| Rétrofitter la messagerie sur une app existante | `hub-notifications` (couvre le rétrofit) + `HUBapp_TEMPLATE_base/docs/HUB_MESSAGES.md` |

## Références

| Réf | Chemin |
|-----|--------|
| Template | `HUBapp_TEMPLATE_base/` |
| Version template | `HUBapp_TEMPLATE_base/VERSION` (à lire, ne jamais coder en dur) |
| Script création | `scripts/create_app.sh` |
| INITIALISE | `HUBapp_TEMPLATE_base/ACTIONS/PYTHON/INITIALISE.py` |
| Profil client exemple | `HUBapp_TEMPLATE_base/docs/client-profile.example.json` |
| README template | `HUBapp_TEMPLATE_base/README.md` |
| Conventions backend | fichiers sources du tableau Phase E (models, migrations, compose, AuthContext, hub_auth) |
| Messagerie Hub | `HUBapp_TEMPLATE_base/docs/HUB_MESSAGES.md` |
| Migrations SQL | `HUBapp_TEMPLATE_base/.github/instructions/migrations-sql.instructions.md` |
| Variante Rust | `HUBsocle/docs/REFERENCE-APP-FINE.md` (§9) · `HUBsocle/rust/CHANGELOG.md` (matrice de compat) · `HUBsocle/tests/contract/` (suite de contrat) |
| Workshop mover | `.opencode/skills/app-workshop-mover/SKILL.md` |
