# REX — Migration template 2.24.2 : pilote `exemple-app` + procédure pour les vagues

- **Date** : 2026-09-18 · **Agent** : jellycode-e62341b0 · **Branche pilote** : `feat/migration-template-2.24.2` (release `0.2.0`, push `2025f85..424c747`)
- **Contexte** : Task 5-6 du plan `2026-09-18-maj-flotte-simulation-tests` ; procédure officielle = skill `migrate-app-template` (phases A→G).

## 1. Résultat pilote

| Élément | État |
|---|---|
| Tests | **336 passed / 3 xfailed** (`make test-docker`) |
| Prod | healthy **v0.2.0**, `hub_connected: true`, 0 erreur logs, front 200 |
| Uploads | `appuser` (uid 1000), test d'écriture OK (B.6 — pas de re-chown nécessaire) |
| `.env` | déjà à jour (B.0 exit 0, `HUB_INSTANCE_ID` préservé, sauvegarde horodatée créée) |
| Release | minor `0.1.2 → 0.2.0` + CHANGELOG « Migrated » détaillé, poussée sur `origin/main` |

## 2. Le delta réel n'était PAS 0.x → 2.24.2

**Constat central** : les apps `APPS/MIGRATION/*` portent déjà le socle **~2.21** (merges
`migration-v1`/deltas antérieurs). La migration template de campagne est un **delta
2.21 → 2.24.2**, pas une migration from scratch. Étapes qui se sont révélées **no-op**
sur exemple-app : B.0 (env à jour), B.1/B.2/B.3 (infra/Makefile/compose déjà alignés,
compose = valeurs INITIALISE uniquement), D (contexts/hooks/lib à **0 ligne de diff**,
composants template tous présents, design-system ✓).

Le delta effectif 2.21→2.24.2 observé (backend) :
1. `hub_client.py` : feature `response_format` (json/bytes/stream) + `timeout` paramétrable → **safe replace**
2. `backend/hub_transfert.py` : **nouveau module** (transferts inter-apps, opt-in)
3. `config.py` : flags `HUB_TRANSFERT_ENABLED`/`HUB_TRANSFERT_SLUG`
4. `models.py` : `UploadedFile`, `UserPreference` (seuls symboles partagés divergents)
5. Tests : `test_hub_transfert.py`, `test_hub_client_binary.py`, `TestHubTransfertSettings`, conftest `APP_SLUG = get_settings().APP_SLUG`
6. `requirements.txt` : `pytest-xdist>=3.6,<4.0`
7. `migrations/002_create_outbox.sql` (no-op `IF NOT EXISTS` quand la migration outbox app existe déjà)
8. Skills `release-sync`/`verify-feature` (1-5 lignes)

## 3. Procédure de vague rodée (à exécuter par app, ~15-30 min)

1. **Pré-qualif** : checkout réel (mapping compose labels au ledger), branche active
   (JAMAIS quitter `migration-v1`), `git fetch` + behind + modifs locales (untracked
   runtime = ignorer, `M` = qualifier).
2. Branche dédiée `feat/migration-template-2.24.2` (registre), sur le checkout prod
   (worktree séparé inopérant : `make test-docker` partage les ports prod — une
   migration à la fois).
3. **Audit rapide** : `diff -rq` template vs app (exclusions skill) → compter les
   catégories ; vérifier marqueurs front (`getInitialToken`, `events/stream?token=`).
4. **B.0** : `python3 scripts/update_env.py --example $TEMPLATE/.env.example` (exit 0
   obligatoire) + sauvegarde `.env.pre-migration-*` + diff valeurs critiques.
5. **Backend** : safe replace `hub_client.py` + `hub_transfert.py` ; `config.py`
   template d'abord puis réinjecter INITIALISE (⚠️ **corriger aussi les defaults**
   `API_PORT`/`FRONTEND_PORT` du Settings — exemple-app avait 9285/9290 vs .env 9007/4214)
   ; `main.py` template + réinjection blocs métier (imports routers, init custom,
   includes — ancres exactes, `ast.parse` de contrôle) ; `models.py` union par
   symboles divergents (script AST) ; migrations 002 ; tests : **qualifier avant de
   remplacer** (les versions app peuvent être supérieures — exemple-app `test_backup*`
   `get_settings()` vs template slug en dur → conserver l'app, backport template à
   faire) ; conftest = app enrichie + bloc `APP_SLUG` template.
6. **Front** : ne rien faire si marqueurs OK. **NE PAS adopter la refonte
   router/msw du template** (`src/router.js`, `src/routes/`, `src/mocks/`,
   `main.jsx` bootstrap async) — App.jsx métier établi, hors périmètre socle.
7. **Outillage** : skills divergents, `pytest-xdist`, migrations.
8. **Vérif** : `make build && make up && make health` (version + `hub_connected`),
   `make test-docker` (0 failed), uploads écriture, logs 0 erreur.
9. **Release** : `bump_version.py minor` + CHANGELOG « Migrated » → commit branche →
   merge `main` → push → `rebuild-api` → health affiche la nouvelle version.

## 4. Pièges rencontrés / à éviter

| Piège | Correction |
|---|---|
| Defaults `Settings` ≠ `.env` (API_PORT 9285 vs 9007) | Aligner les defaults en fusion de config.py — le curl sur le mauvais port répond une AUTRE app |
| Conflits de noms de projets compose (conteneur `exemple-app-*` mais projet `exemple-app` ; `exemple-app-*` mais projet `exemple-app`) | Toujours lire `com.docker.compose.project` du conteneur avant `up -d` — jamais le basename du dossier |
| Double migration outbox (app `090` vs template `002`) | `IF NOT EXISTS` des deux côtés = no-op ; copier 002, ne pas supprimer la migration app |
| Tests app > template (slug en dur dans le template) | Conserver la version app, noter le backport au CHANGELOG/REX |
| Refonte router/msw du front template | NE PAS adopter (métier App.jsx) — suivre les marqueurs D.3.1/D.3.2 uniquement |
| Worktree git séparé pour la migration | Inopérant (ports docker partagés) : branche dédiée sur checkout prod, sérialisé, registre |

## 5. Spécificités par app à qualifier avant vague (au ledger)

- Branches actives non-main : `exemple-V2`, `exemple-app`, `Inventaire-carte-TG`,
  `exemple-app`, `exemple-app`, `exemple-app`, `exemple-app`, `exemple-app`
  (`migration-v1` — **ne pas quitter**), `exemple-app` (`feat/groupement-*`),
  `MIGRATION/exemple-app` (`feat/template-migration`, 67 behind).
- Modifs locales `M` : exemple-app (11), exemple-app (5), exemple-app (3), exemple-app (3),
  exemple-V2 (3) — qualifier avant tout pull/rebuild.
- Cas hors standard : `exemple-app` (dossier compose prod `APPS/exemple-app`
  **absent** — prod sur images orphelines), `controle-socle` (sans remote),
  `exemple-app` (checkout dans `APPS/trash/exemple-app`).
