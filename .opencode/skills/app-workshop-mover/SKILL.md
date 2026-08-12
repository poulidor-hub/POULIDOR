---
name: app-workshop-mover
description: Utiliser pour le cycle Workshop (mode DEV) — mettre une app en atelier (sandbox avec clone DB) ou supprimer l'atelier. L'atelier tourne via un 2e projet docker compose (-p X-ws) à côté de la prod, piloté par APPS/X/.workshop.env. La prod reste en place (stopée) pendant l'atelier. Utiliser quand on demande "mettre en atelier", "supprimer l'atelier", "mode dev", ou pour implémenter ces actions dans hubctl.
---

# app-workshop-mover

## Overview

Le Workshop (mode DEV uniquement) fait tourner une **sandbox à côté de la prod**
sans déplacer les fichiers. L'app de production `APPS/X` reste **en place**
(stopée, jamais supprimée) pendant qu'un 2e projet docker compose nommé `X-ws`
tourne avec un clone de sa DB.

- **[→] Mettre en atelier** : `./hubctl atelier X` clone la DB de prod (`X-postgres-data`
  → `X-ws-postgres-data`), alloue 2 ports libres (API `[10000-10499]`, frontend
  `[5200-5699]`), écrit `APPS/X/.workshop.env`, démarre le projet `X-ws`.
- **[×] Supprimer l'atelier** : re-`./hubctl atelier X` (toggle interactif) —
  `docker compose -p X-ws down -v` + suppression de `.workshop.env`.

**Règle d'or** : la prod `APPS/X` n'est jamais supprimée ni modifiée pendant
l'atelier. Le code de l'atelier vit dans le même dossier `APPS/X/`, seule la DB
est clonée et les ports diffèrent.

## When to Use

- "Mets exemple-app-2 en atelier pour travailler dessus" → `./hubctl atelier exemple-app-2`
- "Supprime l'atelier d'exemple-app-2" → re-`./hubctl atelier exemple-app-2` puis choix "Supprimer"
- Implémenter des évolutions du cycle atelier dans `hubctl` (`actions.py`)

**Ne PAS utiliser pour :**
- Créer une nouvelle app → `scripts/create_app.sh` / skill `create-hub-app`
- Déployer une MAJ code-only en prod (hors atelier) → `./hubctl update`
- Redémarrer une app → `make restart` dans `APPS/X`

## État de l'implémentation (important)

| Fonctionnalité | Statut | Commande réelle |
|---|---|---|
| Mettre en atelier (clone DB) | ✅ Implémenté | `./hubctl atelier X` |
| Supprimer l'atelier | ✅ Implémenté (toggle) | re-`./hubctl atelier X` + prompt |
| Déploiement atelier → prod (`ship`) | ❌ **Non implémenté en CLI** | manuel : `cd APPS/X && git pull && make build && make up` |
| Copie DB atelier → prod (`--copy-db`) | ❌ Non implémenté | — |
| Multi-slug (`work X,Y,Z`) | ❌ Non implémenté | un seul slug à la fois |
| Blue-green deploy (`deploy`) | ❌ Non implémenté | — |

> Les anciennes documentations (specs `docs/superpowers/specs/2026-07-*`, plans
> historiques, anciens README) référencent les commandes `work`, `ship`,
> `deploy`, multi-slug, `--copy-db` et blue-green. **Aucune de ces commandes
> n'existe dans le parser actuel** (`hubctl_src/hubctl_cli/__main__.py`).
> Seul `atelier` est exposé. Les specs sont conservées comme archives de design
> (intention valide, implémentation à venir).

## Prérequis (non négociables)

| Prérequis | Vérification |
|-----------|-------------|
| Docker running | `docker info > /dev/null 2>&1` |
| `APPS/X` existe | `test -d APPS/X` |
| Hub opérationnel | `./hubctl health` ou `curl http://localhost:8000/api/health` |
| Pour supprimer : `APPS/X/.workshop.env` existe | `test -f APPS/X/.workshop.env` |

## Action `[→]` Mettre en atelier

Implémentée par `_create_workshop` (`actions.py`), appelée via
`action_atelier(console, app_slug, dry_run)` quand `APPS/X/.workshop.env` est absent.

```
1. CHECK    Docker + Hub + APPS/X existe
2. PORTS    Alloue API_PORT dans [10000-10499], FRONTEND_PORT dans [5200-5699]
3. ENV      Écrit APPS/X/.workshop.env : {APP_SLUG: X-ws, *_PORT, *_HTTPS_PORT}
4. VOLUME   docker volume create X-ws-postgres-data
            + alpine cp -a /from/. /to/ depuis X-postgres-data
5. BUILD-UP docker compose -p X-ws -f APPS/X/docker-compose.yml --env-file .workshop.env build
            + up -d
6. HEALTH   curl http://localhost:{API_PORT_atelier}/api/health
            └ échec → down atelier + rm .workshop.env + rm volume (rollback)
```

La prod `APPS/X` **n'est pas stoppée** explicitement par `action_atelier` — les
deux instances tournent en parallèle sur des ports différents (pas de collision).

## Action `[×]` Supprimer l'atelier

Implémentée par `_remove_workshop` (`actions.py`), appelée via
`action_atelier(console, app_slug, dry_run)` quand `APPS/X/.workshop.env` existe.
Prompt interactif 2 choix (supprimer / annuler).

```
1. CONFIRM   prompt interactif (annuler par défaut)
2. DOWN-V    docker compose -p X-ws down -v   ← SEUL usage légitime de -v dans le cycle
3. UNLINK    rm APPS/X/.workshop.env
```

C'est le **seul** endroit du cycle où `down -v` est permis (destruction
explicite du volume cloné de la sandbox). Partout ailleurs, `down -v` est
INTERDIT ( risquerait de destroy la DB prod `X-postgres-data`).

## Déploiement atelier → prod (non implémenté en CLI)

Lorsque le code testé en atelier est prêt pour la prod, faire manuellement :

```bash
# 1. Committed + poussé depuis l'atelier (le code est partagé avec APPS/X/)
cd APPS/X
git status                   # vérifier que tout est committed
git push                     # pousser vers le dépôt distant

# 2. Supprimer l'atelier (libère les ports + nettoie)
./hubctl atelier X           # toggle → "Supprimer"

# 3. Mettre à jour la prod
git pull --recurse-submodules
make build && make up

# 4. Health check
make health
```

> **DB préservée** : ce cycle ne touche jamais au volume `X-postgres-data` de prod.
> Si une migration DB doit être appliquée, c'est `make up` qui s'en charge au
> démarrage via alembic.

## Slug renaming

Le slug atelier est `{slug}-ws`. Il est piloté par `APP_SLUG` dans `.workshop.env`
(et NON dans `.env` — `.env` reste `{slug}` pour la prod). Le `-ws` pilote :
- `container_name` (nginx, db, api ont `-ws` en suffixe)
- nom du volume (`X-ws-postgres-data`)
- entrypoint du conteneur DB

## Quick Reference

| Ressource | Emplacement |
|-----------|------------|
| Code prod | `APPS/X/` |
| Override atelier | `APPS/X/.workshop.env` (généré par `hubctl atelier`) |
| Projet docker compose atelier | `X-ws` (via `-p X-ws`) |
| Slug atelier | `{slug}-ws` |
| Volume DB prod | `X-postgres-data` |
| Volume DB atelier | `X-ws-postgres-data` |
| Ports atelier | API `[10000-10499]`, frontend `[5200-5699]` |
| Marqueur atelier actif | `APPS/X/.workshop.env` existe |
| Health endpoint | `http://localhost:{API_PORT}/api/health` |
| Code hubctl | `hubctl_src/hubctl_cli/actions.py::_create_workshop`, `_remove_workshop`, `action_atelier` |

### Commandes

```bash
./hubctl atelier X           # [→] créer l'atelier (si .workshop.env absent)
                             # [×] prompt de suppression (si .workshop.env présent)
./hubctl atelier X --dry-run # simuler sans rien exécuter
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
atelier_parser = sub.add_parser("atelier", help="Créer, déployer ou supprimer l'atelier d'une app")
atelier_parser.add_argument("app", help="Slug de l'app")
```

### Fonctions helpers dans `actions.py`

- `_ws_project(app_slug) -> str` → `"X-ws"`
- `_ws_env_path(app_slug) -> Path` → `APPS/X/.workshop.env`
- `_ws_exists(app_slug) -> bool`
- `_create_workshop(console, app_slug, *, dry_run=False) -> bool` (ligne ~1610)
- `_remove_workshop(console, app_slug, *, dry_run=False) -> bool` (ligne ~1771)
- `action_atelier(console, app_slug, *, dry_run=False) -> None` (ligne ~1795) : toggle create/remove

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
| `docker compose down -v` sur la prod | **Destruction irréversible de la DB prod** | `-v` UNIQUEMENT via `./hubctl atelier X` (toggle remove) ; jamais sur le projet default |
| Éditer `.env` au lieu de `.workshop.env` pour l'atelier | L'atelier écrase la config prod | L'atelier lit `.env` (commun) + override par `.workshop.env` (spécifique atelier) |
| Lancer `git pull` dans `APPS/X` pendant que l'atelier tourne | Code modifié à chaud pour l'atelier | Stopper l'atelier d'abord (`./hubctl atelier X` → supprimer) |
| Confondre "atelier actif" et "mode dev" | Le mode dev est global au parc, l'atelier est par-app | Mode dev = `auto_detect_mode()` retourne "dev" si ≥1 atelier actif |
| Supprimer `APPS/X/.workshop.env` à la main | Atelier zombie (conteneurs tournent sans override) | Toujours passer par `./hubctl atelier X` pour cleanup propre |

## Red Flags — STOP et corriger

- "Le déploiement atelier→prod se fait via la commande `ship`" → **Faux.** `ship` n'est pas implémenté. Cycle manuel : `git pull && make build && make up`.
- "L'atelier copie la DB prod par défaut" → **Faux.** L'atelier clone la DB dans un nouveau volume `X-ws-postgres-data`. La prod `X-postgres-data` n'est jamais touchée.
- "`down -v` pour être sûr de nettoyer" → **Faux.** Sauf dans `_remove_workshop`, c'est une destruction de volume. Sur la prod = perte de DB.
- "On peut lancer plusieurs ateliers en une commande (`work X,Y,Z`)" → **Faux.** Un slug à la fois. Le multi-slug est documenté dans les specs historiques mais pas implémenté.
- "L'atelier déplace les fichiers vers un dossier dédié (schéma legacy)" → **Faux.** Schéma legacy abandonné. L'atelier vit dans `APPS/X/` avec override `.workshop.env`.
