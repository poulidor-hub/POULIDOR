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
├── hubctl                    ← CLI de pilotage (TUI + CLI non-interactif, symlink → hubctl_src)
├── hubctl_src/               ← Code métier hubctl (menu, coffre, atelier, export/restore)
├── HUB_base/                 ← Hub SSO (auth, registry, messaging, backups)
├── HUBapp_TEMPLATE_base/     ← Template canonique pour toute nouvelle app
├── APPS/                     ← Applications en production
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
- **CLI non-interactive** : `start`, `stop`, `update`, `atelier`, `init`, `export`, `restore`, `pra-restore`, `debug`, `vpn`, `vault`, `seed`
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
