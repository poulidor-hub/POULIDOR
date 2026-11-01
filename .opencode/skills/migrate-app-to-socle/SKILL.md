---
name: migrate-app-to-socle
description: Use when migrer une application existante de APPS/ vers le modèle app fine sur HUBsocle (vague B8), quand une app doit être « passée sur le socle », convertie à create_app(), purgée de ses modules transverses, rebâtie sur poulidor/socle-api, ou lors d'une release d'app après un bump de socle du parc.
---

# Migrer une app vers le socle (app fine)

## Overview

Recette de conversion d'une app fork (`APPS/<slug>`) en app fine consommant
HUBsocle. Principe : **le socle fournit le transverse, l'app ne garde que son
métier**. Chaque étape laisse l'app bootable et committée.

**Prérequis de lecture** : `HUBsocle/docs/REFERENCE-APP-FINE.md` (contrat
d'extension + 12 pièges) et le plan de vague en cours (ledger SDD).

## When to Use

- App async (grep `create_async_engine` dans `backend/database.py`) fork du template
- **NE PAS utiliser** si l'app est sync (`from sqlmodel import Session`) ou
  non-Python (cf. audits exemple-app / exemple-app) — cadrage dédié requis

## Recette (ordre strict)

1. **Audit d'entrées** (subagent ou greps) : settings hors socle, routers
   métier vs socle, models métier vs `models_core`, storage custom, deps pip
   hors `pyproject` socle, migrations (002_create_outbox local = à retirer,
   socle 090 ; plage app = 001-08x), consommateurs M2M du slug.
2. **Pré-requis socle** : toute extension générique portée par l'app
   (helper auth, hub_client, fix backup) s'upstream au socle d'abord (TDD,
   test porté de l'app) → release socle + `hubctl socle build --force` +
   **vérifier le paquet DANS l'image** (`docker run --entrypoint python
   <image> -c "import hub_socle; print(hub_socle.__version__)"`).
   **Bump socle = `python3 scripts/sync_version.py` obligatoire** (régénère
   `hub_socle/__version.py` que le build incruste — l'oublier = image avec
   `socle_version` en retard, payé 2.30.2→2.30.4). **Deps de TEST demandées
   par la migration → `dependencies` runtime du socle** (offline-first :
   aucun `pip install` au build d'app fine ; optional `dev` = `make
   test-docker` cassé pour toutes les apps, 2.30.4).
3. **Backend** : extraire les endpoints inline de `main.py` vers
   `routes/<metier>.py` (`@app.` → `@router.`) ; émonder les endpoints
   dupliqués du socle (status/discover/call/catalog si prefix déjà dans
   l'APIRouter) ; supprimer les modules transverses **et `entrypoint.sh`**
   (l'image socle fournit `socle-entrypoint`) ; `models.py` sur
   `hub_socle.database.Base` (exciser les classes core) ; **migrations SQL
   métier : garder `backend/migrations/`** — le socle applique
   `/app/migrations` automatiquement (fusion triée, tracking
   `schema_migrations` partagé → les versions fork déjà appliquées sont
   reconnues) ; **jamais de fichiers SQL dans `migration_hooks`** (ils
   tournent AVANT `init_db`) ; **seeds et tâches asyncio métier →
   `lifespan_extra`** (tourne APRÈS `init_db`/`apply_migrations` ;
   `create_task` + `cancel`/`await` au `finally` pour un scheduler/worker) ;
   **endpoint métier pris dans un router socle forké** (ex. exemple-app
   `GET /api/m2m/employees/hub-identifier` dans le fork `routes/m2m.py`) :
   l'extraire vers un router app-side dédié AVANT de purger le router ;
   **`utils.py` hybride** (transverse + métier) : réexporter les fonctions
   socle (`from hub_socle.utils import ...`) et garder le métier ;
   **auditer `flush()` sans `commit()`** dans les handlers d'écriture →
   `commit()` explicite — stratégie proportionnée : petit métier = tout
   corriger ; gros métier (95+ sites) = préserver le comportement fork
   (override de test committant), corriger le handler du canari 2-sessions,
   documenter la dette (référence §3) ; **champs Settings « morts » : ne se
   fier qu'au grep des usages runtime `settings.X`** sur tout le backend —
   un usage dans une fonction évaluée au niveau module est vivant
   (exemple-app `M2M_*TIMEOUT` : 500 AttributeError sinon).
4. **Infra** : `Dockerfile.backend` = `FROM poulidor/socle-api:${SOCLE_VERSION}`
   + `COPY backend/ /app/` + `COPY VERSION` ; compose arg `SOCLE_VERSION=?` +
   `additional_contexts: socle` (frontend) ; `.env.example` +
   `APP_SOCLE_VERSION` ; Makefile + `scripts/sync_socle_version.py` (copié du
   template) appelé dans `sync-env` ; `ssl/.gitkeep` ; opt-in réparation
   volumes root (`user: "0"` + caps CHOWN/SETUID/SETGID) si volumes frais ;
   **volumes/réseau d'une app migrée : préserver les noms historiques
   explicites** (jamais `${APP_SLUG}-*` si les volumes prod existent sous un
   autre nom) ; **overlay dev** : `additional_contexts` dans
   `docker-compose.dev.yml` (créer le fichier s'il manque — `make dev` est
   alors cassé) + `COPY --from=socle` AVANT `npm install` dans
   `Dockerfile.frontend.dev` ; `.dockerignore` : exclure le symlink `socle` ;
   **`USER appuser` du socle persiste dans les layers** : un `RUN chown` de
   l'app tourne en appuser et échoue silencieusement — `USER root` autour,
   retour `USER appuser` ; **`make test-docker` : `XDIST_DOCKER_WORKERS ?= 2`**
   (`-n auto` = OOM 512 Mo, exit 137).
5. **Frontend** : dep `@poulidor/hub-socle": "file:../socle"` ; symlink dev
   `<repo>/socle → ../HUBsocle` (gitigné) ; supprimer context/hooks/lib/config
   + composants communs ; imports → `@poulidor/hub-socle/...` **avec
   extension** (`.jsx`/`.js`) ; `vite.config` + `resolve.preserveSymlinks:
   true` ; `Dockerfile.frontend` : `COPY --from=socle /frontend /socle/frontend`
   **avant** `npm install` ; `npm run build` vert.
6. **Tests** : supprimer les tests des briques socle (ils vivent au socle) ;
   conftest hermétique (§4 : env ÉCRASÉ avant imports, mocks sur
   `hub_socle.*`, autouse offline — voir pièges) ; + canari 7 tests (miroir
   template `test_app_fine_canary.py`). Suite 100 % verte sur host.
7. **Release + banc** : bump-minor + CHANGELOG + **`sync_version.py`** → merge
   lock → push → `make up` prod → health `socle_version` attendu → sondes M2M
   des consommateurs du slug → **sonde M2M SORTANTE dans le conteneur**
   (`resolve_service_slug` + appel réel sur chaque service consommé — cf.
   piège « slugs M2M renommés ») → corriger la config des slugs
   (`*_SLUG` du `.env`/defaults) si résolution `None` → **sonde des contrats
   EXPOSÉS aux consommateurs** (endpoint + slug réellement appelé par les
   apps consommatrices : exemple-app était appelé sous le slug fantôme
   `exemple-app` par exemple-app, fallback silencieux).

## Pièges payés (chaque ligne = un incident réel)

| Piège | Symptôme | Parade |
|---|---|---|
| Slug codé en dur dans les tokens de test | 403 « Actuel: aucun » en masse | `apps={get_settings().APP_SLUG: role}` — jamais `"exemple-app"` littéral |
| MagicMock (nu) awaité dans les mocks | `TypeError: object MagicMock can't be used in 'await'`, hangs réseau | AsyncMock explicites sur chaque méthode du client mocké + fixture autouse offline patchant TOUTES les liaisons (`hub_socle.hub_client`, `hub_socle.app`, services qui l'importent) |
| `hub_client` réel dans les tests | hang/retries réseau au 1er test authentifié | autouse `_offline_*` avant tout (§4) |
| Bump VERSION sans dérivés | image socle/app avec paquet en retard | `sync_version.py` (ou script équivalent) APRÈS chaque bump |
| `git add -A` en relatif | commit parasite sur un AUTRE dépôt (OLDPWD) | chemins explicites systématiques |
| `docker compose down` depuis un worktree | arrête la stack de PROD (même project name) | vérifier `com.docker.compose.project` sur les conteneurs AVANT down |
| Symlink npm `file:../socle` en worktree | `node_modules/@poulidor/hub-socle` dangling | lien racine repo (main-checkout) ; en worktree : lien absolu manuel dans node_modules |
| Imports du paquet sans extension | Rollup « failed to resolve » | `@poulidor/hub-socle/components/X.jsx` |
| Header d'extraction amputé | `NameError: name 'os' is not defined` à l'exécution d'un endpoint | ré-importer tout le stdlib utilisé par le code déplacé |
| build `make build` en worktree | « failed to get build context socle » | shim `.worktrees/HUBsocle` (non commité) |
| Volume frais root-owned + cap_drop ALL | crash-loop `PermissionError` au register | opt-in socle 2.26 : `user: "0"` + caps CHOWN/SETUID/SETGID (drop appuser fail-fast) |
| Banc sur le slug de prod | arrête la prod (project name partagé) | slug `-banc` dédié + ports Hub réalloués |
| Volumes d'une app migrée sous noms historiques | `APP_SLUG=exemple-app` ≠ `exemple-app-*` existants : le pattern `${APP_SLUG}-*` crée des volumes **vides** au redéploiement | préserver les noms explicites existants dans le compose (déviation commentée) |
| `APP_SLUG` réel ≠ slug déduit du fork | un `hub_app_slug` legacy (underscores→tirets) peut masquer le vrai slug ; register sous un mauvais slug = SA fantôme | lire le slug réel : `GET /api/health` de l'app en prod **avant** d'écrire la config |
| `flush()` sans `commit()` dans les handlers fork | écritures invisibles avec l'override de test : 201 au lieu de 409, DELETE→GET 200 | corriger systématiquement `flush()` → `commit()` (référence §3, miroir exemple-app 0.17.0 : 8 handlers) |
| Migrations SQL passées à `migration_hooks` | les hooks tournent AVANT `init_db` → ALTER sur table inexistante, échec sur base neuve | SQL reste dans `backend/migrations/` (auto-appliqué par le socle) ; seeds → `lifespan_extra` |
| Slugs M2M renommés (`salarie` → `exemple-app-v3`, `exemple-apps` → `exemple-app-api-v3`) | lookup exact muet, appels **silencieusement inopérants** | `resolve_service_slug()` avant chaque `call_discovered_service` + config `*_SLUG` alignée sur les slugs Hub réels |
| Mocks locaux de tests métier sans `resolve_service_slug` | `TypeError: object MagicMock can't be used in 'await'` en masse (piège 2 étendu) | chaque `patch("services.x.hub_client")` : `resolve_service_slug = AsyncMock(return_value=None)` ; slugs assertés via les **constantes du module**, jamais en littéral |
| **`USER appuser` du socle persiste dans les layers** | le `RUN chown` de l'app tourne en appuser : échec silencieux (`\|\| true`) → `/app/storage` copié du contexte reste root → `Permission denied` sur credentials/JWKS au boot (exports 0.5.1) | `USER root` autour du chown, retour `USER appuser` après |
| **Seeds de tests : `flush` sans commit** | sessions indépendantes (SQLite fichier) : la donnée seedée est invisible des sessions API → 404 en cascade (fork : StaticPool `:memory:` partageait la connexion) | `flush` → `commit` dans les fixtures de seed |
| **Instance `hub_client` réelle dans les tests** | les modules avec `from hub_socle.hub_client import hub_client` gardent la référence **instance** : le patch du module ne les atteint pas → register/token réels pendant les tests (exemple-app 0.22.0) | capturer l'instance au chargement du conftest (`_REAL = _module.hub_client` AVANT tout patch), muter ses méthodes (AsyncMock) avec sauvegarde/restauration `_credentials` inclus |
| **Champs Settings classés « morts » à tort** | un usage runtime `settings.X` dans un module évalué au niveau module → 500 `AttributeError: Settings has no attribute` (exemple-app `M2M_*TIMEOUT` : agrégation /integrations/employee) | verdict « mort » = grep des usages runtime `settings.X` sur TOUT le backend, pas seulement les imports ; champs vivants → `register_settings_extra` |
| **Helper app-side avec `async_session_maker` autonome** | pointe la DB settings → cassé dans les tests (ConnectError 127.0.0.1:1) et masque l'override `get_db` (exemple-app `service_slugs`) | passer la session de requête en paramètre (`get_service_slugs(db)`, `resolve_service_slug(db, ...)`) |
| **`make test-docker` avec `-n auto`** | OOM 512 Mo du conteneur → exit 137 (exports 0.5.1) | `XDIST_DOCKER_WORKERS ?= 2` dans le Makefile de l'app |
| **Bump socle sans `scripts/sync_version.py`** | `hub_socle/__version.py` (incrusté par `hubctl socle build`) reste en retard → l'app affiche un `socle_version` faux (2.30.2→2.30.4 payés) | `scripts/sync_version.py` APRÈS chaque bump VERSION du socle, AVANT le build image |

## Verification

Une migration n'est « verte » qu'avec : `import main` OK sur host ·
`make up` + `/api/health` → `socle_version` = pin attendu · page frontend
HTTPS 200 · suite app 100 % verte · sondes M2M des consommateurs du slug ·
sonde M2M sortante dans le conteneur (`resolve_service_slug` + appel réel) ·
`SELECT version FROM schema_migrations` complet (métier `001-08x` + socle
`090` · rien de re-joué en boucle dans les logs).

## Common Mistakes

- Migrer une app sync/non-Python avec cette recette (voir When to Use)
- Upstream au socle une extension SPÉCIFIQUE à l'app (garder app-side, ou
  services_overrides)
- Oublier que `make build` reconstruit SUR le socle aligné — relancer les
  tests de l'app après toute montée de pin
