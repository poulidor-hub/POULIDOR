# POULIDOR — Parc applicatif HUB

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
├── hubctl                    ← CLI de pilotage (TUI + CLI non-interactif)
├── hubctl_cli/               ← Code métier (menu, coffre, blue-green, park-export)
├── HUB_base/                 ← Hub SSO (auth, registry, messaging, backups)
├── HUBapp_TEMPLATE_base/     ← Template canonique pour toute nouvelle app
├── APPS/                     ← Applications en production (ateliers inclus, via .workshop.env)
└── exports/                  ← Archives park-export
```

---

## Composants clés

### Hub SSO (`HUB_base/`)
Portail central d'authentification et de service :
- Authentification JWT/JWKS (RSA) — authentification unique pour toutes les apps
- Registre des applications (découverte M2M)
- Messagerie inter-applications et notifications SSE temps réel
- Sauvegardes automatiques, tableau de bord santé des apps
- Support WireGuard VPN intégré

### Template d'application (`HUBapp_TEMPLATE_base/`)
Squelette standard pour toute nouvelle app du parc :
- **Backend** : FastAPI async avec SQLAlchemy 2.x, auth JWT/JWKS, client Hub
- **Frontend** : React 18 + Vite 5, AuthContext avec refresh proactif, TanStack Query
- **Infra** : Docker Compose (PostgreSQL + API + Frontend + Nginx), Makefile standard
- Convention UTC stricte (`TIMESTAMPTZ`, `DateTime(timezone=True)`, `TZ=UTC`)

### Pilotage (`hubctl`)
Outil unique pour administrer tout le parc :
- **TUI interactif** : dashboard avec statut des apps, menus de configuration, coffre de secrets
- **CLI non-interactive** : `start`/`stop`, `update`, `init`, `atelier`, `export` (park-export), `restore` (park-restore), `pra-restore`, `vpn`, `vault`, `seed`, `debug`
- **Blue-green deploy** : déploiement zéro downtime avec validation humaine (`--validate`)
- **Atelier de développement** : bac à sable parallèle par app (clone DB prod à la demande)
- **Coffre chiffré** : sauvegarde des secrets du parc (Fernet + scrypt), export de recovery
- **Park export/restore** : archivage chiffré du parc complet pour disaster recovery

---

## Démarrage rapide

```bash
# 1. Cloner le dépôt (nécessite une clé SSH enregistrée sur l'org GitHub ;
#    accepter la host key GitHub au premier connect — ou pré-remplir :
#    ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts)
git clone --recurse-submodules git@github.com:POULIDOR-Audit-Developpement/POULIDOR.git
cd POULIDOR

# 2. Installation tout-en-un (prérequis + Hub)
#    Sur Debian/Ubuntu/Linux Mint — installe Docker, Python, git, etc.
#    puis initialise le Hub automatiquement.
sudo ./install.sh

# 3. Le Hub est accessible sur https://<IP_DU_SERVEUR>
#    Les credentials admin s'affichent dans le récapitulatif final.

# 4. Créer une nouvelle application
#    Via le TUI : ./hubctl → Apps → Ajouter
#    Ou via l'IA : « Crée une app mon-outil dans POULIDOR »
```

> **Réseau des apps** — à l'installation, `hubctl init` autorise
> (`APP_WHITELIST_NETWORKS`) le réseau Docker des apps + le subnet LAN
> détecté du serveur. Pour autoriser d'autres réseaux (allocation de ports,
> auto-enregistrement), éditer `HUB_base/.env` puis
> `docker compose up -d hub-api` (⚠️ `restart` ne recharge pas le `.env`).

### Installation manuelle (alternative)

Si les prérequis sont déjà installés, ou pour un déploiement ciblé du Hub uniquement :

```bash
./hubctl init
```

Voir `HUB_base/docs/GUIDE_INSTALLATION.md` pour l'installation manuelle détaillée.

---

## Documentation

| Document | Contenu |
|----------|---------|
| `docs/guide-hub/hubctl.html` | Guide complet de `hubctl` (TUI + CLI) |
| `docs/guide-hub/make.html` | Référence des commandes `make` par app |
| `docs/guide-hub/architecture.html` | Architecture du parc |
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
| `vault-manager` | Gestion du coffre de secrets chiffré |
| `create-hub-app` | Création/scaffold d'une nouvelle app de A à Z |
| `app-workshop-mover` | Mise en atelier / déploiement d'une app |

---

## Licence

Projet interne — POULIDOR Audit & Développement.
