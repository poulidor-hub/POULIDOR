# POULIDOR — Parc applicatif HUB

![version](https://img.shields.io/badge/version-0.59.1-blue)
![licence](https://img.shields.io/badge/licence-projet%20interne-lightgrey)

Plateforme de développement et d'exécution pour applications métier, avec **SSO centralisé**,
**déploiement Docker** et **pilotage unifié**.

**Stack :** FastAPI · React 18 / Vite 5 · PostgreSQL 15 · Docker Compose

---

## Pourquoi POULIDOR ?

- **SSO maison léger** — authentification JWT/JWKS (RSA asymétrique). Le Hub signe les tokens,
  les apps les vérifient avec une clé publique. Zéro couplage, zéro usine à gaz.
- **Déploiement reproductible** — chaque app est autonome (Docker Compose + Makefile standard)
  et le Hub centralise l'auth, le messaging et les backups.
- **Pilotage unifié** — `./hubctl` (TUI + CLI) administre tout le parc : déploiement,
  configuration, sauvegarde, ateliers de développement, coffre de secrets.

---

## Structure

```
POULIDOR/
├── hubctl                    ← CLI de pilotage (TUI + CLI non-interactif, symlink → hubctl_src)
├── hubctl_src/               ← Code métier hubctl (menu, coffre, atelier, export/restore, socle)
├── HUB_base/                 ← Hub SSO (auth, registry, messaging, backups, OIDC)
├── HUBsocle/                 ← Socle applicatif versionné des apps (factory + images de base)
├── HUBapp_TEMPLATE_base/     ← Template canonique pour toute nouvelle app
├── HUBCSS/                   ← Design system (CSS + icônes + fonts, servi par le Hub)
├── hub-mcp/                  ← Serveur MCP (65 outils IA pour piloter le Hub)
├── APPS/                     ← Applications en production
├── docs/                     ← Guides du parc (installation, hubctl, make, architecture)
└── exports/                  ← Archives park-export
```

## Architecture

```mermaid
flowchart TB
    subgraph pilotage["🧭 Pilotage"]
        hubctl["hubctl<br/>TUI + CLI"]
        mcp["hub-mcp<br/>65 outils IA"]
    end
    subgraph hub["🌐 Hub central — HUB_base"]
        api["API FastAPI<br/>auth JWT/JWKS · OIDC · registry<br/>messages · backups · snapshots"]
        portail["Portail web"]
        db[("PostgreSQL 16")]
    end
    subgraph apps["📦 Applications — APPS/"]
        app1["App métier 1"]
        app2["App métier 2"]
    end
    socle["🧱 HUBsocle<br/>images socle-api / socle-web"]
    tpl["📋 HUBapp_TEMPLATE_base<br/>template des apps"]
    css["🎨 HUBCSS<br/>design system"]

    hubctl -->|"init · update · atelier · vault"| api
    mcp -->|"MCP stdio · M2M"| api
    app1 & app2 -->|"JWT · M2M · SSE"| api
    api --- db
    portail --- api
    tpl -->|"INITIALISE (fork)"| apps
    socle -->|"FROM socle-api:version"| apps
    css -->|"bundle packé"| hub
    hub -->|"assets runtime"| apps
```

### Composants

| Composant | Version | Rôle |
|---|---|---|
| [`HUB_base`](https://github.com/POULIDOR-Audit-Developpement/HUB_base) | 3.59.x | Hub SSO : auth JWT/JWKS, OIDC, registre des apps, messagerie SSE, backups & snapshots, VPN |
| [`HUBsocle`](https://github.com/POULIDOR-Audit-Developpement/HUBsocle) | 2.25.x | Socle versionné des apps : paquets `hub-socle` / `@poulidor/hub-socle`, images de base |
| [`HUBapp_TEMPLATE_base`](https://github.com/POULIDOR-Audit-Developpement/HUBapp_TEMPLATE_base) | 2.24.x | Template canonique dont toute nouvelle app est issue |
| [`Hubctl`](https://github.com/POULIDOR-Audit-Developpement/Hubctl) | 0.9.x | Pilotage du parc : TUI + CLI, ateliers, coffre, PRA |
| [`HUBCSS`](https://github.com/POULIDOR-Audit-Developpement/HUBCSS) | 0.2.x | Design system Tailwind v4 + icônes Lucide, offline-first |
| [`hub-mcp`](https://github.com/POULIDOR-Audit-Developpement/hub-mcp) | 0.4.x | Serveur MCP : 65 outils IA pour administrer le Hub |

Chaque dépôt a son README détaillé (rôle, démarrage, tests) — les versions exactes
vivent dans les fichiers `VERSION` de chaque composant.

---

## Composants clés

### Hub SSO (`HUB_base/`)
Portail central d'authentification et de service :
- Authentification JWT/JWKS (RSA) — authentification unique pour toutes les apps,
  trousseau multi-clés avec rotation sans rupture
- Provider OIDC complet pour les apps externes (discovery, back-channel logout)
- Registre des applications (découverte M2M)
- Messagerie inter-applications et notifications SSE temps réel
- Sauvegardes automatiques par app + snapshots complets chiffrés du Hub, tableau de
  bord santé des apps
- Support WireGuard VPN intégré

### Template d'application (`HUBapp_TEMPLATE_base/`)
Squelette standard pour toute nouvelle app du parc :
- **Backend** : FastAPI async avec SQLAlchemy 2.x, auth JWT/JWKS, client Hub
- **Frontend** : React 18 + Vite 5, AuthContext avec refresh proactif, TanStack Query
- **Infra** : Docker Compose (PostgreSQL + API + Frontend + Nginx), Makefile standard
- Convention UTC stricte (`TIMESTAMPTZ`, `DateTime(timezone=True)`, `TZ=UTC`)

### Socle versionné (`HUBsocle/`)
Le code de base des apps est mutualisé dans un socle **versionné** :
- Factory `create_app()` (paquet pip `hub-socle`) + frontend `@poulidor/hub-socle` (npm)
- Images de base `poulidor/socle-api` / `poulidor/socle-web` construites en local
  (`./hubctl socle build` — offline-first, aucun registre requis)
- Chaque app déclare sa version via `APP_SOCLE_VERSION` ; `./hubctl socle status`
  surveille le drift de la flotte. Les apps existantes restent des forks du template ;
  les nouvelles apps naîtront « fines » via INITIALISE v2 (à venir).

### Pilotage (`hubctl`)
Outil unique pour administrer tout le parc :
- **TUI interactif** : dashboard avec statut des apps, menus de configuration, coffre de secrets
- **CLI non-interactive** : `start`, `stop`, `update`, `atelier`, `init`, `export`, `restore`, `pra-restore`, `debug`, `vpn`, `vault`, `jwt`, `seed`, `socle`
- **Atelier de développement** : bac à sable par app (`./hubctl atelier <slug>`) — 2e projet compose `<slug>-ws` avec clone de la DB prod, piloté par `APPS/<slug>/.workshop.env` ; `--maj` teste une montée de version, `--prod` déploie ce qui a été validé
- **Coffre chiffré** : sauvegarde des secrets du parc (Fernet + scrypt), export de recovery
- **Park export/restore** : archivage chiffré du parc complet pour disaster recovery

---

## Démarrage rapide

```bash
# 1. Cloner le dépôt
git clone --recurse-submodules git@github.com:POULIDOR-Audit-Developpement/POULIDOR.git
cd POULIDOR

# 2. Installation tout-en-un (prérequis + Hub)
#    Sur Debian/Ubuntu/Linux Mint — installe Docker, Python, git, etc.
#    puis initialise le Hub automatiquement.
sudo ./install.sh

# 3. Le Hub est accessible sur https://<IP_DU_SERVEUR>
#    Les credentials admin s'affichent dans le récapitulatif final.

# 4. Créer une nouvelle application
#    Fichier seed YAML : ./hubctl seed apps.yaml  (ou scripts/create_app.sh)
#    Ou via l'IA : « Crée une app mon-outil dans POULIDOR »
```

### Installation manuelle (alternative)

Si les prérequis sont déjà installés, ou pour un déploiement ciblé du Hub uniquement :

```bash
./hubctl init
```

Voir `HUB_base/docs/GUIDE_INSTALLATION.md` pour l'installation manuelle détaillée.

> 🧰 Outillage dev (gh, tests parallèles, Node.js, diagnostic machine) : [docs/outillage.md](docs/outillage.md)

---

## Mise à jour du parc

⚠️ **Un simple `git pull` ne suffit pas** : les composants (HUB_base, HUBapp_TEMPLATE_base…)
sont des **submodules** — `git pull` ne déplace pas leur pointeur. Et en prod, les fichiers
statiques du frontend sont **cuits dans l'image Docker** (`COPY public/`) : un restart sans
rebuild sert l'ancienne version (badge de version absent, nouveautés invisibles).

```bash
# 1. Pull du méta-repo + mise à jour des submodules
git pull --recurse-submodules
git submodule update --init --recursive

# 2. Rebuild + relance du Hub et des apps (build → up → health check)
./hubctl update
```

Alternative : relancer `sudo ./install.sh` — il resynchronise les submodules et
reconverge le Hub (build + up-prod, cache Docker) même s'il tourne déjà.

---

## Documentation

| Document | Contenu |
|----------|---------|
| `docs/guide-hub/presentation.html` | **Présentation du HUB** — tour d'horizon de toutes les fonctionnalités |
| `docs/guide-hub/hubctl.html` | Guide complet de `hubctl` (TUI + CLI) |
| `docs/guide-hub/make.html` | Référence des commandes `make` par app |
| `docs/guide-hub/architecture.html` | Architecture du parc |
| `docs/guide-parc-poulidor.md` | Référence complète du parc (instantané daté) |
| `docs/cheatsheet-dev-banc.md` | **Banc de test local** : resets (`scripts/banc/`), tokens, debug |
| `docs/guide-developpement-template.md` | Développer une app (conventions, tests, release) |
| `docs/debug-agent.md` | Agent de debug IA |
| `docs/visualDev_guide.html` | Guide visuel (architecture, cycle de vie, atelier, PRA) |
| `docs/canvas-poulidor.html` | Présentation visuelle (canvas client) |
| `HUB_base/docs/GUIDE_ADMIN.md` | Guide administrateur Hub |
| `HUB_base/docs/ARCHITECTURE.md` | Architecture interne du Hub |
| `HUBapp_TEMPLATE_base/docs/API.md` | Conventions API d'une app |
| `HUBapp_TEMPLATE_base/README.md` | Documentation du template |

---

## Compétences IA

Le parc intègre des **skills IA** (`.opencode/skills/`) pour le développement assisté :

| Skill | Usage |
|-------|-------|
| `release-on-main` | Versionnage et CHANGELOG avant push sur `main` |
| `create-hub-app` | Création/scaffold d'une nouvelle app de A à Z |
| `app-workshop-mover` | Cycle atelier : mise en atelier, test, déploiement en prod |
| `migrate-app-template` | Montée de version d'une app vers le template (fusion `.env` incluse) |
| `vault-manager` | Gestion du coffre de secrets chiffré |
| `hub-oidc-manager` | Pont OIDC du HUB : clients, apps externes, debug SSO |

---

## Licence

Projet interne — POULIDOR Audit & Développement.
