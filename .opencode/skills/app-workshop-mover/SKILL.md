---
name: app-workshop-mover
description: Utiliser pour déplacer une application entre APPS/ et APP_Workshop/ (les deux sens) afin de travailler dessus en mode dev ou de la ramener en production. Gère docker compose down avant copie, copie de volume avec docker run alpine cp, renommage du slug avec suffixe -ws, build-up avec vérification santé, et backup avant suppression de la source. Utiliser quand on demande "déplacer/copier une app vers le workshop", "ramener une app du workshop", "mettre une app en atelier", ou pour implémenter l'action workshop-move dans hubctl.
---

# app-workshop-mover

## Overview

Déplacer une application entre `APPS/` (production) et `APP_Workshop/` (développement)
en préservant les données réelles. L'opération suit un ordre strict : **down →
copy files + volume → rename slug → build-up → verify health → backup → delete source**.
Jamais l'inverse.

## When to Use

- "Déplace l'app X dans le workshop"
- "Ramène l'app X-ws en production"
- "Mets exemple-app-2 en atelier pour travailler dessus"
- Implémenter l'action Workshop dans `hubctl` (actions.py + menu.py)

**Ne PAS utiliser pour :**
- Créer une nouvelle app depuis le template → `create_app.sh`
- Cloner un dépôt distant → `action_add_app()` ou `action_init()`
- Simplement redémarrer une app → `make restart`
- Déployer une mise à jour → `action_update()` (blue-green)

## Prérequis (non négociables)

| Prérequis | Vérification |
|-----------|-------------|
| Mode dev actif | `test -f HUB_base/.dev-mode` (ou via hubctl) |
| Docker running | `docker info > /dev/null 2>&1` |
| App source existante | Le dossier source doit exister |
| App destination absente | Le dossier destination ne doit PAS exister (pas d'écrasement) |

**Violer un prérequis = tout arrêter.** Ne jamais contourner.

## Flux 1 : APPS → APP_Workshop (mise en atelier)

Étapes dans l'ordre strict. Chaque étape doit réussir avant de passer à la suivante.

```
1. CHECK     Vérifier .dev-mode et Docker
2. DOWN      docker compose down dans APPS/X
3. COPY      cp -r APPS/X → APP_Workshop/X-ws
4. VOLUME    docker run --rm -v {x}-postgres-data:/from -v {x}-ws-postgres-data:/to alpine cp -a /from/. /to/
5. RENAME    Modifier APP_SLUG=X → APP_SLUG=X-ws dans APP_Workshop/X-ws/.env
6. BUILD-UP  cd APP_Workshop/X-ws && docker compose build && docker compose up -d
7. HEALTH    curl -f http://localhost:{API_PORT}/api/health  (retry 5x, 2s interval)
8. BACKUP    tar czf hubctl_cli/backups/X-$(date +%Y%m%d-%H%M%S).tar.gz -C APPS X
9. DELETE    rm -rf APPS/X
```

**Règle d'or** : si l'étape 6 ou 7 échoue, on fait `docker compose down` dans APP_Workshop et on rollback (ne pas supprimer la source).

### Slug renaming (étape 5)

Modifier uniquement le `.env` de destination :
```bash
sed -i 's/^APP_SLUG=.*/APP_SLUG=X-ws/' APP_Workshop/X-ws/.env
```

Le slug impacte automatiquement les `container_name`, le nom du volume, et le network dans `docker-compose.yml` (qui référence `${APP_SLUG}`).

### Copie de volume (étape 4)

```bash
# Créer le volume destination s'il n'existe pas
docker volume create X-ws-postgres-data

# Copier les données
docker run --rm \
  -v X-postgres-data:/from:ro \
  -v X-ws-postgres-data:/to \
  alpine cp -a /from/. /to/
```

**Ne JAMAIS utiliser `docker compose down -v`** — cela détruirait les volumes.

## Flux 2 : APP_Workshop → APPS (retour en production)

Même ordre, sens inverse.

```
1. CHECK     Vérifier .dev-mode et Docker
2. DOWN      docker compose down dans APP_Workshop/X-ws
3. COPY      cp -r APP_Workshop/X-ws → APPS/X
4. VOLUME    docker run --rm -v {x}-ws-postgres-data:/from -v {x}-postgres-data:/to alpine cp -a /from/. /to/
5. RENAME    Modifier APP_SLUG=X-ws → APP_SLUG=X dans APPS/X/.env
6. BUILD-UP  cd APPS/X && docker compose build && docker compose up -d
7. HEALTH    curl -f http://localhost:{API_PORT}/api/health  (retry 5x, 2s interval)
8. BACKUP    tar czf hubctl_cli/backups/X-ws-$(date +%Y%m%d-%H%M%S).tar.gz -C APP_Workshop X-ws
9. DELETE    rm -rf APP_Workshop/X-ws
```

## Quick Reference

| Ressource | Emplacement |
|-----------|------------|
| Apps production | `APPS/` |
| Apps workshop | `APP_Workshop/` |
| Slug workshop | `{slug}-ws` |
| Volume pattern | `{slug}-postgres-data` |
| Marqueur dev-mode | `HUB_base/.dev-mode` |
| Backup dir | `hubctl_cli/backups/` |
| Health endpoint | `http://localhost:{API_PORT}/api/health` |

### Commandes essentielles

```bash
# Check dev-mode
test -f HUB_base/.dev-mode && echo "OK: dev mode" || echo "ERREUR: mode prod!"

# Down propre (sans -v !)
docker compose -f APPS/X/docker-compose.yml down

# Copier un volume Docker
docker run --rm -v vol_src:/from:ro -v vol_dst:/to alpine cp -a /from/. /to/

# Build + up
docker compose -f APP_Workshop/X-ws/docker-compose.yml build
docker compose -f APP_Workshop/X-ws/docker-compose.yml up -d

# Health check avec retry
for i in $(seq 1 5); do
  curl -sf http://localhost:{PORT}/api/health && echo "OK" && break
  sleep 2
done

# Backup tar.gz
tar czf hubctl_cli/backups/X-$(date +%Y%m%d-%H%M%S).tar.gz -C APPS X
```

## Guide hubctl (implémentation)

### Nouvelle action dans `actions.py`

```python
def action_workshop_move(direction: str, app_name: str, dry_run: bool = False):
    """
    Déplace une app entre APPS/ et APP_Workshop/.
    direction: "to_workshop" | "to_production"
    """
    # 1. Vérifier .dev-mode
    # 2. Résoudre chemins source/dest selon direction
    # 3. docker compose down (source)
    # 4. cp -r fichiers
    # 5. Copier volume Docker
    # 6. Renommer slug -ws (ajout ou retrait)
    # 7. docker compose build && up -d (dest)
    # 8. Vérifier santé (retry 5x)
    # 9. Backup tar.gz (source)
    # 10. Supprimer dossier source
```

### Intégration menu (`menu.py`)

Ajouter une option "Workshop" (sous-menu) entre "Supprimer une app" (3) et "Réparer" (4). Le sous-menu liste les apps dans les deux dossiers et propose deux actions :
- `[→] Mettre en atelier` → sélectionne une app dans `APPS/`, appelle `action_workshop_move("to_workshop", ...)`
- `[←] Remettre en production` → sélectionne une app dans `APP_Workshop/`, appelle `action_workshop_move("to_production", ...)`

### Réutilisation de l'existant

| Besoin | Code existant |
|--------|--------------|
| Lancer une commande shell | `run_shell()` dans `utils.py` |
| Dry-run global | Déjà propagé à `run_shell()` |
| Backup tar.gz | Pattern de `action_remove_app()` |
| Check `.dev-mode` | `menu.py::_devprod_toggle()` |
| Liste des apps | `hub_state.py::get_apps()` |
| Confirmation utilisateur | `utils.py::confirm()` |

## Common Mistakes

| Erreur | Conséquence | Correction |
|--------|-------------|------------|
| `docker compose down -v` | **Destruction irréversible des volumes** | Toujours `down` sans `-v` |
| Copier sans faire `down` d'abord | DB corrompue, ports occupés | Étape 2 avant étape 3, toujours |
| Supprimer la source avant de vérifier la destination | Perte de données si le build-up échoue | Ordre : build-up → health → backup → delete |
| Oublier le renommage du slug | Collision de `container_name`, deux apps ne peuvent pas tourner | Slug `-ws` systématique |
| Ne pas copier le volume | L'app workshop démarre avec une DB vide | `docker run alpine cp` obligatoire |
| Faire l'opération en mode prod | Risque de casser la production | Check `.dev-mode` en étape 1 |
| Utiliser `cp` au lieu de `cp -r` | Les sous-dossiers ne sont pas copiés | `cp -r` ou `rsync -a` |

## Red Flags — STOP et corriger

- "Les conteneurs sont déjà arrêtés, pas besoin de down" → Faux. Des networks/volumes persistent.
- "On peut réutiliser le volume existant sans le copier" → Faux. Deux slugs différents = deux volumes.
- "Je vais juste renommer le dossier, pas besoin de toucher au .env" → Faux. Le slug est dans le .env.
- "On supprime la source d'abord, ça ira plus vite" → Faux. Perte de données garantie si le build échoue.
- "Pas besoin de backup, on a une copie" → Faux. La copie n'est pas un backup versionné.
- "Le mode dev c'est optionnel" → Faux. C'est le premier garde-fou.

**Tous ces drapeaux signifient : revenir à l'étape 1 du flux et suivre l'ordre strict.**
