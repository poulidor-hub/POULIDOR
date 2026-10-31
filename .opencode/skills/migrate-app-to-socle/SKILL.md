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
   tournent AVANT `init_db`) ; **seeds → `lifespan_extra`** (tourne APRÈS
   `init_db`/`apply_migrations`) ; **auditer `flush()` sans `commit()`**
   dans les handlers d'écriture → `commit()` explicite (référence §3).
4. **Infra** : `Dockerfile.backend` = `FROM poulidor/socle-api:${SOCLE_VERSION}`
   + `COPY backend/ /app/` + `COPY VERSION` ; compose arg `SOCLE_VERSION=?` +
   `additional_contexts: socle` (frontend) ; `.env.example` +
   `APP_SOCLE_VERSION` ; Makefile + `scripts/sync_socle_version.py` (copié du
   template) appelé dans `sync-env` ; `ssl/.gitkeep` ; opt-in réparation
   volumes root (`user: "0"` + caps CHOWN/SETUID/SETGID) si volumes frais ;
   **volumes/réseau d'une app migrée : préserver les noms historiques
   explicites** (jamais `${APP_SLUG}-*` si les volumes prod existent sous un
   autre nom) ; **overlay dev** : `additional_contexts` dans
   `docker-compose.dev.yml` + `COPY --from=socle` AVANT `npm install` dans
   `Dockerfile.frontend.dev` ; `.dockerignore` : exclure le symlink `socle`.
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
   (`*_SLUG` du `.env`/defaults) si résolution `None`.

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
