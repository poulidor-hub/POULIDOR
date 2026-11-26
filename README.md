# POULIDOR — parc d'applications branchées sur un Hub d'authentification self-hosted

POULIDOR est un petit parc d'applications métier organisé autour d'un **Hub
d'authentification auto-hébergé** : SSO par tokens JWT signés RS256, PKI interne,
registre des applications, messagerie inter-apps, sauvegardes — l'alternative légère
et maîtrisée à Keycloak/Authentik, pensée pour une exploitation simple sur un serveur
unique.

Le parc se compose de sept dépôts, publiés ici en open source (AGPLv3 pour le cœur,
MIT pour le gabarit et le design system) :

| Dépôt | Rôle | Version |
|-------|------|---------|
| [`HUB`](https://github.com/poulidor-hub/HUB) | Le Hub : SSO, PKI, registre des apps, messagerie, sauvegardes, WireGuard | ![version](https://img.shields.io/badge/version-0.88.4-blue) |
| [`HUBsocle`](https://github.com/poulidor-hub/HUBsocle) | Socle versionné des applications (API fine branchée sur le Hub) | ![version](https://img.shields.io/badge/version-0.88.4-blue) |
| [`HUBapp-template`](https://github.com/poulidor-hub/HUBapp-template) | Gabarit d'application branchée sur le Hub (FastAPI + React) | ![version](https://img.shields.io/badge/version-0.88.4-blue) |
| [`HUBCSS`](https://github.com/poulidor-hub/HUBCSS) | Design system CSS/JS servi aux applications | ![version](https://img.shields.io/badge/version-0.88.4-blue) |
| [`hubctl`](https://github.com/poulidor-hub/hubctl) | CLI d'administration du parc (init, update, ateliers, coffre) | ![version](https://img.shields.io/badge/version-0.88.4-blue) |
| [`hub-mcp`](https://github.com/poulidor-hub/hub-mcp) | Serveur MCP pour piloter le Hub depuis un assistant IA (66 outils) | ![version](https://img.shields.io/badge/version-0.88.4-blue) |
| **POULIDOR** (ce dépôt) | Méta-dépôt : documentation, runbooks, scripts transverses | ![version](https://img.shields.io/badge/version-0.88.4-blue) |

---

## Installer un déploiement complet

Un déploiement POULIDOR = ce méta-dépôt (avec ses sous-modules) + un fichier `.env`
+ vos applications dans `APPS/` (hors git). Prérequis : un serveur Linux, Docker ≥ 24,
2 Go de RAM.

```bash
# 1) cloner le méta et ses composants
git clone --recurse-submodules https://github.com/poulidor-hub/POULIDOR.git
cd POULIDOR

# 2) nommer la source officielle « upstream » (lecture seule)
git remote rename origin upstream

# 3) (recommandé) garder votre propre dépôt privé comme « origin »
git remote add origin git@<votre-git>:<votre-org>/POULIDOR.git
git push -u origin main

# 4) configuration et applications (hors git)
cp .env.example .env && éditer le .env   # PHILIA_NG_DOMAIN, ports, secrets…
mkdir -p APPS                            # vos applications, hors git

# 5) installer et démarrer le Hub
cd HUB_base && sudo ./install.sh && cd ..
#    — ou via la CLI :
./hubctl init

# 6) vérifier
bash hub.sh up-prod
./hubctl doctor
```

Le script d'installation affiche l'URL du Hub et le mot de passe admin auto-généré.
Vos applications se créent depuis le gabarit [`HUBapp-template`](https://github.com/poulidor-hub/HUBapp-template)
(`INITIALISE.py`) et s'enregistrent auprès du Hub.

## Mettre à jour un déploiement

```bash
git fetch upstream
git merge --ff-only upstream/main
git submodule update --init --recursive
bash hub.sh up-prod
./hubctl doctor
```

`--ff-only` refuse de mélanger vos éventuelles divergences locales : vous décidez.
**Ce dépôt public est en lecture seule pour les déploiements clients** — vos mises à
jour locales se poussent vers votre propre dépôt privé (`origin`), jamais vers
`poulidor-hub`. Un client qui fork un composant pour le personnaliser utilise
[`scripts/fork-remotes.sh`](scripts/fork-remotes.sh) pour réorganiser ses remotes
(origin = son fork, mises à jour tirées de la branche publique).

## Documentation

La documentation complète du parc vit dans ce dépôt : [`docs/guide-hub/`](docs/guide-hub/presentation.html)
(presentation, installation, hubctl, ateliers…), plus les guides embarqués dans chaque
composant (`HUB_base/docs/`, gabarit, hubctl).

## Organisation du dépôt

```
POULIDOR/
├── HUB_base/               ← sous-module : le Hub (FastAPI + vanilla JS + PostgreSQL)
├── HUBsocle/               ← sous-module : le socle applicatif (Python + Rust)
├── HUBapp_TEMPLATE_base/   ← sous-module : le gabarit d'application
├── HUBCSS/                 ← sous-module : le design system
├── hubctl_src/             ← sous-module : la CLI hubctl
├── hub-mcp/                ← sous-module : le serveur MCP
├── docs/                   ← documentation (guide-hub, runbooks, benchmarks)
└── scripts/                ← scripts transverses (migration, oss-guard, remotes…)
```

## Licences

- `HUB_base` et le socle : **GNU AGPLv3** — voir [`HUB_base/LICENSE`](HUB_base/LICENSE).
- Gabarit, design system, CLI, hub-mcp : **MIT**.
- Le nom « POULIDOR » et les logos ne sont pas couverts par ces licences.
