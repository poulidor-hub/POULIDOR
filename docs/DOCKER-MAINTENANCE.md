# DOCKER-MAINTENANCE — entretien Docker du parc POULIDOR

`scripts/parc-docker-maintenance.sh` — entretien récurrent et sûr de Docker
(build cache, images inutilisées, volumes orphelins).

## But

Aucune purge Docker n'existait dans le parc. Constat sur un serveur
(diagnostic) :

- build cache : **137,9 GB** (100 % récupérable) ;
- images inutilisées : **49 GB** ;
- **169 volumes orphelins** (~19 GB) : caches cargo (~11,5 GB),
  `postgres-data` de branches/worktrees mortes, volumes d'une app supprimée
  (`exemple-app-27`).

Le script permet soit un **rapport** (défaut), soit une **purge cadrée**
(`--apply`).

## Usage

```
parc-docker-maintenance.sh [--apply] [--keep-cache GO] [--include-vol-data] [--help]
```

| Option | Effet |
|---|---|
| *(défaut)* | **dry-run** : rapport de ce qui serait purgé, aucune suppression |
| `--apply` | exécute la purge (4 étapes ci-dessous) |
| `--keep-cache GO` | Go de build cache à conserver (défaut : 20) |
| `--include-vol-data` | inclut les volumes DATA **et** INCONNUE |
| `--help` | aide |

Ordre d'exécution de `--apply` :

1. `docker builder prune -af --keep-storage <GO>GB` (build cache, `<GO>` Go conservés) ;
2. `docker image prune -af` (images inutilisées) ;
3. suppression des volumes **CACHE** ;
4. suppression des volumes **DATA + INCONNUE**, uniquement avec `--include-vol-data`.

Le rapport affiche `docker system df`, la taille du build cache
(`docker buildx du`), les images reclaimable, la classification des volumes
dangling, et `df -h` du data-root (`--apply` l'affiche avant **et** après).

## Classification des volumes dangling

Motifs insensibles à la casse, testés dans cet ordre :

| Classe | Motifs sur le nom | Suppression |
|---|---|---|
| CACHE | contient `cargo`, `registry`, `target`, `tmp`, `cache`, `npm`, `pip` | `--apply` |
| DATA | contient `postgres-data`, `pgdata`, `uploads-data`, `logs-data`, `_data`, ou finit par `-data` | `--apply --include-vol-data` |
| INCONNUE | tout le reste (hash hex 64, etc.) | `--apply --include-vol-data` |

Classification volontairement **conservatrice** : un nom matchant plusieurs
classes (ex. `target-data`) part en DATA et exige `--include-vol-data`.

## Sécurités

- Défaut **dry-run** : rien n'est supprimé sans `--apply`.
- Les volumes attachés à un container ne sont **JAMAIS** touchés : le filtre
  `dangling=true` les exclut déjà, et un garde supplémentaire
  (`docker ps -aq --filter volume=<nom>`) protège de toute course entre le
  listing et la suppression.
- ⚠ **Les volumes DATA supprimés ne sont pas sauvegardés** : le script
  affiche ce warning et exige `--include-vol-data` pour toute donnée.
- Chaque volume supprimé est journalisé (stdout + fichier si
  `PARC_DOCKER_MAINTENANCE_LOG=/chemin/vers/log`).

## Exemples

```bash
# rapport (aucune suppression) — à lancer chaque semaine
scripts/parc-docker-maintenance.sh

# purge : build cache au-delà de 20 Go + images inutilisées + volumes CACHE
scripts/parc-docker-maintenance.sh --apply --keep-cache 20

# entretien complet, ⚠ détruit aussi les volumes DATA/INCONNUE orphelins
PARC_DOCKER_MAINTENANCE_LOG=/var/log/parc-docker-maintenance.log \
  scripts/parc-docker-maintenance.sh --apply --include-vol-data
```

## Cron suggéré

- **1×/semaine** : dry-run, en alerte (rapport envoyé/mail, surveillance de la
  croissance du build cache et des volumes).
- **`--apply --keep-cache 20`** : en suggestion manuelle après revue du
  rapport hebdomadaire, ou en cron **mensuel** si le rapport hebdo est suivi.

```cron
# rapport hebdomadaire (lundi 06:30) — alerte uniquement, rien n'est supprimé
30 6 * * 1  /chemin/vers/POULIDOR/scripts/parc-docker-maintenance.sh | mail -s "[parc] docker maintenance" ops@example.com

# purge mensuelle (1er du mois, 04:00) — build cache + images + volumes CACHE
0 4 1 * *   PARC_DOCKER_MAINTENANCE_LOG=/var/log/parc-docker-maintenance.log /chemin/vers/POULIDOR/scripts/parc-docker-maintenance.sh --apply --keep-cache 20
```

(Adaptez `/chemin/vers/POULIDOR` à chaque serveur.)

## Rappel — rotation des logs

La rotation des logs containers est gérée **dans les compose**
(`logging.options.max-size` / `max-file`), pas par ce script : vérifiez la
présence de ces options sur les services avant de chercher un espace disque
côté logs.
