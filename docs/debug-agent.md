# Agent de debug IA (Ollama)

Assistant IA local pour le debug des applications POULIDOR.

> **⚠ Non encore déployé** — l'agent de debug IA n'est pas encore en place sur
> le parc. Ce guide décrit l'installation prévue ; les commandes
> `./hubctl debug` existent déjà côté CLI.

## Installation (une fois)

### 1. Installer Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Installer le modele

```bash
./hubctl debug --setup
```

L'installeur detecte votre GPU et propose le modele adequat :
- **GPU avec >= 8 Go VRAM** : modele 8b (meilleur raisonnement)
- **CPU seul ou GPU faible** : modele 2b (plus leger)

Vous pouvez forcer un modele : `./hubctl debug --setup --model 2b`

### 3. Verifier l'installation

```bash
./hubctl debug --status
```

## Utilisation

### Session de debug (lecture seule par defaut)

```bash
./hubctl debug exemple-app-1
```

L'IA analyse les logs, configs et statut des conteneurs, puis propose des
commandes a executer manuellement (copier-coller).

### Session de debug (semi-auto)

```bash
./hubctl debug exemple-app-1 --rw
```

L'IA peut executer des actions non-destructives (restart, recreate) directement.
Les actions destructives (down, rm, reset) demandent confirmation.

### Forcer un modele

```bash
./hubctl debug exemple-app-1 --model 2b
```

## Desactivation

```bash
# Desactiver pour la session courante
export POULIDOR_AI_ENABLED=false

# Reactiver
export POULIDOR_AI_ENABLED=true
```

## Outils disponibles

### Lecture (tous modes)
- `docker_logs` — logs d'un conteneur
- `docker_ps` — liste des conteneurs
- `docker_inspect` — inspecter un conteneur
- `docker_stats` — stats ressources
- `db_query_select` — requete SQL SELECT
- `db_dump_inspect` — dump de la base de donnees pour inspection (pg_dump, lecture seule)
- `app_status` — statut global
- `read_file` — lire un fichier

### Actions (mode --rw uniquement)
- `docker_restart` — redemarrer un service
- `docker_recreate` — reconstruire un service
- `docker_down` — arreter l'app (confirmation)
- `docker_prune` — supprimer les images et conteneurs inutilises (confirmation)
- `docker_rm` — supprimer un conteneur (double confirmation)
- `db_reset` — reinitialiser la base (double confirmation)
- `volume_delete` — supprimer un volume Docker (double confirmation)

## Securite

- L'IA est restreinte a l'app cible (`--app`)
- Les fichiers lisibles sont limites au dossier de l'app et HUB_base/
- Les requetes SQL sont limitees a SELECT/WITH
- Les secrets (mots de passe, tokens, cles) sont masques dans le contexte
