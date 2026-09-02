---
name: app-workshop-mover
description: Utiliser pour le cycle Workshop (mode DEV) — mettre une app en atelier (sandbox avec clone DB), déployer le code de l'atelier vers la prod via git pull (défaut, DB préservée), ou exceptionnellement écraser la DB prod (--copy-db, avancé CLI-only), et supprimer l'atelier. La prod n'est jamais supprimée pendant l'atelier (modèle sandbox + deploy). Utiliser quand on demande "mettre en atelier", "déployer l'atelier vers la prod", "shipper le code", "copier la BDD de l'atelier (--copy-db)", "supprimer l'atelier", ou pour implémenter ces actions dans hubctl.
---

# app-workshop-mover

## Overview

Le Workshop (mode DEV uniquement) suit un modèle **« sandbox + deploy »** :
l'app de production `APPS/X` reste **en place** (stopée, jamais supprimée) pendant
qu'un atelier `APP_Workshop/X-ws` sandbox tourne à côté avec un clone de sa DB.

- **`[→] Mettre en atelier`** : clone la prod (code + DB) vers `X-ws`, stoppe la prod.
- **`[←] Déployer vers la prod`** (défaut) : `git pull` code-only sur la prod, **DB intacte**.
- **`[←] --copy-db`** (avancé, CLI-only) : écrase la DB prod par celle de l'atelier (destructif).
- **`[×] Supprimer l'atelier`** : détruit la sandbox (`down -v` + backup), redémarre la prod.

**Règle d'or** : on ne touche JAMAIS à la DB de prod par défaut. La copie DB est
l'exception explicite (`--copy-db`), jamais le cycle standard.

## When to Use

- "Mets exemple-app-2 en atelier pour travailler dessus" → `[→]`
- "Déploie / shippe le code de l'atelier vers la prod" → `[←]` (git pull)
- "Copie la BDD de l'atelier vers la prod" → `[←] --copy-db` (avancé)
- "Supprime l'atelier X-ws" → `[×]`
- Implémenter ces actions dans `hubctl` (`actions.py` + `menu.py`)

**Ne PAS utiliser pour :**
- Créer une nouvelle app → `create_app.sh` / skill `create-hub-app`
- Déployer une MAJ code-only en prod (hors atelier) → `action_update()`
- Déploiement blue-green zéro-downtime → `action_deploy()`
- Redémarrer une app → `make restart`

## Prérequis (non négociables)

| Prérequis | Vérification |
|-----------|-------------|
| Mode dev actif | `test -f HUB_base/.dev-mode` (ou via hubctl) |
| Docker running | `docker info > /dev/null 2>&1` |
| `[→]` : `APPS/X` existe, `APP_Workshop/X-ws` absent | Pas d'écrasement d'atelier existant |
| `[←]` : `APPS/X` ET `APP_Workshop/X-ws` existent | La prod doit être en place pour un git pull |

**Violer un prérequis = tout arrêter.** Ne jamais contourner.

## Action `[→]` : Mettre en atelier (`action_workshop_create`)

```
1. CHECK    .dev-mode + Docker ; refuser si X-ws existe déjà
2. STOP     docker compose stop sur APPS/X   ← prod stoppée, dir + volume LAISSÉS EN PLACE
3. COPY     APPS/X → APP_Workshop/X-ws        (shutil.copytree)
4. VOLUME   X-postgres-data → X-ws-postgres-data  (clone DB, alpine cp)
5. SLUG     APP_SLUG=X → X-ws dans l'.env atelier
6. BUILD-UP atelier
7. HEALTH   atelier (via _health_check, port_override=API_PORT atelier)
             └ échec → down atelier + rmtree + RESTART prod (rollback)
```

**Pas de backup, pas de suppression de source.** La prod est stoppée mais conservée.

## Action `[←]` Défaut : Déployer code-only (`action_prod_deploy`, `copy_db=False`)

```
1. CHECK    .dev-mode + Docker ; APPS/X et APP_Workshop/X-ws doivent exister
2. GIT-HYGIÈNE (warnings non bloquants sur le dépôt atelier) :
   - changements non commités → ⚠
   - commits non poussés → ⚠ "git pull ne ramènera rien"
3. CAPTURE prev_commit = git -C APPS/X rev-parse HEAD   (pour rollback)
4. PULL     git -C APPS/X pull --recurse-submodules
5. BUILD    make -C APPS/X build
6. UP       make -C APPS/X up
7. HEALTH   _health_check(X)  └ échec → _rollback(snapshot=None) : git reset --hard + build + up
```

**La DB prod (volume `X-postgres-data`) n'est JAMAIS touchée.** Atelier conservé.

## Action `[←] --copy-db` : Écraser la DB prod (avancé, CLI-only)

⚠️ Destructif. **Jamais exposé dans le menu TUI** — uniquement `hubctl ship X --copy-db`.

```
1. CONFIRM   input() : doit taper le slug exact (gate forte)
2. STOP       prod APPS/X
3. BACKUP     volume X-postgres-data → alpine tar czf (filet de sécurité)
              └ si rc != 0 : backup_path=None (rollback skippera la restore)
4. OVERWRITE  docker volume rm X-postgres-data + create + alpine cp (X-ws → X)
5. PULL       git -C APPS/X pull (migrations cohérentes avec la DB migrée)
6. BUILD-UP   prod
7. HEALTH     └ échec → alpine restore volume depuis backup (mount SYMÉTRIQUE /data, -C /)
                 + git reset (rollback lourd)
```

**Symétrie backup/restore** : le backup monte `dst_vol:/data` et archive `/data`
(entrées `data/...`) ; la restore monte `dst_vol:/data` et extrait `-C /` pour que
`data/...` atterrisse **dans le volume**. Un montage `/to` casserait la restore.

## Action `[×]` : Supprimer l'atelier (`action_workshop_remove`)

```
1. CONFIRM   widgets.confirm(default=False)
2. DOWN-V    docker compose down -v sur APP_Workshop/X-ws   ← SEUL usage légitime de -v
3. BACKUP    tar.gz X-ws → hubctl_cli/backups/
4. TRASH     shutil.move X-ws → hubctl_cli/_trash/
5. RESTART   prod APPS/X (make up) si elle existe ; sinon warning
```

C'est le **seul** endroit du cycle où `down -v` est permis (destruction explicite
de la sandbox). Partout ailleurs, `down -v` est INTERDIT.

## Slug renaming

Le slug est dans le `.env` (`APP_SLUG`). Pour l'atelier, `X` → `X-ws` :

```bash
# Via hubctl (recommandé) — env_manager.write_env gère l'upsert atomique
# Manuel :
sed -i 's/^APP_SLUG=.*/APP_SLUG=X-ws/' APP_Workshop/X-ws/.env
```

Le slug pilote `container_name`, le nom du volume (`{slug}-postgres-data`), et le
network dans `docker-compose.yml` (qui référence `${APP_SLUG}`). Le `[←]` code-only
ne change **pas** le slug de la prod (il reste `X`).

## Multi-app & dépendances

Le workshop supporte la mise en atelier de **plusieurs apps en une passe**, avec
suggestions automatiques basées sur les dépendances déclarées (`depends.yaml`).
Cf. skill `app-dependencies` (côté template) pour la création des fichiers.

### Trois modes de mise en atelier

| Option TUI | Comportement |
|---|---|
| `[→] X` | Met X en atelier. Si X a des deps non présentes en atelier, propose de les emmener (menu `select` : Oui / Non). |
| `[→→] Multi-sélection` | `widgets.multiselect` (checkbox). Calcule l'union des `resolve_group` et propose le groupe final. |
| `[→+] Ajouter à l'atelier` | Ajoute une app à un atelier existant sans toucher au reste. Visible si atelier non vide. |

### CLI multi-slug

```bash
./hubctl work X,Y,Z          # met X, Y, Z en atelier (un par un, clone DB)
./hubctl work "alpha , beta" # whitespace stripped automatiquement
```

Le split sur virgule se fait dans `action_work`. Chaque slug déclenche un
`action_workshop_create` indépendant (avec son propre rollback sur échec).

### Logique de suggestion (`resolve_group`)

`hubctl_cli/dependencies.py::resolve_group(slug)` fait un DFS transitif :
si `exemple-apps` dépend de `exemple-app-2` qui dépend de `HUBVault`, alors
`resolve_group("exemple-apps")` → `{exemple-apps, exemple-app-2, HUBVault}`.

Le menu propose d'emmener tout le groupe. Si l'utilisateur refuse, un warning
clair s'affiche :

> ⚠ exemple-app sera en atelier sans exemple-app-2. Les appels M2M pointeront vers la prod.

### Offline-first

La lecture disque (`build_graph()`) ne dépend **ni du hub ni de Docker**. Le menu
workshop peut proposer des groupes même si le hub est down ou les apps stoppées.
Le graphe hub (`app_dependencies`) sert uniquement au dashboard prod (via
`GET /api/apps/dependencies`) et à l'affichage de `last_sync_at`.

## Quick Reference

| Ressource | Emplacement |
|-----------|------------|
| Apps production | `APPS/` |
| Apps workshop | `APP_Workshop/` |
| Slug workshop | `{slug}-ws` |
| Volume pattern | `{slug}-postgres-data` |
| Marqueur dev-mode | `HUB_base/.dev-mode` |
| Backup dir | `hubctl_cli/backups/` |
| Corbeille | `hubctl_cli/_trash/` |
| Health endpoint | `http://localhost:{API_PORT}/api/health` |
| Fichier deps par app | `APPS/X/depends.yaml` |
| Module graphe hubctl | `hubctl_cli/dependencies.py` |
| CLI multi-slug | `./hubctl work X,Y,Z` |

### Commandes hubctl

```bash
./hubctl work X              # [→] mettre X en atelier (clone DB)
./hubctl work X,Y,Z          # multi-slug : met X, Y, Z en atelier en une passe
./hubctl ship X              # [←] déployer code-only vers la prod (git pull, DB préservée) — DÉFAUT
./hubctl ship X --copy-db    # [←] avancé : écraser la DB prod (destructif, gate input)
# [×] Supprimer l'atelier : via menu TUI (touch 6 en mode dev)
# --dry-run global supporté sur work/ship
```

### Commandes Docker brutes (référence)

```bash
# Check dev-mode
test -f HUB_base/.dev-mode && echo "OK: dev mode" || echo "ERREUR: mode prod!"

# Stop prod sans détruire (préserve volume + container pour restart rapide)
docker compose -f APPS/X/docker-compose.yml stop

# Cloner un volume (APPS → atelier)
docker volume create X-ws-postgres-data
docker run --rm -v X-postgres-data:/from:ro -v X-ws-postgres-data:/to alpine cp -a /from/. /to/

# Backup volume en tar (pour --copy-db)
docker run --rm -v X-postgres-data:/data:ro alpine tar czf - /data > backup.tar.gz

# Restore volume depuis tar (SYMÉTRIQUE : mount /data, -C /)
docker volume rm X-postgres-data && docker volume create X-postgres-data
docker run --rm -i -v X-postgres-data:/data alpine tar xzf - -C / < backup.tar.gz
```

## Guide hubctl (implémentation)

### Trois fonctions dans `actions.py`

```python
def action_workshop_create(console, app_name: str, *, dry_run: bool = False) -> None:
    """[→] APPS/X → APP_Workshop/X-ws (clone DB). Prod stoppée mais laissée en place."""

def action_prod_deploy(console, slug: str, *, copy_db: bool = False, dry_run: bool = False) -> None:
    """[←] Déployer l'atelier X-ws vers la prod APPS/X.
    copy_db=False (défaut) : git pull code-only, DB préservée.
    copy_db=True          : écrase la DB prod (destructif, délégué à action_prod_deploy_copy_db).
    """
    # `slug` est le slug BASE (sans -ws).

def action_prod_deploy_copy_db(con, slug, prod_dir, ws_dir, compose_file, *, dry_run):
    """Chemin --copy-db (interne) : backup + overwrite volume + git pull + rollback restore."""

def action_workshop_remove(console, app_name: str, *, dry_run: bool = False) -> None:
    """[×] Supprimer l'atelier X-ws (down -v + backup + trash + restart prod)."""
    # `app_name` est le slug ATELIER (avec -ws).
```

### Wrappers CLI (`actions.py`)

- `action_work(console, slug, *, dry_run=False)` → `action_workshop_create`
- `action_ship(console, slug, *, copy_db=False, dry_run=False)` → `action_prod_deploy(copy_db=...)`
  (la gate `input()` est DANS `action_prod_deploy_copy_db`, pas dans `action_ship`)

### Menu TUI (`menu.py::_workshop_menu`)

```
── APP_Workshop/ (développement) ──
  [←] X-ws   → déployer vers la prod (git pull)     # action_prod_deploy(base slug)
  [×] X-ws   → supprimer l'atelier                  # action_workshop_remove(ws slug)
── APPS/ (production) ──
  [→] Y      → mettre en atelier        (si Y-ws absent)
  ⏸  X       (en atelier — prod stoppée) (si X-ws existe, pas de [→])
ℹ Copie DB (avancé) : hubctl ship <slug> --copy-db
```

### Réutilisation de l'existant

| Besoin | Code existant |
|--------|--------------|
| Shell + dry-run | `utils.run_shell()` |
| Health check | `_health_check(target, console, timeout, port_override)` |
| Rollback code-only | `_rollback(target, path, prev_commit, snapshot=None, ...)` |
| Capture HEAD | `_git_previous_commit(path, console)` |
| Liste apps | `hub_state.get_apps()` / `get_workshop_apps()` |
| `.env` read/write | `env_manager.read_env()` / `write_env()` |
| Confirmation TUI | `widgets.confirm()` / `widgets.confirm_by_typing()` |
| Confirmation CLI | `input()` (builtins, pas de canvas) |

## Common Mistakes

| Erreur | Conséquence | Correction |
|--------|-------------|------------|
| `docker compose down -v` hors de `action_workshop_remove` | **Destruction irréversible des volumes** | `-v` UNIQUEMENT dans `[×]` ; partout ailleurs `stop` ou `down` sans `-v` |
| `[←]` par défaut qui touche à la DB | Écrasement accidentel de la DB prod | Le défaut est code-only (`git pull`) ; `--copy-db` est explicite |
| Restore volume `--copy-db` avec mount asymétrique (`/to` vs backup `/data`) | Restore silencieuse → prod garde la DB écrasée | Mount SYMÉTRIQUE `dst_vol:/data` + `-C /` |
| `[→]` sans stopper la prod d'abord | DB/source en cours d'écriture, clone incohérent | `stop` avant `copytree` + clone volume |
| Oublier le renommage du slug à l'atelier | Collision `container_name`, deux apps ne tournent pas | `APP_SLUG=X-ws` systématique |
| `[←]` alors que l'atelier a des commits non poussés | `git pull` ne ramène rien, dev confus | Warnings git-hygiène ; le dev pousse d'abord |
| Faire l'opération en mode prod | Casser la production | Check `.dev-mode` étape 1, toujours |

## Red Flags — STOP et corriger

- "Le `[←]` copie la DB par défaut, non ?" → **Faux.** Le défaut est `git pull` code-only. `--copy-db` est explicite.
- "`down -v` pour être sûr de nettoyer" → **Faux.** Sauf dans `action_workshop_remove`, c'est une destruction de volume.
- "On supprime la prod à l'atelier, comme avant" → **Faux.** La prod reste en place (stopée). C'est le modèle sandbox + deploy.
- "La restore `--copy-db`, je monte n'importe comment" → **Faux.** Montage symétrique obligatoire (cf. section `[←] --copy-db`).
- "Pas besoin de git-hygiène, je pousse toujours" → **Faux.** Les warnings existent justement pour les oublis.
- "Le mode dev c'est optionnel" → **Faux.** Obligatoire ; proposé à l'activation mais refus = abort.

**Tous ces drapeaux : revenir à l'action correspondante et suivre l'ordre strict.**
