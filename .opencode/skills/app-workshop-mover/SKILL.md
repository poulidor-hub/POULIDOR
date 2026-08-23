---
name: app-workshop-mover
description: Utiliser pour le cycle Workshop (mode DEV) — mettre une app en atelier (sandbox avec clone DB), tester une montée de version (--maj), déployer en prod (--prod) ou supprimer l'atelier. L'atelier tourne via un 2e projet docker compose (-p X-ws) à côté de la prod, piloté par APPS/X/.workshop.env. La prod reste en place pendant l'atelier. Utiliser quand on demande "mettre en atelier", "mettre à jour l'atelier", "tester une montée de version", "déployer en prod", "supprimer l'atelier", "mode dev", ou pour implémenter ces actions dans hubctl.
---

# app-workshop-mover

## Overview

Le Workshop (mode DEV uniquement) fait tourner une **sandbox à côté de la prod**
sans déplacer les fichiers. L'app de production `APPS/X` reste **en place**
(jamais supprimée) pendant qu'un 2e projet docker compose nommé `X-ws`
tourne avec un clone de sa DB.

- **[→] Mettre en atelier** : `./hubctl atelier X` clone la DB de prod (`X-postgres-data`
  → `X-ws-postgres-data`), alloue 2 ports libres (API `[10000-10499]`, frontend
  `[5200-5699]`) + un subnet `/24` dédié (pool `198.51.100.0/24`..`198.51.100.10/24`),
  écrit `APPS/X/.workshop.env`, démarre le projet `X-ws`.
- **[↻] MAJ de l'atelier** : `./hubctl atelier X --maj [--ref R]` — teste une montée
  de version sur le clone (git fetch + checkout + rebuild `-ws`, migrations
  rejouées au boot).
- **[⇧] Déployer en prod** : `./hubctl atelier X --prod` — déploie `origin/main`
  validé en atelier, puis supprime l'atelier.
- **[×] Supprimer l'atelier** : re-`./hubctl atelier X` (menu 4 choix) → choix 3 —
  `docker compose -p X-ws down -v` + suppression de `.workshop.env`.

**Règle d'or** : la prod `APPS/X` n'est jamais supprimée, et sa DB
(`X-postgres-data`) jamais touchée. Le code de l'atelier vit dans le même dossier
`APPS/X/` (working tree **partagé** avec la prod) : il n'est modifié que via
`./hubctl atelier X --maj` (tracé `WS_REF`/`WS_COMMIT` + rollback git), jamais
par des `git pull`/`git checkout` manuels. Seule la DB est clonée ; ports et
subnet diffèrent.

## When to Use

- "Mets exemple-app-2 en atelier pour travailler dessus" → `./hubctl atelier exemple-app-2`
- "Teste la montée en version d'exemple-app-2" → `./hubctl atelier exemple-app-2 --maj`
- "Déploie exemple-app-2 en prod après validation atelier" → `./hubctl atelier exemple-app-2 --prod`
- "Supprime l'atelier d'exemple-app-2" → re-`./hubctl atelier exemple-app-2` puis choix 3
- Implémenter des évolutions du cycle atelier dans `hubctl` (`actions.py`)

**Ne PAS utiliser pour :**
- Créer une nouvelle app → `scripts/create_app.sh` / skill `create-hub-app`
- Déployer une MAJ code-only en prod (hors atelier) → `./hubctl update`
- Redémarrer une app → `make restart` dans `APPS/X`

## État de l'implémentation (important)

| Fonctionnalité | Statut | Commande réelle |
|---|---|---|
| Mettre en atelier (clone DB) | ✅ Implémenté | `./hubctl atelier X` |
| MAJ de l'atelier (test montée de version) | ✅ Implémenté | `./hubctl atelier X --maj [--ref R]` |
| Déploiement atelier → prod (`ship`) | ✅ Implémenté | `./hubctl atelier X --prod` |
| Supprimer l'atelier | ✅ Implémenté (menu) | `./hubctl atelier X` → choix 3 |
| Copie DB atelier → prod (`--copy-db`) | ❌ Non implémenté (non voulu) | — |
| Multi-slug (`work X,Y,Z`) | ❌ Non implémenté | un seul slug à la fois |
| Blue-green deploy (`deploy`) | ❌ Non implémenté | — |

> Les anciennes documentations (specs `docs/superpowers/specs/2026-07-*`, plans
> historiques, anciens README) référencent les commandes `work`, `ship`,
> `deploy`, multi-slug, `--copy-db` et blue-green. **Aucune de ces commandes
> n'existe dans le parser actuel** (`hubctl_src/hubctl_cli/__main__.py`) :
> le cycle complet est porté par le subparser `atelier` (création, `--maj`,
> `--prod`, suppression via menu). Les specs sont conservées comme archives
> de design.

## Prérequis (non négociables)

| Prérequis | Vérification |
|-----------|-------------|
| Docker running | `docker info > /dev/null 2>&1` |
| `APPS/X` existe | `test -d APPS/X` |
| Hub opérationnel | `./hubctl health` ou `curl http://localhost:8000/api/health` |
| Pour supprimer : `APPS/X/.workshop.env` existe | `test -f APPS/X/.workshop.env` |

## Action `[→]` Mettre en atelier

Implémentée par `_create_workshop` (`actions.py`), appelée via
`action_atelier` quand `APPS/X/.workshop.env` est absent (et sans flags).

```
1. CHECK    Docker + Hub + APPS/X existe
2. PORTS    Alloue API_PORT dans [10000-10499], FRONTEND_PORT dans [5200-5699]
3. SUBNET   Alloue le 1er /24 libre du pool [198.51.100.0/24 .. 198.51.100.10/24]
            (overlap vérifié contre les réseaux docker existants + ateliers)
4. ENV      Écrit APPS/X/.workshop.env : APP_SLUG, API_PORT, FRONTEND_PORT,
            FRONTEND_HTTPS_PORT, WS_REF, WS_COMMIT, APP_SUBNET (7 clés)
5. VOLUME   docker volume create X-ws-postgres-data
            + alpine cp -a /from/. /to/ depuis X-postgres-data
6. BUILD-UP docker compose -p X-ws -f APPS/X/docker-compose.yml build (timeout 600 s)
            + up -d — .workshop.env injecté dans l'environnement,
            APP_VERSION injectée depuis APPS/X/VERSION
7. HEALTH   curl http://localhost:{API_PORT_atelier}/api/health (timeout 30 s)
            └ échec → down atelier + rm .workshop.env + rm volume (rollback)
```

La prod `APPS/X` **n'est pas stoppée** : grâce au subnet dédié (`APP_SUBNET`),
prod et atelier **cohabitent** sur les apps du template courant (subnet épinglé
dans leur compose). `WS_REF`/`WS_COMMIT` tracent le code testé ; si `APPS/X`
n'a pas de remote git, l'atelier est créé avec `WS_REF=n/a` (`--maj`/`--prod`
seront refusés — recréer l'atelier après mise en place du remote).

## Action `[×]` Supprimer l'atelier

Implémentée par `_remove_workshop` (`actions.py`), atteinte via le **menu 4 choix**
de `action_atelier` (choix 3) quand `APPS/X/.workshop.env` existe — ou appelée
automatiquement par `_ship_workshop` à la fin d'un `--prod` réussi.

```
1. MENU     ./hubctl atelier X → 4 choix : 1) mettre à jour  2) déployer en prod
            3) supprimer  4) annuler — précédé de l'état :
            « teste WS_REF @ WS_COMMIT[:8] (code VERSION) »
2. DOWN-V   docker compose -p X-ws down -v   ← SEUL usage légitime de -v dans le cycle
3. UNLINK   rm APPS/X/.workshop.env
```

C'est le **seul** endroit du cycle où `down -v` est permis (destruction
explicite du volume cloné de la sandbox). Partout ailleurs, `down -v` est
INTERDIT ( risquerait de destroy la DB prod `X-postgres-data`).

## Cycle de test de mise à jour (implémenté)

```bash
./hubctl atelier X                # 1. créer l'atelier (clone DB + 2e instance -ws, build 600 s)
./hubctl atelier X --maj          # 2. tester origin/main sur le clone (migrations rejouées, build 600 s)
./hubctl atelier X --maj --ref feat/xyz   # (option) tester une branche candidate avant merge
# …validation manuelle de l'app sur les ports atelier…
./hubctl atelier X --prod         # 3. déployer origin/main validé + supprimer l'atelier

./hubctl --dry-run atelier X --maj   # (option) simuler — --dry-run est un flag GLOBAL,
                                      # il se place AVANT le subcommand (la forme
                                      # « atelier X --dry-run » est rejetée par argparse)
```

- `--maj` exige un working tree propre (`git status` vide, pas de commits non poussés).
- `--prod` déploie UNIQUEMENT `origin/main` : refuse si l'atelier teste un autre ref
  (mergez via release-on-main d'abord), ou si main a avancé depuis le test
  (relancez `--maj` et revalidez).
- Échec `--maj` : rollback git (l'atelier reste sur l'ancien commit) ; la DB du clone
  peut être migrée → recréer l'atelier pour repartir du clone propre.
- Échec `--prod` : rollback prod, **atelier conservé** pour diagnostic.
- Interruption (Ctrl-C) : rollback best-effort ; récupération manuelle via `git reflog`
  et `WS_COMMIT` dans `.workshop.env`.

> **DB préservée** : ce cycle ne touche jamais au volume `X-postgres-data` de prod.
> Les migrations sont rejouées sur le clone au boot (alembic via `make up`) ;
> c'est `--prod` qui redémarre ensuite la prod sur le nouveau code.

> **Garde grossière** : le health check du ship (`/api/health`) ne vérifie pas la DB
> sur le template courant (répond « healthy » même DB down). La validation manuelle
> sur l'atelier reste donc la vraie porte de qualité avant `--prod`.

## Slug renaming

Le slug atelier est `{slug}-ws`. Il est piloté par `APP_SLUG` dans `.workshop.env`
(et NON dans `.env` — `.env` reste `{slug}` pour la prod). Le `-ws` pilote :
- `container_name` (nginx, db, api ont `-ws` en suffixe)
- nom du volume (`X-ws-postgres-data`)
- entrypoint du conteneur DB

`APP_SUBNET` (7e clé, ajoutée par cette release) épingle le subnet `/24` du
réseau du projet `-ws` : c'est ce qui permet à prod et atelier de cohabiter sur
les apps du template courant. Les ateliers créés avant cette release peuvent ne
pas avoir cette clé — recréer l'atelier pour en bénéficier.

## Quick Reference

| Ressource | Emplacement |
|-----------|------------|
| Code prod | `APPS/X/` |
| Override atelier | `APPS/X/.workshop.env` (généré par `hubctl atelier`) |
| Projet docker compose atelier | `X-ws` (via `-p X-ws`) |
| Slug atelier | `{slug}-ws` |
| Subnet atelier | 1er `/24` libre du pool `198.51.100.0/24`..`198.51.100.10/24` (clé `APP_SUBNET`, overlap-check) |
| Volume DB prod | `X-postgres-data` |
| Volume DB atelier | `X-ws-postgres-data` |
| Ports atelier | API `[10000-10499]`, frontend `[5200-5699]` |
| Ref testé en atelier | `WS_REF` + `WS_COMMIT` dans `.workshop.env` (lignes d'état du menu et garde-fous `--prod`) |
| Marqueur atelier actif | `APPS/X/.workshop.env` existe |
| Health endpoint | `http://localhost:{API_PORT}/api/health` |
| Code hubctl | `hubctl_src/hubctl_cli/actions.py::_create_workshop`, `_update_workshop`, `_ship_workshop`, `_remove_workshop`, `action_atelier` |

### Variables `.workshop.env` (7 clés)

| Clé | Rôle |
|-----|------|
| `APP_SLUG` | `{slug}-ws` — pilote le projet compose, les conteneurs et le volume |
| `API_PORT` / `FRONTEND_PORT` / `FRONTEND_HTTPS_PORT` | ports atelier alloués dans les plages dédiées |
| `WS_REF` / `WS_COMMIT` | ref + commit du code testé (tracing du cycle `--maj`/`--prod`) ; `n/a` si `APPS/X` n'a pas de remote git |
| `APP_SUBNET` | subnet `/24` dédié du réseau `-ws` (pool `10.210.x`) — depuis cette release ; recréer un atelier legacy pour l'obtenir |

### Commandes

```bash
./hubctl atelier X                  # [→] créer l'atelier (si .workshop.env absent)
                                    # menu 4 choix si présent : maj / prod / supprimer / annuler
./hubctl atelier X --maj [--ref R]  # MAJ atelier : git fetch + checkout origin/main (ou R) + rebuild -ws
./hubctl atelier X --prod           # déployer origin/main validé en prod + supprimer l'atelier
./hubctl --dry-run atelier X --maj  # simuler — --dry-run est GLOBAL (avant le subcommand)
```

### Commandes Docker brutes (debug)

```bash
# Lister les ateliers actifs
for f in APPS/*/.workshop.env; do echo "→ $(dirname "$f")"; done

# Voir les conteneurs atelier
docker ps --filter "name=-ws" --format "{{.Names}}\t{{.Status}}"

# Stop un atelier sans le supprimer
docker compose -p X-ws -f APPS/X/docker-compose.yml stop

# Cloner un volume manuellement (debug)
docker volume create X-ws-postgres-data
docker run --rm -v X-postgres-data:/from:ro -v X-ws-postgres-data:/to alpine cp -a /from/. /to/
```

## Implémentation dans hubctl

### Point d'entrée

`hubctl_src/hubctl_cli/__main__.py:52` déclare le subparser :
```python
atelier_parser = sub.add_parser("atelier", help="Creer, mettre a jour, deployer en prod ou supprimer l'atelier d'une app")
atelier_parser.add_argument("app", help="Slug de l'app")
# groupe mutuellement exclusif : --maj / --prod ; + --ref REF (avec --maj seulement)
# --dry-run est un flag GLOBAL du parser principal (pas du subparser atelier)
```

### Fonctions helpers dans `actions.py`

- `_ws_project(app_slug) -> str` → `"X-ws"`
- `_ws_env_path(app_slug) -> Path` → `APPS/X/.workshop.env`
- `_ws_exists(app_slug) -> bool`, `_ws_read_env`, `_ws_compose_env`
- Allocation : `_ws_used_ports()`, `_ws_used_subnets()`, `_find_free_subnet()` (pool `10.210.x.0/24`)
- Git (cycle maj/ship) : `_ws_git_state`, `_ws_resolve_ref`, `_ws_git_restore`
- `_create_workshop(console, app_slug, *, dry_run=False) -> bool` (ligne ~2115)
- `_update_workshop(console, app_slug, ref="main", *, dry_run=False) -> bool` (ligne ~1852)
- `_ship_workshop(console, app_slug, *, dry_run=False) -> bool` (ligne ~1996)
- `_remove_workshop(console, app_slug, *, dry_run=False) -> bool` (ligne ~2297)
- `action_atelier(console, app_slug, *, dry_run=False, maj=False, prod=False, ref=None) -> None` (ligne ~2321) : dispatch flags → création → menu 4 choix

### Réutilisation de l'existant

| Besoin | Code existant |
|--------|--------------|
| Shell + dry-run | `utils.run_shell()` |
| Health check | `_health_check(target, console, timeout, port_override)` |
| `.env` read/write | `env_manager.read_env()` / `write_env()` |
| Liste apps | `hub_state.get_apps()` / `get_workshop_apps()` |
| Détection mode dev | `hub_state.auto_detect_mode()` (dev si au moins 1 `.workshop.env`) |
| Confirmation TUI | `widgets.confirm()` |

## Common Mistakes

| Erreur | Conséquence | Correction |
|--------|-------------|------------|
| `docker compose down -v` sur la prod | **Destruction irréversible de la DB prod** | `-v` UNIQUEMENT via `./hubctl atelier X` (menu → supprimer) ; jamais sur le projet default |
| Éditer `.env` au lieu de `.workshop.env` pour l'atelier | L'atelier écrase la config prod | L'atelier lit `.env` (commun) + override par `.workshop.env` (spécifique atelier) |
| Lancer `git pull`/`git checkout` manuels dans `APPS/X` pendant que l'atelier tourne | Code modifié à chaud pour l'atelier ET la prod (working tree partagé), sans tracing | Utiliser `./hubctl atelier X --maj` (hygiène + rollback + tracing `WS_REF`/`WS_COMMIT`) |
| Confondre "atelier actif" et "mode dev" | Le mode dev est global au parc, l'atelier est par-app | Mode dev = `auto_detect_mode()` retourne "dev" si ≥1 atelier actif |
| Supprimer `APPS/X/.workshop.env` à la main | Atelier zombie (conteneurs tournent sans override) | Toujours passer par `./hubctl atelier X` pour cleanup propre |

## Red Flags — STOP et corriger

- "Le déploiement atelier→prod se fait via la commande `ship`" → **Faux.** `ship` n'existe pas (archive de spec). Le déploiement implémenté est `./hubctl atelier X --prod` (déploie `origin/main` validé puis supprime l'atelier ; rollback prod avec atelier conservé en cas d'échec).
- "L'atelier copie la DB prod par défaut" → **Faux.** L'atelier clone la DB dans un nouveau volume `X-ws-postgres-data`. La prod `X-postgres-data` n'est jamais touchée.
- "`down -v` pour être sûr de nettoyer" → **Faux.** Sauf dans `_remove_workshop`, c'est une destruction de volume. Sur la prod = perte de DB.
- "On peut lancer plusieurs ateliers en une commande (`work X,Y,Z`)" → **Faux.** Un slug à la fois. Le multi-slug est documenté dans les specs historiques mais pas implémenté.
- "L'atelier déplace les fichiers vers un dossier dédié (schéma legacy)" → **Faux.** Schéma legacy abandonné. L'atelier vit dans `APPS/X/` avec override `.workshop.env`.
