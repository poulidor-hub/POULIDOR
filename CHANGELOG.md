# Changelog - POULIDOR (HUB stack)

> Historique des versions du méta-dépôt agrégeant le HUB et les applications du parc.

---

## [0.37.0] - 16 août 2026

### ⚡ hubctl v0.5.0 — kit PRA : emplacement secondaire automatique + pra-restore

- **hubctl_src** → v0.5.0 : pointeur de sous-module avancé sur `main`.
  - **Réplication PRA** : le coffre (`parc.vault.enc` + `.bak`) et le dernier snapshot
    du HUB sont répliqués automatiquement vers l'emplacement PRA à chaque sauvegarde
    du coffre — diff checksum, copie atomique, non-bloquant, clé `pra` dans le résumé
    `backup_all`.
  - **Emplacement générique** : clé USB, 2e disque ou montage réseau ; validation
    « ailleurs » en 2 niveaux (refus du disque serveur) ; marqueur `HUB-PRA-KIT.json`
    + `PRA-README.txt` embarqués dans le kit.
  - **Setup initial** : phase récurrente au 1er lancement de hubctl (configurer /
    plus tard / refus définitif), action **Coffre → 🔄 Emplacement PRA** (statut,
    changer, répliquer, retirer) et badge `⚠ PRA` sur le dashboard si l'emplacement
    est absent ou non synchronisé depuis 7+ jours.
  - **Assistant `pra-restore`** : `python -m hubctl_cli pra-restore` — localisation
    du kit, coffre restauré depuis le kit, build & start de la stack, injection du
    snapshot, attente du restore interne, sélection des apps à rebuilder/réinjecter.
    Idempotent/resumable ; arguments `kit` (positionnel, scan auto) et fanions
    `--snapshot`, `--apps all|none|a,b`, `--admin-user`, `--yes`, `--force`
    (garde-fou parc non vide), `--dry-run`. Documentation PRA dans `hubctl_cli/README.md`.
  - **Tests** : `test_pra_config` (24), `test_pra_replicate` (9), `test_pra_restore`
    (29), `test_setup_phase` (10), +2 hooks `vault_manager` — 396 au total.

## [0.36.0] - 16 août 2026

### 🔒 Cloisonnement réseau du VPN WireGuard (defense-in-depth)

- **Constat audit** : la restriction « HUB uniquement » des clients VPN ne reposait que
  sur le split tunnel côté client (`AllowedIPs = hub/32` dans les .conf générés par le
  HUB). Côté serveur, rien ne l'enforçait : `net.ipv4.ip_forward=1` et politique
  `FORWARD ACCEPT` avec `DOCKER-USER` vide — un client éditant son .conf (ex.
  `AllowedIPs = 198.51.100.30/16`) pouvait atteindre les réseaux Docker internes
  (`hub-db` :5432, bridges des apps) et tenter le LAN.
- **Ajouté** `scripts/hub-vpn-firewall.sh` : script firewall idempotent (règles marquées
  `-m comment`, purge + réinsertion ordonnée). Les clients `wg0` n'atteignent que le
  trafic **DNATé** par Docker (= HUB + apps via leurs ports publiés) ; tout le reste
  est droppé (LAN, réseaux internes, hôte/SSH). `INPUT` : seul `ESTABLISHED,RELATED`
  et ICMP echo (ping `198.51.100.50`, diagnostic) passent depuis `wg0`. IPv4 uniquement
  (`wg0` sans adressage IPv6).
- **Ajouté** `scripts/systemd/hub-vpn-firewall.service` (oneshot, `After=docker.service`,
  `RemainAfterExit=yes`) : réapplique les règles à chaque boot — la chaîne `DOCKER-USER`
  est recréée vide par Docker au démarrage. Inoffensif si le VPN est désactivé (aucun
  trafic ne matche `-i wg0`).
- **install.sh** (Phase 2f) : installe script + unit vers `/usr/local/sbin/` et
  `/etc/systemd/system/`, `systemctl enable --now`. Idempotent.
- **Tests** : script validé par harnais mock iptables (ordre des règles ACCEPT/DROP,
  idempotence sur 3 exécutions, création de la chaîne si absente).

## [0.35.12] - 16 août 2026

### ⚡ HUB_base v3.32.2 — tooltip « Répartition du temps par application » corrigé

- **HUB_base** → v3.32.2 : pointeur de sous-module avancé sur `main`.
  - **Fix audit** (`audit-charts.js`, `renderUserDayBreakdown`) : au survol/clic d'un segment
    de la barre empilée « Répartition du temps par application » (onglet Uptime utilisateurs),
    le tooltip affichait `— 20min (undefined%)` sans nom d'app. Cause : formatter basé sur
    `params.name` (vide — axe de catégorie masqué) et `params.percent` (propriété réservée
    aux séries pie). Correctif : nom via `params.seriesName`, pourcentage calculé sur le
    total du jour. Vérifié en production (tooltip « App — durée (x%) »).

## [0.35.11] - 16 août 2026

### ⚡ HUB_base v3.32.1 — fin du bruit 404 du health monitor dans le journal d'audit

- **HUB_base** → v3.32.1 : pointeur de sous-module avancé sur `main`.
  - **Fix supervision** (`routes/apps_health.py`) : le moniteur (`GET /api/apps/health`)
    ne sonde plus `/api/health/detailed` sur l'app système `hub` elle-même — le HUB
    n'expose pas cet endpoint, d'où un faux 404 auto-infligé (IP hub-api) journalisé
    dans l'audit à chaque affichage de la page de supervision. L'enrichissement local
    (version + uptime sans HTTP) reste inchangé, aucune perte dans l'UI.

## [0.35.10] - 16 août 2026

### ⚡ HUBapp_TEMPLATE_base v2.13.0 — épinglage du sous-réseau Docker des apps

- **HUBapp_TEMPLATE_base** → v2.13.0 : pointeur de sous-module avancé sur `main`.
  - **Réseau** : le réseau `app-network` du `docker-compose.yml` du template épingle son
    sous-réseau via IPAM (`APP_SUBNET`), alloué automatiquement par le Hub
    (`POST /api/apps/allocate-ports`, pool `APP_SUBNET_POOL`) à la première exécution de
    `make up`/`make build`. Complète la feature subnet de HUB_base v3.32.0.
  - **⚠ Migration** : les apps existantes syncées sur ce template doivent relancer
    `make sync-env` (allocation `APP_SUBNET` automatique et idempotente) avant
    `docker compose up`.

## [0.35.9] - 16 août 2026

### ⚡ HUB_base v3.32.0 — snapshots complets + allocation de sous-réseaux Docker

- **HUB_base** → v3.32.0 : pointeur de sous-module avancé sur `main`.
  - **Snapshots** : capture du code, de la config et de l'historique `.git` des apps
    (`APPS/`) dans `apps/apps_code.tar` ; restauration semi-automatique PRA bare-metal
    documentée dans `BACKUP.md` ; fix du scheduler cron qui ne déclenchait jamais les
    snapshots planifiés.
  - **Réseau** : allocation d'un sous-réseau Docker `/24` par application depuis le pool
    `APP_SUBNET_POOL` (défaut `198.51.100.40/16`) ; remplissage paresseux des allocations
    existantes ; champ `subnet` exposé dans `AllocatePortsResponse`,
    `GithubRepoPrepareResponse` et `PortsStatusResponse`.
- **Docs** : mise à jour des rapports Superpowers (`task-6-report.md`,
  `task-7-report.md`, `progress.md`) pour la livraison snapshot.

## [0.35.8] - 15 août 2026

### 🔒 Fin du spam du journal d'erreurs HUB — 401 SSE + fixes des 4 apps legacy

- **HUB_base** → v3.31.1 : merge de `feat/audit-usage-charts` sur `main` — embarque
  v3.28.5 (les 401 sur `/api/events/stream` ne sont plus enregistrés dans `error_logs`,
  ~14 000 entrées/jour observées le 2026-08-15 ; rejet côté client inchangé), v3.29.0
  (cert PhiliaNG auto-généré), v3.30.0 (groupes d'applications), v3.31.0 (visualisations
  audit : uptime utilisateurs, heatmap parc, stats par application) et v3.31.1 (perf
  agrégats 90 j + filtre app sur `/usage/apps`). *(Pointeur sous-module avancé —
  réconciliation effectuée.)*
- **HUBapp_TEMPLATE_base** → v2.12.0 : re-synchro périodique (6 h) des certificats HTTPS
  depuis la PKI du HUB (`cert_sync.py`) — la rotation du cert du HUB se propage sans
  intervention manuelle. *(Pointeur sous-module avancé.)*
- **exemple-app** → v1.27.0 (dépôt indépendant, hors sous-modules) : vue groupée arborescente
  des contrats + correctifs recherche/filtres cumulatifs.
- **4 apps legacy corrigées** (SSE du Hub désormais authentifié via `?token=`, pattern
  template — notifications SSE fonctionnelles + fin de la boucle 401) :
  - **exemple-app** → v0.0.2
  - **exemple-app-16_API_v3** → v1.6.1
  - **exemple-app_v3** → v0.2.1 (package.json réaligné)
  - **exemple-app** → v1.0.6 (package.json réaligné ; **push GitHub bloqué** :
    droits d'écriture manquants sur `Federation-exemple-50/exemple-app` — commit prêt
    localement)
- **Purge** : 14 344 erreurs 401 SSE historiques supprimées de `error_logs`.
- **Skills** : `migrate-app-template` — nouvelle section **D.3.2** (SSE authentifié :
  détection, pattern correct, vérification post-migration) + item dédié dans la
  checklist **G.2**.

---

## [0.35.7] - 14 août 2026

### 🔒 Bug « onglet qui se referme » au lancement des apps — correctif + garde-fou migration

- **HUBapp_TEMPLATE_base** → v2.11.2 : `AuthContext.getInitialToken()` purge le refresh
  token localStorage quand un token de lancement arrive sans `refresh_token` associé —
  corrige la fermeture immédiate d'onglet au clic (refresh token consommé par la
  rotation du HUB → 401 → logout → `window.close()`), quasi systématique depuis les
  access tokens à 30 min.
- **exemple-app** (app) → v2.15.3 : même correctif **+ init URL-first synchrone** au mount
  (l'ancien état lisait uniquement le localStorage et pouvait `logout()` avant de
  traiter le token frais de l'URL). Déployé en production.
- **Skills** : `migrate-app-template` enrichi — section **D.3.1** documentant le bug
  legacy (mécanisme + 2 correctifs du template + vérification post-migration) et item
  dédié dans la checklist **G.2** : les apps legacy non migrées gardent le bug jusqu'à
  leur migration.

---

## [0.35.6] - 14 août 2026

### 🔒 Correctifs sécurité parc — audit du 10 mai 2026 (fin de chantier)

- **HUBapp_TEMPLATE_base** → v2.11.1 : durcissement des conteneurs (audit #21) — `no-new-privileges` + `cap_drop: ALL` sur les trois services compose (caps minimales pour postgres, zéro pour l'api, `NET_BIND_SERVICE` pour le frontend) ; frontend **100 % non-root** (`USER nginx`, pattern `HUB_base/frontend`). Non propagé aux apps existantes (effectif à la prochaine migration template).
- **exemple-app** (app, hors sous-modules) → v2.15.2 : SSE — fin du décodage JWT sans vérification de signature et du fallback anonyme par cookie (audit #12) ; token validé via `hub_auth.decode_token` (RS256), 401 sinon, + 5 tests de régression.
- **exemple-app** (app, hors sous-modules) → v1.26.1 : retrait de la publication du port Postgres 5432 sur l'hôte (recommandation audit « ne jamais publier la DB ») — accès réseau Docker interne uniquement.

---

## [0.35.5] - 14 août 2026

### ⚡ HUBapp_TEMPLATE_base v2.11.0 — Canevas de cahier des charges (100 % métier)

- **HUBapp_TEMPLATE_base** → v2.11.0 : ajout de `cahier-des-charges.html`, un canevas interactif autonome (HTML statique, `file://`, sans backend) pour décrire le besoin métier d'une nouvelle app en amont du code, à remplir en atelier (dev + métier).
- Canevas **100 % métier** (10 questions) : l'agent Jellycode dérive la couche technique (modèle de données, endpoints, écrans) depuis la spécification exportée. Exports Markdown + JSON round-trip + « Spécification agent » (manifest métier). Attribution POULIDOR, fiche d'identité (auteur/mainteneur), logigramme Mermaid, thème clair/sombre.

---

## [0.35.4] - 13 août 2026

### ⚡ HUB_base v3.28.4 — Retrait du « Guide de maintenance »

- **HUB_base** → v3.28.4 : suppression de la vue d'aide « Guide de maintenance » (bouton `?` de la navbar, modale `#guideModal` et logique `showGuideModal`). Vue jugée inutile.

---

## [0.35.3] - 12 août 2026

### 🔧 HUB_base v3.28.3 — SNI PhiliaNG automatique

- **HUB_base** : `nginx-philia-ng.conf` utilise `host.docker.internal:4443` au lieu d'une IP hardcodée. Le HUB se déploie sur n'importe quel serveur sans modifier la config SNI PhiliaNG.
- **HUB_base** : `docker-compose.yml` ajoute `extra_hosts: host.docker.internal:host-gateway` au service `hub-frontend`.

## [0.35.2] - 12 août 2026

### ⚡ Skills enrichis + submodules bumped + script check-import

- **HUB_base** → v3.28.2 : Docker GID configurable via `HOST_DOCKER_GID`, fix comment `is_workshop`.
- **hubctl_src** → v0.4.0 : shell marker portable (`_install_shell_marker`), auto-source `.secrets`, cleanup legacy `APP_Workshop/`.
- **Skills** : `app-workshop-mover`, `proxy-ia` enrichis ; `create-hub-app`, `vault-manager` corrigés.
- **Manifest** : ajout de `hubctl_src` dans `manifest.json` pour la découverte complète du parc.
- **README** : suppression de la référence `APP_Workshop/` (obsolète depuis le nouveau schéma atelier).
- **`.secrets.example`** : mise à jour des variables d'exemple.
- **`scripts/check-import.sh`** : nouveau script utilitaire pour vérifier les imports.
- **`.superpowers/sdd/`** : rapports de tâches mis à jour.

## [0.35.1] - 11 août 2026

### ⚡ Fixes HUB_base + hubctl_src

- **HUB_base** → v3.28.1 : PhiliaNG nginx conditionnel — ne crash plus au boot
  si les certificats `certs/server/philia-ng/` sont absents (machine sans PhiliaNG).
- **hubctl_src** → v0.3.2 : fix `_sync_db_password_if_needed()` — la commande
  `psql -d` utilisait `POSTGRES_USER` au lieu de `POSTGRES_DB`, empêchant la
  sync du mot de passe DB quand un volume existait.

## [0.35.0] - 11 août 2026

### ⚡ Nouveau skill proxy-ia et correction release-on-main

- **Skills** : ajout du skill `proxy-ia` — pattern générique de proxy transparent
  avec overlay JS, cache collectif L1/L2, piggyback du token utilisateur, et
  recherches backend dans le cache. Cas de référence : PhiliaNG / philiang.
- **release-on-main** : correction du comportement par défaut — le CHANGELOG
  est désormais purement technique, le patchnote utilisateur n'est rédigé que
  sur demande explicite (plus de question automatique au push).

## [0.34.1] - 10 août 2026

### ⚡ Fix fresh clone : APPS/.gitkeep + hubctl_src PARC_ROOT

- **hubctl_src** → v0.3.1 : `_find_parc_root()` corrigé — ne requiert plus `APPS/`
  (seulement `manifest.json`). Sur un fresh clone sans apps, `APPS/` n'existe pas
  et la détection retombait sur `hubctl_src/`, empêchant `make -C HUB_base up-prod`.
- **POULIDOR** : ajout de `APPS/.gitkeep` tracké dans git (avec exception dans
  `.gitignore`) pour garantir que le dossier existe sur tout clone frais.

## [0.34.0] - 10 août 2026

### ⚡ Installation full-auto + .env enrichi OIDC/SLO/SA

- **HUB_base** → v3.28.0 : `install.sh` en mode `--auto` par défaut (zéro interaction),
  `.env` généré enrichi avec les variables OIDC, SLO, et Service Account interne.
  `.env.example` synchronisé avec les 5 variables manquantes.
- **hubctl_src** → v0.3.0 : `_generate_dotenv()` enrichi avec les mêmes variables
  OIDC/SLO/SA pour la cohérence entre `./install.sh` et `./hubctl init`.

## [0.33.0] - 10 août 2026

### ⚡ Mise à jour sous-modules + skill migrate-app-template

- **HUB_base** → v3.27.0 : routage SNI `service.example.org` → proxy PhiliaNG transparent (nginx-ssl.conf)
- **HUBapp_TEMPLATE_base** → v2.9.0 : affichage `APP_VERSION` dans le header de l'app
- **Skills** : ajout du skill `migrate-app-template` pour mettre à jour les apps vers la dernière version du template

## [0.32.0] - 3 août 2026

### ⚡ HUB_base v3.24.0 — Préférences utilisateur globales

- **HUB_base** : nouveau système de préférences utilisateur (tags globaux). Les admins
  définissent des catégories de préférences (ex: secteur, équipe), les utilisateurs
  sélectionnent leurs valeurs depuis leur dashboard, et les apps les consomment automatiquement
  via le claim JWT `tags`. API REST `/api/tags` (12 endpoints), migration 047, UI admin
  avec onglets (catégories, utilisateurs, mes préférences), widget dashboard, SSE temps réel.
- **Correctifs HUB_base** : proxy SSL redirect, grille VPN peers UI, healthcheck frontend.

---

## [0.31.0] - 2 août 2026

### 📣 Pour les développeurs

- **Amélioré** : Les skills parc sont allégés et consolidés — `agent-isolation-git` (333→135 lignes, + découvrable), `hub-oidc-manager` (462→387), `create-hub-app` (183→161).
- **Corrigé** : Incohérence cache nginx `jellycode.md` (expires 1d → immutable) résolue. Compteur MCP ~85→~65 corrigé. Skill `app-dependencies` désormais découvrable (front-matter ajouté). `hub-messages-integration` fusionné dans `hub-notifications`.
- **Mis à jour** : Submodule `HUBapp_TEMPLATE_base` → v2.8.0 (refactor massif des skills template : fusion, scission, allègement, nouvelle doc `docs/HUB_MCP.md`, nouveau skill `bulk-operations`).

### ⚡ Refactor du parc de skills — nettoyage et cohérence

- **Skills parc allégés** : `agent-isolation-git` 333→135 (condensé au noyau lock/registre, multi-agent occasionnel confirmé), `hub-oidc-manager` 462→387 (doc code coupée : vars OIDC, endpoints, tables DB, claims OIDC ; recettes terrain gardées), `create-hub-app` 183→161 (Phase E/F redondantes → pointeurs).
- **Corrections `jellycode.md`** : cache headers `expires 1d` → `public, max-age=31536000, immutable` (aligné sur `cache-busting-deployment`), compteur MCP ~85→~65, listing skills app à jour (+app-dependencies, -hub-messages-integration).
- **Corrections skills** : `app-dependencies` front-matter ajouté (était un zombie invisible sans découverte), `release-sync` pointe vers `release-on-main`.
- **Submodule `HUBapp_TEMPLATE_base`** → v2.8.0 : refactor complet des skills template (fusion hub-messages-integration→hub-notifications, scission badge-search→badge-search + bulk-operations, migration catalogue hub-mcp-usage→docs/HUB_MCP.md). Net -187 lignes.

## [0.30.0] - 2 août 2026

### ⚡ Skill agent-isolation-git : isolation multi-agent concurrents

- **Nouveau skill `agent-isolation-git`** : permet à plusieurs agents Jellycode de
  travailler en parallèle sur le même dépôt sans collision de commits ou de branches,
  via des worktrees isolés et un registre partagé.
- **Registre JSON** (`registry.json`) dans `.worktrees/_agents/` avec lock atomique
  (`mkdir`) pour éviter les collisions de branches et sérialiser les merges vers `main`.
- **Cycle de vie en 5 étapes** : enregistrement → création du worktree → travail →
  merge sérialisé (lock + `release-on-main`) → nettoyage.
- **Lock stale détecté** automatiquement après 60 secondes (crash d'un agent).
- **Périmètre git uniquement** (v1) — pas de Docker, DB, ou submodules.
- **AGENTS.md** : nouvelle section "Multi-agent — isolation git" qui documente
  l'obligation d'isolation avant toute modification de code.

## [0.29.0] - 2 août 2026

### ⚡ Guide développement + clarification agent + màj dépendances

- **`docs/guide-developpement-template.md`** : nouveau guide de référence (1021 lignes)
  pour créer, développer et maintenir une application HUB basée sur le template.
- **Agent Jellycode** : clarification du workflow de vérification — `verify-feature` pour
  les apps (Makefile app) vs rebuild manuel + curl pour le HUB core (`HUB_base/`).
- **Cleanup** : `APPS/README.md` et `APP_Workshop/README.md` supprimés (obsolètes
  après la migration des ateliers vers `APPS/` via `.workshop.env`).
- **HUB_base** `24d56a5` → `549f7b5` (v3.23.0) — 11 commits :
  - Guide de maintenance en modale Bootstrap
  - Apps santé : badge Système, masquage actions sur HUB
  - `/api/health` expose version + uptime
  - Audit : IP réelle derrière proxy (X-Forwarded-For)
  - App système `git_repo_url` persistant/modifiable
  - VPN : migration subprocess.run → API Docker, parsing handshake robuste, seuil 180s
- **hub-mcp** `8ffec6e` → `2bc3696` (v0.4.0) — client standalone enrichi (discover,
  JWKS, M2M), bootstrap tokens désactivés proprement, résolution slug→id
- **hubctl_src** `e67e72b` → `99b5e38` (v0.2.0) — migration ateliers `APP_Workshop/`
  → `APPS/` via `.workshop.env`, `PARC_ROOT` robuste face aux symlinks

## [0.28.2] - 2 août 2026

### ⚡ Mise à jour de dépendance — HUB_base v3.21.0

- **HUB_base** : `9ec9148` (v3.20.1) → `49f5549` (v3.21.0)
  - VPN WireGuard mode serveur : gestion peers, .conf, QR code, split tunnel
  - AllowedIPs dynamiques (accès apps via VPN, aucune IP en dur)
  - Fix : changement de port via l'UI réellement appliqué (redémarrage conteneur)
  - Fix : retrait du DNS imposé au client

## [0.28.1] - 2 août 2026

### ⚡ Correction des pointeurs de sous-modules

- **HUB_base** : `1393353` (orphelin) → `9ec9148` (origin/main, v3.20.1)
- **HUBapp_TEMPLATE_base** : `84f6878` (feature branch) → `98900db` (origin/main, v2.7.0)
- **hubctl_src** : `205a927` (orphelin) → `e67e72b` (origin/main, v0.1.0)
- Les trois sous-modules pointaient vers des commits jamais poussés sur leurs dépôts respectifs.

## [0.28.0] - 1 août 2026

### ⚡ Directive agent template-centrée (ex-HUBCSS)

- **`.opencode/agent/jellycode.md`** : les directives HUBCSS (package `@poutchouli/design-system`, docs `HOW2USE.md`/`PERFORMANCE.md`, classes `hub-button`/`hub-surface`/etc.) sont remplacées par une approche centrée sur le template. Le template devient la source de vérité visuelle pour l'agent.
- **Nouvelle section « Directives visuelles »** intégrée à la charte Jellycode : table des tokens CSS, conventions de classes, patterns composants de référence, garde-fous cache nginx / React Query / performance, et checklist des 8 anti-patterns.
- **Charte point 3** : « Cohérence visuelle = suivre le template » remplace « Harmonie visuelle HUBCSS ».
- **Suppressions** : références à `@poutchouli/design-system`, `HUBCSS/docs/HOW2USE.md`, `HUBCSS/docs/PERFORMANCE.md`. Les tokens `--hub-*` restent mentionnés comme variables CSS disponibles.

## [0.27.2] - 31 juillet 2026

### ⚡ Migration hubctl_cli → sous-module Hubctl

- **hubctl_cli** (59 fichiers) extrait en sous-module indépendant vers le repo
  `POULIDOR-Audit-Developpement/Hubctl` (v0.1.0). Historique complet préservé
  (502 commits via `git subtree split`). Sous-module dans `hubctl_src/`.
- **Compatibilité préservée** : symlinks `hubctl → hubctl_src/hubctl` et
  `hubctl_cli → hubctl_src/hubctl_cli`. Tous les chemins `./hubctl` et
  `hubctl_cli/` continuent de fonctionner sans modification.
- **`install.sh`** : ajout de `git submodule update --init --recursive` en
  phase 1, garantissant que `hubctl_src/` est initialisé même si le clone a
  été fait sans `--recurse-submodules`.
- **`git clone`** : nécessite `--recurse-submodules` pour initialiser `hubctl_src`.
  `install.sh` gère désormais ce cas automatiquement via `git submodule update --init`.

## [0.27.1] - 31 juillet 2026

### ⚡ Outillage MCP hub-mcp v0.3.1

- **hub-mcp** (sous-module) mis à jour vers v0.3.1 : correction du bug `"object dict
  can't be used in 'await' expression"` qui rendait tous les outils MCP du Hub
  inaccessibles depuis le méta-repo (mode standalone). Le client standalone
  `StandaloneHubClient.call_hub_endpoint` passe en `async def` pour respecter le
  contrat attendu par `call_tool()`.

## [0.27.0] - 30 juillet 2026

### ⚡ hubctl v0.27.0 — seed export

- **`hubctl seed export`** : nouvelle commande pour générer un fichier seed YAML à partir des apps installées dans `APPS/`. Utilise `-o <chemin>` pour spécifier la sortie (défaut : `seed-export-YYYY-MM-DD.yaml`), `--force` pour écraser un fichier existant. Compatible avec `hubctl seed <fichier.yaml>` (déploiement).
- **312 tests** (hubctl_cli), 5 tests unitaires dédiés à `action_seed_export`.
- Correction post-review : support de la syntaxe `seed export`, nettoyage du dead code, tests `--force` et nom de fichier par défaut.

## [0.26.0] - 30 juillet 2026

### 📣 Pour les utilisateurs

- **Ajouté** : le coffre (vue détaillée) est maintenant accessible depuis le dashboard (touche `4`/`6`). Il affiche les entrées du coffre, les badges `[MODIFIÉ]` quand le disque a divergé, et permet de consulter les secrets par entrée.
- **Corrigé** : les résultats des actions (✓/✗ démarrage, arrêt, mise à jour, sauvegarde coffre) étaient invisibles — seul « ↵ Entrée pour revenir au menu… » s'affichait. Le message de résultat est désormais composé avec l'invite.
- **Corrigé** : les erreurs lors de la sauvegarde / export / changement de passphrase du coffre étaient silencieuses. Elles sont maintenant affichées avec ✗ en rouge.
- **Amélioré** : le coffre ne sauvegarde plus inutilement quand aucun `.env` n'a changé depuis la dernière sauvegarde (« ✓ Coffre déjà à jour »).
- **Amélioré** : le démarrage/arrêt détecte désormais les apps déjà démarrées/arrêtées et les saute (« ✓ déjà démarré/arrêté »).
- **Amélioré** : la mise à jour détecte désormais si le dépôt git est déjà à jour et saute le cycle stop→pull→build→up (« ✓ déjà à jour »).

### ⚡ hubctl v0.26.0 — coffre visible + actions idempotentes

- **`view_coffre` branché dans `main_loop`** (`menu.py`) : l'écran complet du coffre (entrées, divergence, actions, révélation) était écrit mais jamais appelé — il remplace désormais `_coffre_submenu`.
- **`pause(canvas, message)`** (`menu.py`) : `pause` accepte un message optionnel composé AVEC l'invite Entrée (au lieu d'écraser le message précédent).
- **`_run_action`** (`menu.py`) : utilise `pause(canvas, message)` pour que le résultat ✓/✗ reste visible après `stream_command`.
- **`view_coffre` try/except** (`menu.py`) : les 3 actions (sauvegarder, export, changer passphrase) capturent et affichent les erreurs.
- **Coffre idempotent** (`menu.py:view_coffre`) : `check_divergence()` avant `backup_all()` — skip si rien n'a changé.
- **Helpers d'idempotence** (`actions.py`) : `_app_running()` (Docker API), `_hub_running()` (services Hub), `_git_up_to_date()` (git fetch + compare HEAD/@{u}).
- **Start/stop idempotents** (`actions.py`) : `_start_hub`, `_start_app`, `_stop_app` sautent les cibles déjà dans l'état voulu.
- **Update idempotent** (`actions.py:_update_target`) : si `HEAD == @{u}`, saute le cycle stop→pull→build→up.
- **Tests** : 307 (inclut `test_view_coffre_backup_already_up_to_date`).

---

### 🐛 HUB_base v3.19.1 — fix migrations fresh install

- **HUB_base → v3.19.1** : correctifs sur les migrations 026 (`INSERT` app système Hub manquait `is_workshop` et `is_unmanaged`) et 042 (`ALTER TABLE ADD COLUMN git_repo_url` manquait `IF NOT EXISTS`). Ces bugs empêchaient un boot sur base de données vierge (`NotNullViolation` / `DuplicateColumnError`). Nouveau test garde-fou empêchant cette classe de régression à la source.

---

## [0.25.5] - 29 juillet 2026

### 📣 Pour les utilisateurs

- **Corrigé** : la création d'un nouveau coffre avec une passphrase vide n'est plus autorisée.
- **Corrigé** : l'export de récupération protège désormais les permissions des fichiers secrets écrits (0o600) et restaure correctement l'umask en cas d'erreur.
- **Amélioré** : la vérification « Hub vide » avant une restauration de parc utilise désormais le nombre réel de lignes dans la table `users` (et non le nombre de tables), ce qui permet de restaurer un Hub fraîchement initialisé.
- **Note technique** : les paramètres du KDF Scrypt (n=2^14) sont volontairement bas pour la rapidité — ils évolueront dans une version future avec versionnage du format coffre.

### 🧹 Finitions — `hubctl`

- **`export_recovery` umask garantie** (`vault_manager.py`) : l'état du `umask` est restauré via `try/finally`. Les fichiers secrets écrits reçoivent explicitement `chmod 0o600` (plus par effet de bord).
- **Passphrase vide refusée** (`coffre.py:unlock()`) : un coffre créé avec une passphrase vide était trivialement déchiffrable. Défense en profondeur (l'UI vérifiait déjà mais le coffre ne défendait pas).
- **`datetime.utcnow()` → `now(timezone.utc)`** (`vault_manager.py`) : API dépréciée depuis Python 3.12.
- **Validation des valeurs `.env`** (`env_manager.py`) : `write_env` rejette désormais les valeurs contenant un `\n` (saut de ligne) — elles corrompraient le fichier.
- **Durabilité de `_atomic_write`** (`env_manager.py`) : `os.fsync` du répertoire parent après `os.replace` pour garantir la persistance du rename en cas de crash système.
- **`_check_hub_is_empty` corrigé** (`park_restore.py`) : la requête comptait les tables via `information_schema.tables` (1 si la table existe, même vide) au lieu des lignes de `users` (`SELECT COUNT(*) FROM users`). Un Hub démarré mais sans users (juste après un `compose up` initial) était refusé à tort.
- **Note Scrypt** (`coffre.py:derive_key`) : commentaire documentant le choix `n=2^14` et la nécessité de versionner le KDF dans le blob pour une future montée en résistance brute-force.

### 🧪 Tests

- **306 tests, 0 échec** (stable depuis v0.25.4).

## [0.25.4] - 29 juillet 2026

### 📣 Pour les utilisateurs

- **Corrigé** : la jauge réseau du tableau de bord affichait une unité fausse (Go/s au lieu de Mo/s).
- **Corrigé** : appuyer sur Échap dans le dialogue de confirmation (exemple : quitter hubctl) fermait l'application au lieu d'annuler.
- **Corrigé** : la barre d'espace disque et son pourcentage se contredisaient (barre = % utilisé, chiffre = % libre) — désormais cohérents.
- **Amélioré** : le terminal revient toujours en mode normal, même après un crash de hubctl (plus d'entrée invisible sans écho qui forçait à taper `reset`).
- **Amélioré** : l'atelier (création d'un environnement de test pour une app) garantit désormais le redémarrage de la production en cas d'erreur inattendue.
- **Amélioré** : robustesse de l'export et de la restauration de parc — l'archive détecte correctement un dump de base de données manquant, et la restauration est compatible avec Python 3.10 et 3.11.

### 🛡️ Robustesse — `hubctl` (Palier 3)

- **`_norm` cohérent Compose v2** (`hub_state.py`) : remplace les séparateurs par `-` au lieu de les supprimer → fin des collisions `exemple-app` ≡ `exemple` (faux statut d'app).
- **Labels Docker dict/str** (`hub_state.py`) : `_docker_api_containers` gère maintenant le format `"Labels":{"key":"val"}` (certaines versions/API Docker le produisent) en plus du format comma-separated. Sans cela, l'ancien code plantait sur `AttributeError: 'dict' object has no attribute 'split'` → toutes les apps affichées « stopped ».
- **Timeouts `auto_detect`** (`auto_detect.py`) : `subprocess.check_output` appelé sans `timeout=` → ajout de `timeout=5`/`timeout=10` + catch `TimeoutExpired`. Évite que le boot gèle si le daemon Docker est dans un état dégradé.
- **Injection SQL `ALTER USER`** (`actions.py:278`) : extraction de `_build_alter_user_sql` (échappement des quotes + validation de l'identifiant SQL). L'ancienne interpolation `f"ALTER USER ... '{password}'"` cassait silencieusement le bootstrap si le mot de passe contenait une apostrophe.
- **Atelier création : garantie restart prod** (`actions.py`) : le corps de création est entouré d'un `try/except` — toute exception non gérée (ex : `shutil.copytree`, `docker volume create` sans catch) nettoie l'atelier et **redémarre la prod** au lieu de la laisser down.
- **`restore` sans traceback brut** (`__main__.py`) : la commande `restore` attrape désormais les exceptions prévisibles (archive corrompue, magic absent, `tarfile.ReadError`, `docker` absent) → message + exit 1.
- **Fuite de processus sur timeout** (`utils.py`) : `run_shell` (branche `stream=True`) ne tuait pas le fils sur timeout (`communicate(timeout=)` ne le fait pas). Désormais `proc.kill()` + `proc.communicate()` → plus d'orphelins docker/compose.
- **TOCTOU `cancel_current`** (`utils.py`) : le global `_current_proc` était lu deux fois (test + `.kill()`) → un worker parallèle pouvait le mettre à `None` entre-temps → `AttributeError` (pas catché). Fix : capture dans une variable locale.

### 🧪 Fiabilité — coffre, export, TUI

- **Export : manifest `hub_db: null`** (`park_export.py`) : si le dump de la base Hub échoue, le manifest pointe désormais sur `null` au lieu de `databases/hub.pgdump` (inexistant) → le restore n'abortait plus sans explication (« faux backup valide »).
- **`_safe_extractall` compat Python 3.10/3.11** (`park_restore.py`) : l'argument `filter="data"` de `extractall` n'existe qu'en 3.12+. Sur versions antérieures, on valide manuellement chaque membre (anti path-traversal + rejet des symlinks) avant extraction.
- **Échap ne quitte plus l'app** (`menu.py`) : `confirm` retourne le sentinel `ESC` (truthy) sur Échap. Les 3 appels `if confirm:` → `if confirm is True:` (strict).
- **UTF-8 invalide toléré** (`keys.py`) : en mode cbreak, un caractère multioctet peut arriver scindé en plusieurs `os.read` → `UnicodeDecodeError` non rattrapé → crash TUI. `_decode` ignore désormais ces séquences partielles.
- **Terminal restauré avant Live** (`canvas.py:close()`) : le `__exit__` du `Live` Rich était appelé AVANT `termios.tcsetattr`. Si `__exit__` levait, le terminal restait en mode cbreak (input sans écho). Désormais le tcsetattr est fait en premier, chaque étape dans son propre `try/except`.
- **Unités réseau corrigées** (`menu.py:_fmt_net`) : `1000 KB/s ≈ 1 MB/s` (et non 1 GB/s) ; ajout du palier Mo/s manquant. Barre et pourcentage disque désormais tous deux sur le % **utilisé** (plus de contradiction).

### 🧪 Tests

- **306 tests, 0 échec** (+16 depuis v0.25.3) : `_norm` (3), timeouts (2), `ALTER USER` (3), `restore` try/except (1), fuite proc + TOCTOU (3), extraction sûre (2), manifest `hub_db` null (1), UTF-8 invalide (1).

## [0.25.3] - 29 juillet 2026

### 📣 Pour les utilisateurs

- **Corrigé** : `hubctl` ne lagge plus — toutes les touches du clavier répondent désormais instantanément. Le tableau de bord recalculait des appels Docker et `git status` à chaque image (≈ 384 ms de blocage par frame), ce qui gelait la lecture du clavier.
- **Amélioré** : le coffre des secrets est désormais protégé contre la corruption — la sauvegarde est atomique et l'ancien coffre est automatiquement préservé dans un `.bak` récupérable.
- **Amélioré** : durcissement de sécurité du debug agent et de la restauration du parc (voir détail technique ci-dessous).

### ⚡ Performance — `hubctl` (lag des inputs)

- **Boucle de rendu non bloquante** (`menu.py`) : les builders du dashboard (`_build_services`, `_build_resources`) appelaient des fonctions bloquantes synchrones sur le thread de rendu à chaque frame — `docker info`, `docker compose ps`, et surtout `get_active_apps()` (`git status` × N + parcours récursif `_dir_size` × N), soit ≈ 384 ms/frame. Désormais un poll worker d'arrière-plan (`_state_poll_worker`) peuple un cache `_snap` (docker_ok, services, apps_count) lu instantanément par les builders. **Coût d'un render : 384 ms → 0,6 ms (×624).**
- **Amorçage du cache** (`__main__.py`) : l'état calculé par le preload de démarrage (jusqu'ici calculé puis jeté) amorce désormais le cache via `main_loop(..., initial_state=state)` → zéro appel bloquant supplémentaire au boot.

### 🔒 Sécurité — coffre & debug agent

- **Garde-fou SQL durci** (`debug_agent/debug_mcp.py`) : `psql -c` exécutait tous les statements séparés par `;`. Un payload `SELECT 1; COPY ... TO PROGRAM 'cmd'` (non couvert par l'ancienne denylist) permettait une **RCE sur l'hôte DB**, y compris en mode lecture seule. Nouveau `_validate_readonly_query` : interdit le chainage `;` + denylist étendue (`COPY`/`PROGRAM`/`DO`/`CALL`/`VACUUM`/`GRANT`/`REVOKE`/`MERGE`…).
- **`coffre.save()` atomique** (`coffre.py`) : l'écriture était directe (`write_bytes`) — un crash pendant la sauvegarde corrompait le coffre et **perdait tous les secrets du parc**. Désormais : écriture atomique (temp → fsync → `os.replace`, mode 0600) + backup `.bak` récupérable du coffre précédent.
- **`restore()` anti path traversal** (`coffre.py`) : un coffre importé d'une source externe pouvait écrire arbitrairement hors parc via un relpath `../../etc/cron.d/evil`. Garde `is_relative_to(PARC_ROOT)`.
- **`git clone` validé** (`coffre.py`) : l'URL Git issue du coffre est désormais validée (allowlist http/https/ssh/git@/git ; `file://` et chemins locaux interdits) pour empêcher le clonage d'un dépôt arbitraire (vecteur hooks/fsmonitor). Clone best-effort au lieu de `check=True` qui propageait.
- **`import_vault` validé** (`vault_manager.py`) : n'importe quel binaire pouvait remplacer le coffre (activant les failles ci-dessus). Désormais : vérif du magic `HUBCTLV1` + backup `.bak` du coffre courant.

### 🛡️ Robustesse — DB & parsing

- **Health check robuste** (`actions.py`) : l'ancien match littéral `'"status":"healthy"' in stdout` échouait sur `{"status": "healthy"}` (espaces après `:`, format `json.dumps` par défaut) → **faux négatif → rollbacks destructeurs** sur une API pourtant saine. Nouveau `_is_healthy_body` parse le JSON ; + catch `FileNotFoundError` (curl absent) + durée réelle via `time.monotonic()`.
- **`_restore_db` transactionnel** (`vault_manager.py`) : `TRUNCATE CASCADE` sans filet — un dump partiel/corrompu laissait la base **vidée sans recours** (users/apps/settings perdus). Désormais : snapshot live **avant** truncate + rollback automatique sur échec + log (plus d'échec silencieux).
- **Parser `.env`** (`env_manager.py`) : `export KEY=val` et `KEY = val` (espaces autour de `=`) étaient **ignorés silencieusement** → le secret correspondant n'était pas sauvegardé dans le coffre. Regex étendue.

### 🧪 Tests

- **290 tests, 0 échec** (+37 depuis v0.25.2) : garde-fou SQL (17), health check (6), atomicité coffre (3), path traversal + git_url (3), import_vault (3), restore_db transactionnel (2), parser `.env` (3), cache dashboard (déjà en place).

## [0.25.2] - 29 juillet 2026

### 📣 Pour les utilisateurs

- **Corrigé** : `hubctl` plantait au démarrage (module `re` manquant) et lors de la création d'un atelier avec base de données.
- **Corrigé** : `hubctl seed --prune` plantait lors de la suppression d'applications (fonction de suppression manquante).
- **Amélioré** : le tableau de bord affiche désormais la mémoire RAM et swap réelles (au lieu d'une métrique CPU trompeuse).
- **Amélioré** : la fluidité de l'interface terminal est nettement meilleure (taux de rafraîchissement réduit de 30 à 8 fps pour éviter la surcharge du terminal).

### 🐛 Fixes critiques — `hubctl`

- **`import re` manquant** (`actions.py`) : `NameError` au démarrage de `hubctl`. Le module `re` était utilisé (regex de validation, substitutions) mais jamais importé.
- **`run_shell()` non qualifié** (`actions.py`) : `NameError` lors de la création d'un atelier avec clone DB. Remplacé par `subprocess.run(...)` (cohérent avec le reste du fichier).
- **`action_remove_app()` inexistante** (`actions.py`) : `NameError` sur `hubctl seed --prune` confirmé. Fonction implémentée : `compose down -v` + backup tar.gz + `rmtree`.

### ⚡ Améliorations — dashboard & performance

- **Barre RAM corrigée** (`menu.py`) : `_build_resources` affichait le load average CPU étiqueté « RAM » et la swap hardcodée à 0. Nouvelle fonction `_mem_usage()` lisant `/proc/meminfo` → vraies valeurs RAM + swap.
- **Framerate terminal** (`canvas.py`, `menu.py`) : `refresh_per_second` réduit de 30 à 8 (le défaut Rich est 4) ; ajout d'un throttle de rendu (250 ms) dans `main_loop` pour éviter l'étranglement du terminal. Cohérent avec le pattern existant de `stream_command()` (4 fps).
- **Fuite de descripteur de fichier** (`actions.py` : `_db_snapshot`) : `stdout=open(path, "w")` jamais fermé → encapsulé dans `with open(...) as f:`.

### 🧹 Nettoyage & tests

- **Code mort supprimé** : `_port_in_use()`, `_ui_state`, `_cpu_load()` (rendu mort par la correction RAM), double définition `_console = Console()`.
- **Tests réparés** : suppression de `test_menu_tree_contains_all_actions` (obsolète, menu refactorisé) ; mock manquant de `_sync_db_password_if_needed` dans `test_bootstrap_does_not_leak_password` (causait un pend de 60 s) ; les tests `test_seed_prune_*` fonctionnent désormais grâce à l'implémentation de `action_remove_app`.
- **253 tests, 0 échec.**

## [0.25.1] - 23 juillet 2026

### 📣 Pour les utilisateurs

- **Ajouté** : `hubctl seed <fichier.yaml>` — déploie ou met à jour toutes les applications listées dans un fichier YAML en une seule commande. Idéal pour initialiser un nouveau serveur ou synchroniser un parc complet.
- **Ajouté** : `--dry-run` et `--prune` — simulez avant d'exécuter, et nettoyez les apps absentes du fichier seed.
- **Corrigé** : le port HTTPS frontend (`FRONTEND_HTTPS_PORT`) n'était pas renseigné dans les `.env` générés pour les nouvelles applications, ce qui pouvait bloquer le build Docker.

### 🔧 Correction — `FRONTEND_HTTPS_PORT` manquant dans les `.env` générés

- **`_write_app_env`** : ajout de `FRONTEND_HTTPS_PORT = FRONTEND_PORT + 1` dans les substitutions du `.env` généré. Évite le timing Makefile où `make sync-env` écrit la valeur mais `docker compose build` ne la voit pas (le `include .env` est lu au démarrage de make).

## [0.25.0] - 23 juillet 2026

### ⚡ Nouvelle commande `hubctl seed` — déploiement batch déclaratif d'applications

- **`hubctl seed <fichier.yaml>`** : déploie/converge un ensemble d'applications depuis un fichier YAML déclaratif, en mode batch non-interactif et best-effort.
- **3 cas de déploiement** : nouvelle app (clone + init), app clonée non-initialisée (pull + init), app déjà déployée (pull + build + up, `.env` préservé).
- **`--prune`** : supprime les apps présentes mais non listées dans le fichier (confirmation Oui/Non).
- **`--dry-run`** : simule sans exécuter.
- **Rapport final** Rich avec ✓/✗ par app et code de sortie (0 si tout OK, 1 si échec).
- **Fonctions isolées et testables** : `_load_seed_file`, `_seed_one_app`, `_seed_prune`, `action_seed`, `_seed_report` — réutilisation massive des helpers existants.
- **`seed-apps.yaml`** : fichier d'exemple à la racine du parc (8 apps du parc courant).
- **Tests** : +308 lignes de tests unitaires TDD (416 tests au total, 0 régression).

## [0.24.8] - 22 juillet 2026

### 🧹 Tooling — nettoyage plugin + sync outillage Hub

- **Plugin `hub.ts`** : retrait de 2 regex destructrices mortes (`hub_pki_revoke`, `hub_user_reset_password`) — ces outils n'existent plus dans le catalogue hub-mcp v0.3.0.

### ⚙️ Sous-modules

- **hub-mcp → v0.3.0** (`9774f57`) : resynchronisation des outils MCP avec les routes réelles du Hub v3.12 — 4 remappages (`config`, `admin_settings`, `admin_ports_status`, `backup_trigger`) + 12 suppressions d'outils sans route réelle (`pki_*`, `design_*`, `admin_info`, `admin_dns_status`, `discovery_proxy`, `backup_export_env`/`import_env`, `user_reset_password`). Catalogue : 77 → 65 outils. Modèle de permissions documenté (mode app = token Service Account → `403` sur les endpoints utilisateurs ; mode standalone = token admin).
- **HUBapp_TEMPLATE_base → v2.6.3** (`00ce80f`) : skill `hub-mcp-usage` réécrit (65 outils, section « Modèle de permissions SA/standalone », badges 🔓/🔒) + plugin `hub.ts` synchronisé.

## [0.24.7] - 21 juillet 2026

### 🐛 Fix — hub-mcp standalone : suivi des redirects HTTP

- **hub-mcp** : le client standalone (`standalone_client.py`) ne suivait pas les redirects HTTP → les routes FastAPI sans trailing slash (`/api/apps` → `307 /api/apps/`) retournaient un body vide et cassaient les outils concernés (ex: `hub_app_list`). Ajout de `follow_redirects=True`. Validé : `hub_app_list` retourne désormais `canari` depuis le méta-repo.

### ⚙️ Sous-module hub-mcp → v0.2.1

- Mise à jour vers `7897f0a` (v0.2.1).

---

## [0.24.6] - 21 juillet 2026

### ⚡ hub-mcp désormais actif au méta-repo (mode standalone)

- **hub-mcp** : nouveau mode standalone (`hub_mcp/standalone_client.py`, client HTTP httpx) permettant de piloter le Hub depuis le méta-repo POULIDOR **sans dépendre du `backend` d'une app**. Fallback transparent dans `_LazyHubClient` (mode app prioritaire, puis standalone). Contrat `call_hub_endpoint` identique → `tools.py` inchangé.
- **opencode.json** : déclaration du serveur MCP `hub` au niveau du méta-repo (`cd hub-mcp && python3 -m hub_mcp.server`). Les creds (`HUB_BASE_URL` / `HUB_ADMIN_USERNAME` / `HUB_ADMIN_PASSWORD`) viennent de `.secrets` (gitignoré, sourcé via `~/.bashrc`) → non versionnés.
- Jusqu'ici, seul `zai-mcp-server` était actif au méta-repo (hub-mcp étant conçu pour tourner depuis une app). Désormais les ~85 outils du Hub sont pilotables depuis n'importe quelle session méta-repo.

### ⚙️ Sous-module hub-mcp → v0.2.0

- Mise à jour vers `5438c30` (v0.2.0).

---

## [0.24.5] - 21 juillet 2026

### 🐛 Fix — `install.sh` robuste au piège du socket Docker invalidé par apt

- **install.sh** : lors d'un fresh install, si `apt` (Phase 1) (ré)installait un paquet `docker-ce`, le fichier unit `docker.socket` était écrasé à chaud → systemd invalidait le socket ("not functional until restarted") → `systemctl start docker` (Phase 2b) échouait avec rate-limit. Fix : on insère `daemon-reload` + `reset-failed` + `start docker.socket` avant le démarrage du service. Commandes idempotentes (inoffensives si apt n'a rien réinstallé). Bug observé et contourné manuellement lors du fresh install de cette session.

---

## [0.24.4] - 21 juillet 2026

### 🐛 Fix — INITIALISE.py (template) mode clean cassait le code des nouvelles apps

- **Template** : le mode `--clean` (défaut) d'`INITIALISE.py` produisait une app qui ne démarrait pas — `_clean_models()` réécrivait `models.py` en dur en omettant le modèle core `OutboxMessage` (→ `ImportError`), et `_clean_main()` laissait un bloc `if ENABLE_DEMO_ENDPOINTS:` orphelin (→ `IndentationError`). Refactor en nettoyage **ciblé** (regex sur `Item`/`TestData` uniquement, préservation de tous les modèles core). Validé : app canari créée en mode clean démarre et s'inscrit au Hub.

### ⚙️ Sous-module HUBapp_TEMPLATE_base → v2.6.2

- Mise à jour vers `3629aa6` (v2.6.2).

---

## [0.24.3] - 21 juillet 2026

### 🐛 Fix — fresh install du Hub cassé par NotNullViolation sur m2m_enforcement_mode

- **Hub** : le fresh install (DB vierge) échouait sur la migration `026_add_backup_clusters_and_system_app.sql` (`NotNullViolationError` sur `m2m_enforcement_mode`). La colonne était `nullable=False` avec un `default='compat'` Python uniquement ; `Base.metadata.create_all()` créait la colonne sans default SQL → l'INSERT de l'app système violait la contrainte. Fix : `server_default='compat'` sur `models.Application.m2m_enforcement_mode`. Bug latent depuis la 3.12.1 (n'apparaissait que sur DB vierge, pas sur DB existante).
- **Hub** : nettoyage — 3 snapshots chiffrés (`.enc`) étaient trackés par erreur dans `storage/snapshots/` ; retirés du tracking + `storage/snapshots/` ajouté au `.gitignore`.

### ⚙️ Sous-module HUB_base → v3.12.3

- Mise à jour vers `6d84bcd` (v3.12.3).

---

## [0.24.2] - 21 juillet 2026

### ⚡ Sécurité M2M — extension du garde SA/slug à 3 routes Hub supplémentaires

- **Hub** : `authorize_service_account_slug()` appliqué à `PUT /api/apps/me/shared`, `POST /api/apps/me/openapi` et `POST /api/messages/m2m/send` (partage, spec OpenAPI, synchronisation) — slugs non possédés audités en `compat` (défaut), refusés en `enforced` (403). Conforme au design Lot 1 « Autorisation M2M centralisée ».

### ⚙️ Sous-module HUB_base → v3.12.2

- Mise à jour vers `16aff93` (v3.12.2).

---

## [0.24.1] - 19 juillet 2026

### ⚡ Release 1 — sécurité M2M et stabilité

- **Hub** : mode M2M par application (`compat`/`enforced`), garde SA/slug, audit des réinscriptions legacy, outbox admin-only avec livraison `2xx` exclusive.
- **Template** : AuthProvider corrigé (TDZ supprimée), outbox réalignée, preuve M2M en cache lors de la réinscription.
- **Docs** : procédure canari volontaire `MIGRATION_M2M_CANARY.md` ; flux legacy tagués `🔶 LEGACY`.

### ⚙️ Sous-module HUB_base → v3.12.1

- Mise à jour vers `b684457` (v3.12.1).

### ⚙️ Sous-module HUBapp_TEMPLATE_base → v2.6.1

- Mise à jour vers `4482887` (v2.6.1).

---

## [0.24.0] - 18 juillet 2026

### ⚡ Design d'audit Hub/template, release M2M et durcissement TLS

- **Ajouté** : design complet d'audit et de remédiation progressive Hub/template (`docs/superpowers/specs/2026-07-18-hub-template-remediation-design.md`).
- **Ajouté** : plans d'implémentation détaillés Release 1/2/3.
- **Ajouté** : `.worktrees/` ignoré globalement.

### ⚙️ Sous-module HUB_base → v3.12.0

- Mise à jour du pointeur vers `98a70ed` (v3.12.0) : dépendances M2M (AppDependency, POST/GET /api/apps/dependencies, sync-report), section admin SPA, et durcissement TLS (server.key 0640 avec groupe hôte partagé, suppression des capacités frontend excessives).

### ⚙️ Sous-module HUBapp_TEMPLATE_base → v2.6.0

- Mise à jour du pointeur vers `7ac4212` (v2.6.0) : déclaration `depends.yaml`, `HubClient.report_sync()`, push non-bloquant des dépendances au registre, skill `app-dependencies`.

---

## [0.23.5] - 18 juillet 2026

### ⚡ Sécurité hubctl — durcissement coffre, permissions, dry-run et validation

- **Sécurité** : `sync()` supprime les entrées obsolètes d'apps supprimées et ignore les répertoires symlinkés (`coffre.py`, `vault_manager.py`).
- **Sécurité** : `unlock()` ne corrompt plus l'état interne sur mauvais mot de passe.
- **Sécurité** : `_write_app_env()` et les nouvelles sauvegardes (tar.gz, SQL) appliquent `chmod 0600` ; 28 fichiers existants durcis (`.env`, archives, dumps).
- **Corrigé** : `_sync_app_coffre()` utilisait l'ancien chemin `.coffre` et appelait `backup_app_env()` (méthode inexistante) — basculé sur `VaultManager.backup_all()`.
- **Corrigé** : `--dry-run` global (`global_dry_run`) n'est plus écrasé par les sous-parsers ; `update`/`start`/`stop`/`deploy`/`vpn on/off` propagent correctement le mode simulation.
- **Corrigé** : `_compose_file()` rejette les chemins absolus et `..` (prévention traversée de répertoire).
- **Corrigé** : validation des slugs dans toutes les commandes (`work`, `ship`, `update`, `logs`, etc.) — rejet des `/`, `..`, chemins absolus.
- **Corrigé** : `--dev` et `--prod` sont désormais mutuellement exclusifs.
- **Corrigé** : `action_bootstrap()` n'imprime plus le mot de passe admin en clair dans la console.
- **Tests** : +16 tests de régression couvrant chaque correction.

---

## [0.23.4] - 17 juillet 2026

### ⚡ Fix hubctl — prévention fuite "skipped" + label français

- **Corrigé** : `hubctl` laissait fuiter les éléments marqués "skipped" vers l'API.
- **Corrigé** : le label du bouton d'annulation était en anglais, passé en français.

### ⚙️ Sous-module HUB_base → v3.11.2

- Mise à jour du pointeur de sous-module vers `bd9ff79` (v3.11.2) : fix SSE (`sub→user_id`), régénération du secret M2M pour les apps existantes, fix PKI (`server.key` 0o644 pour nginx).

---

## [0.23.3] - 14 juillet 2026

### 📝 README — refonte présentation du projet

- **Refonte** : le README passe de 286 à ~80 lignes. Simplification radicale : suppression
  des murs de commandes `make`, des tables de keybindings TUI et des schémas ASCII de
  workflows — tout est délégué aux docs `docs/guide-hub/`.
- **Corrigé** : le workflow Workshop décrivait l'ancien modèle « move » (obsolète depuis
  v0.21.0). Remplacé par une présentation « sandbox + deploy ».
- **Corrigé** : l'installation pointait vers `./install.sh` (obsolète depuis v0.23.0).
  Remplacé par `./hubctl init`.
- **Ajouté** : section « Pourquoi POULIDOR ? », démarrage rapide en 4 commandes, et
  table de liens vers les docs détaillées.

---

## [0.23.2] - 14 juillet 2026

### ⚡ Fix init — docker compose down avec cwd correct

- **Corrigé** : `_cleanup_existing_hub_containers` exécutait `docker compose down` depuis la racine POULIDOR au lieu de `HUB_base/` → docker compose ne trouvait pas le `.env` → échec silencieux sur les variables `:?` → les anciens conteneurs n'étaient pas nettoyés.
- Fix : ajout de `cwd=str(hub_state.HUB_DIR)` au `subprocess.run` pour que docker compose résolve `.env` correctement.

---

## [0.23.1] - 14 juillet 2026

### 📣 Pour les utilisateurs (devs hubctl)

- **Corrigé** : `hubctl init` nettoie désormais les anciens conteneurs avant de démarrer le Hub. Plus d'erreur « container name already in use » si une instance précédente occupe encore les noms `hub-db`, `hub-api`, `hub-frontend`.

### ⚡ Fix init — nettoyage des conteneurs orphelins

- **`_cleanup_existing_hub_containers(console, *, dry_run)`** : exécute `docker compose down` (gracieux, préserve les volumes) puis inspecte les noms `hub-db`, `hub-api`, `hub-frontend` et force-remove les orphelins issus d'un autre projet compose.
- Appelé dans `action_bootstrap()` entre la génération des clés JWT et le `make up-prod`.
- Tests : 3 nouveaux (compose down + rm orphelins, dry-run no-op, pas de rm si aucun orphelin).

---

## [0.23.0] - 14 juillet 2026

### 📣 Pour les utilisateurs (devs hubctl)

- **Ajouté** : `hubctl init` — un clone frais, une commande, et le Hub tourne. Plus besoin de lancer `install.sh` à la main, de générer le `.env`, ni de débugger les perms SSL. `hubctl init` fait tout : génération des secrets, build, démarrage, vérification santé, et affichage des identifiants admin.
- **Ajouté** : `hubctl init --force` pour écraser un `.env` existant sans confirmation (pratique en CI ou rebuild).
- **Corrigé** : le frontend nginx ne crashe plus au premier démarrage à cause des permissions du certificat SSL — corrigé à la source dans `pki.py`.

### ⚡ `hubctl init` — bootstrap automatique du Hub

- **`_detect_host_ip()`** : détection automatique de l'IP hôte (UDP socket vers 1.1.1.1:80, fallback `127.0.0.1`).
- **`_generate_dotenv(console, *, force, dry_run) -> dict | None`** : génération de `HUB_base/.env` avec secrets aléatoires (PostgreSQL, admin, Fernet, PKI, CORS, whitelist). Idempotent : si `.env` existe déjà, confirmation interactive avant écrasement ; `--force` écrase sans confirmation. Couvre toutes les variables obligatoires (`:?`) et optionnelles du `docker-compose.yml`.
- **`action_bootstrap(console, *, force, dry_run) -> int`** : orchestre le flux complet — check Docker → génération `.env` → clés JWT (`_ensure_jwt_keys`) → `make up-prod` → health check (polling `/api/health`, timeout 120s) → résumé (table Rich avec URLs + credentials admin).
- **CLI** : sous-commande `init` avec flag `--force`, dispatch dans `__main__.py`. Coexiste sans conflit avec le flag `--init` existant (clonage repos depuis `manifest.json`).
- **Sous-module HUB_base** pointer vers `f3bde58` (fix pki.py : clé serveur `0o600` → `0o644`, nginx peut enfin lire le certificat).
- Tests : 16 nouveaux (284 total, 0 régression). TDD attesté pour chaque nouvelle fonction.

---

## [0.22.0] - 14 juillet 2026

### 📣 Pour les utilisateurs (devs hubctl)

- **Ajouté** : `hubctl vpn {sync,status,on,off}` pour piloter le conteneur WireGuard depuis le shell. Le conteneur ne tourne désormais que si le VPN est activé.
- **Changé** : au démarrage du Hub (`hubctl start`), le conteneur WG démarre automatiquement si le VPN est activé, et reste arrêté sinon — fini le conteneur `Up` à vide pendant des jours (RAM + surface `NET_ADMIN`/`SYS_MODULE` économisées).
- **Corrigé** : sur Debian/Mint/Ubuntu, `./hubctl` démarre proprement même si `python3-venv` n'est pas installé — le launcher détecte le venv sans pip et se reconstruit, avec un message actionnable (`sudo apt install python3 python3-venv python3-pip`). Plus de crash silencieux à la ligne 16 sur machine neuve.

### ⚡ `hubctl vpn` + réconciliation host-level WireGuard

- **`action_vpn(console, subcmd, *, dry_run=False)`** + 7 helpers : `_vpn_read_enabled` (psql `app_settings`), `_vpn_conf_exists` (alpine `test -f /vpn/wg_confs/wg0.conf`), `_vpn_container_state` (`docker inspect`), `_vpn_set_enabled` (UPSERT psql), `_vpn_compose_up`/`_vpn_stop` (`utils.run_shell`, dry_run natif), `_vpn_reconcile`.
  - `sync` : lit `vpn_enabled` en DB, démarre (`docker compose --profile wireguard up -d wireguard-client`) ou arrête (`docker stop hub-wireguard`). Idempotent. Retry psql si `hub-db` pas prêt.
  - `status` : flag DB + état conteneur + `wg show`.
  - `on`/`off` : UPSERT du flag + reconcile. `on` avertit si pas de `wg0.conf` ; `off` ne supprime pas la conf (job de l'UI toggle).
- **Hook de boot** : `action_start_stop("start","hub")` appelle `action_vpn(console,"sync",dry_run=dry_run)` après `make up-prod` réussi (rc-gated), dans un `try/except` (échec VPN non bloquant).
- **Argparse** : sous-commande `vpn` (`choices=[sync,status,on,off]`), `--dry-run` global supporté.
- **Sous-module HUB_base** pointer vers v3.11.0 (`restart: "no"` sur `wireguard-client` + bandeau UI informatif).
- **Hub-api reste durcie** : **aucun** mount du socket Docker (approche Y — le cycle de vie est host-level via hubctl, pas via l'API). Aucun `docker compose down -v`.
- Tests : 16 nouveaux (`test_vpn_*` sync/status/on/off + helpers + hook boot rc-gate/non-bloquant + dispatch + choices).

### 🛠 Launcher `hubctl` — robustesse d'installation sur machine neuve

- **Corrigé** : le launcher (`hubctl` racine) créait un venv via `python3 -m venv` puis appelait `$VENV/bin/pip` — sur Debian/Mint/Ubuntu avec seulement `python3` (sans `python3-venv`), `ensurepip` est absent → venv créé **sans pip** → crash ligne 16 (« aucun fichier ou dossier de ce nom ») sans indiquer quoi installer.
- **Détecté & auto-résolu** : (1) check `command -v python3` en entrée avec message `apt install python3 python3-venv python3-pip` ; (2) détection d'un venv existant sans pip utilisable (`$PY -m pip --version` échoue) → suppression + reconstruction automatique ; (3) post-création, vérification que pip est bien présent, sinon message explicite + nettoyage du venv cassé.
- **Robustesse** : utilisation de `$PY -m pip` (forme module via le python du venv) au lieu de `$VENV/bin/pip`.

## [0.21.0] - 14 juillet 2026

### 📣 Pour les utilisateurs (devs hubctl)

- **Changé** : le `[←]` du menu Workshop ne **clone plus la BDD** par défaut. Il
  fait désormais un `git pull` du code uniquement — la BDD de prod est
  **préservée**. C'était l'attente : toucher à une BDD de prod est rare, ça ne
  doit plus être le cycle par défaut.
- **Changé** : quand tu mets une app en atelier (`[→]`), la prod n'est **plus
  supprimée** — elle est stoppée et laissée en place. Tu peux donc la remettre
  en route via un simple `git pull`.
- **Ajouté** : nouvelle action `[×] Supprimer l'atelier` (nettoie la sandbox
  quand tu n'en veux plus, et redémarre la prod).
- **Ajouté** : pour le cas rare où tu veux VRAIMENT écraser la BDD de prod par
  celle de l'atelier, c'est désormais explicite en CLI uniquement :
  `./hubctl ship <app> --copy-db` (avec confirmation en tapant le slug).
- **Renommé** : `[←] Remettre en production` → `[←] Déployer vers la prod`.

### ⚡ Refonte du cycle Workshop — modèle « sandbox + deploy »

Remplacement du modèle « move » (l'app basculait physiquement entre `APPS/` et
`APP_Workshop/`, la prod était supprimée et la BDD clonée à chaque cycle) par
un modèle « sandbox + deploy » : la prod reste en place (stopée), l'atelier est
une sandbox parallèle conservée entre les cycles, et « shipper » = pousser le
code vers la prod via `git pull` (BDD intacte). La copie de BDD devient
l'exception explicite (`--copy-db`, CLI-only).

- **`action_workshop_create`** (`[→]`) : clone la prod (code + volume Postgres)
  vers `X-ws`, stoppe la prod mais la laisse en place (plus de backup/trash).
  Rollback propre : `down` atelier + `rmtree` + restart prod en cas d'échec
  build/health. Réutilise `_health_check(port_override=...)` (acceptation
  stricte `status:healthy`, pas n'importe quel 2xx).
- **`action_prod_deploy`** (`[←]` défaut, `copy_db=False`) : `git pull` code-only
  via `make build`/`make up`, BDD **jamais touchée**. Warnings non bloquants de
  git-hygiène (atelier sale, commits non poussés). Rollback via
  `_rollback(snapshot=None)` → `git reset --hard {prev}` + rebuild.
- **`action_prod_deploy_copy_db`** (`[←] --copy-db`, CLI-only) : chemin destructif
  — backup volume (`alpine tar`) + overwrite (`docker volume rm`/`create` +
  `alpine cp`) + `git pull` + rollback restore. Gate forte `input()` (doit taper
  le slug exact). **Restore SYMÉTRIQUE** du volume (mount `dst_vol:/data` +
  `tar xzf - -C /`) — corrige un bug Critical où la restore était un no-op
  (montage `/to` asymétrique → les fichiers atterrissaient dans l'overlay du
  conteneur, pas dans le volume).
- **`action_workshop_remove`** (`[×]`) : supprime la sandbox
  (`docker compose down -v` — **seul usage légitime de `-v`** dans tout le cycle
  Workshop) + backup `tar.gz` + corbeille + restart prod.
- **Refactor** : suppression de l'ancienne `action_workshop_move` (9 étapes × 2
  sens, trop de responsabilités) au profit de 3 fonctions ciblées à signature
  uniforme `(console, …, *, dry_run=False)`. Couverture préservée (2 tests de
  remplacement réels pour les cas dev-mode-manquant et source-manquante).
- **CLI** : `action_work`/`action_ship` rewirés vers les nouvelles fonctions ;
  `ship` gagne `--copy-db` ; `--dry-run` enfin threadé sur `work`/`ship` (était
  silencieusement ignoré avant).
- **Menu** (`_workshop_menu`) : double entrée `[←]`/`[×]` par app atelier, ligne
  `⏸ (en atelier)` pour les apps dont la prod est stoppée, footer informatif
  pour `--copy-db` (pas de choix direct — conforme à « explicite en CLI »).
- **Skill `app-workshop-mover`** réécrit pour refléter le nouveau modèle
  (défaut `git pull`, `--copy-db` avancé, `[×]`, exigence de symétrie restore).
- **Sécurité** : `docker compose down -v` confiné à `action_workshop_remove`
  par test (`test_workshop_create_never_uses_down_with_v`) + grep.
- Tests : 250 verts (refonte complète TDD, 1 `tarfile` DeprecationWarning
  préexistant non lié).

## [0.20.0] - 13 juillet 2026

### 🎨 Doc client & structuration des secrets

- **Ajouté** : `docs/canvas-poulidor.html` — canvas client standalone (schéma double-vue métier / service info, tokens HUBCSS, zéro dépendance externe). Première représentation visuelle du fonctionnement du parc destinée aux prospects.
- **Ajouté** : `.secrets.example` — template (committé) de la source unique des secrets d'API IA (DeepSeek, Anthropic, Z_AI). Documente les variables attendues par l'écosystème.
- **Modifié** : `.gitignore` ignore désormais `.secrets` (la source unique des clés API, à ne jamais committer ; `.secrets.example` reste suivi).
- **Pourquoi** : le canvas donne enfin un support pédagogique client (vue métier pour décideurs, vue service info pour DSI) ; la structuration `.secrets` centralise les clés API précédemment éparpillées dans `TEMPLATE_CODE/apiCC` (supprimé), avec sourcing automatique via `~/.bashrc`.

## [0.19.1] - 13 juillet 2026

### 🛠 Coffre — confirmation de la passphrase à la création

- **`menu._require_vault`** : à la création du coffre, la passphrase est
  désormais demandée **deux fois** (saisie + confirmation). Si les deux saisies
  ne correspondent pas, l'utilisateur est invité à recommencer (message
  « Les passphrases ne correspondent pas »). La passphrase vide reste rejetée.
- **Pourquoi** : auparavant la création ne demandait la passphrase qu'une seule
  fois — une typo silencieuse rendait le coffre définitivement inaccessible
  (passphrase irrécupérable par design). C'est la cause racine d'un incident
  réel (coffre recréé depuis le disque). La confirmation aligne la création sur
  le pattern déjà utilisé par `change_passphrase` et `park-export`.
- Tests : 2 nouveaux (`test_require_vault_create_confirms_and_rejects_mismatch`,
  `test_require_vault_create_empty_then_valid`) + 1 existant adapté.

## [0.19.0] - 12 juillet 2026

### ⚡ hubctl « atout dev » + « sécurité prod » — vague quick wins

Refonte ciblée pour faire de `hubctl` un outil adopté par les dev (et non une
contrainte) tout en comblant les sécurités prod prévues non implémentées.

**Cibles dev (4 sous-commandes CLI non-interactives)** — comblent la fracture
`make` ↔ `hubctl` :
- `./hubctl logs <cible> [--api|--db|--frontend]` — logs filtrables par service
  (délègue à `docker compose logs`).
- `./hubctl restart <cible> [api|frontend]` — redémarrage granulaire (défaut :
  tous les services).
- `./hubctl health <cible> [--detailed]` — `GET /api/health` (+ détaillé),
  exit 0 si sain.
- `./hubctl db-shell <app>` — shell `psql` interactif d'une app.

**Blue-green `deploy` (prod safe, zéro downtime)** — la grosse sécurité prod
qui manquait :
- `./hubctl deploy <cible>` — instance verte sur ports+1 → health check → swap.
  `--validate` pour validation humaine avant swap (œil dans le navigateur).
  `--dry-run` pour simuler.
- Helpers : `_find_free_ports`, `_port_in_use`, `_db_snapshot_app`,
  `_read_prod_ports`, `_build_test_env`.
- `update` **inchangé** (flow en place, rapide, pour le dev/atelier).

**Sécurités annexes** — comblent des écarts spec↔code :
- **Retypage du nom pour supprimer une app** (`widgets.confirm_by_typing`) —
  la spec §9 prévoyait « retaper le nom exact », le code faisait juste
  Oui/Non. Corrigé.
- **Génération automatique des clés JWT** (`_ensure_jwt_keys`) — hubctl génère
  `jwt_private_key.pem` / `jwt_public_key.pem` (`openssl genrsa`/`rsa -pubout`)
  au lieu de juste avertir. Fini le « exécutez install.sh à la main ».

**Fixes post-review (qualité prod)** :
- `deploy` blue-green : propagation `env=test_env` au conteneur vert (C1),
  health check sur le port test via `port_override` (C2), `_rollback` cible
  la bonne DB selon hub/app via `db_container`/`db_name` (C3), pipe du
  snapshot SQL via `input=snapshot.read_bytes()` (C4), `import sys` (C5).
- `deploy --dry-run` : `_rollback` propage `dry_run` (C6 — sinon `git reset
  --hard` + `make build` exécutés pour de vrai), health checks simulés en
  dry_run (C7), snapshot skippé en dry_run (C8).

**Outillage** : `utils.run_shell` accepte désormais un paramètre `env=` pour
les overrides de variables d'environnement (blue-green).

**Docs** : `docs/guide-hub/hubctl.html` (section « Dev (cibles granulaires) »
+ doc `deploy`) et `make.html` (note hubctl) mis à jour.

## [0.18.2] - 12 juillet 2026

### 🛠 guide-hub : resynchronisation de la version affichée

- `docs/guide-hub/assets/guide.js` : constante `PARC_VERSION` passée de
  `0.14.0` (obsolète) à la version courante du parc. Ajout d'un commentaire
  pointant vers le fichier `VERSION` comme source de vérité, pour éviter la
  re-désynchronisation lors des futures releases.
- Impact : les footers des pages du guide (`data-parc-version`) affichent
  désormais la bonne version.

## [0.18.1] - 12 juillet 2026

### ⚡ Guides hubctl & make exhaustifs (docs/guide-hub)

- **hubctl.html** : flags complets (`--anim`, `--dev`, `--prod`) + variable
  `HUBCTL_MODE` + comportement non-TTY ; nouvelle section « Sous-commandes CLI
  non interactives » (`status`, `start`/`stop hub|<slug>`, `update` avec
  rollback auto + health check, `work`/`ship`, `park-export`/`park-restore`,
  agent `debug`) ; détail des sous-choix internes du menu TUI ; garde-fous
  complétés (rollback automatique sur `update`, confirmation par retaper le
  slug sur `ship`).
- **make.html** : distinction des deux familles de Makefile ; nouvelle section
  `HUB_base/Makefile` (hub central : `build`, `up-prod`, `up-dev`, `down`,
  `logs`, `ps`) ; Makefile d'app restructuré et complété (SSL/env, cycle de
  vie, logs, tests & santé, base de données, initialisation/index IA, design
  system/outillage Hub) ; section « Hors make, pas sur hubctl » (scripts
  racine, HUBCSS `npm run build`/`demo:dev`, sous le capot `allocate_ports.py`
  / `INITIALISE.py`).
- Constat (hors release) : `guide.js` porte `PARC_VERSION = "0.14.0"`
  (obsolète vs 0.18.x) — non corrigé, hors périmètre.

## [0.18.0] - 10 juillet 2026

### ⚡ Catalogue M2M exportable — blueprint pour IA de dev

- **HUBapp_TEMPLATE_base** v2.4.4 → v2.5.0 : nouvel endpoint `GET /api/m2m/catalog`
  (auth service account) — auto-introspection de la surface d'API de l'app
  (paths, méthodes, schémas résolus, niveaux d'auth). Module `m2m_catalog.py`
  (`deduce_auth_level`, `resolve_refs`, `build_app_catalog`) + tagging
  `__auth_level__` des closures d'auth.
- **HUB_base** v3.9.9 → v3.10.0 : nouvel endpoint `GET /api/apps/m2m-catalog/export`
  (admin-only) — agrège le catalogue de toutes les apps partagées en un fichier JSON
  téléchargeable, destiné à être filé à une IA de dev pour générer/injecter des
  fausses données en environnement dev/test. Agrégation parallèle, fallback
  heuristique OpenAPI, aucune donnée secrète exportée.
- **Docs** : spec `docs/superpowers/specs/2026-07-10-m2m-catalog-export-design.md`
  + plan `docs/superpowers/plans/2026-07-10-m2m-catalog-export.md`.

## [0.17.1] - 10 juillet 2026

### ⚡ Mise à jour HUB_base v3.9.9 — pool SQLAlchemy réduit

- **HUB_base** v3.9.8 → v3.9.9 : `database.py` — pool_size réduit de 10→5,
  max_overflow de 20→10. Aligne le Hub sur le template `HUBapp_TEMPLATE_base`,
  prévient le risque `too many clients` PostgreSQL.

## [0.17.0] - 8 juillet 2026

### 🧠 Compétences Hub & M2M pour Jellycode

- **Skill `create-hub-app` (parc)** : workflow complet de création/scaffold d'une
  app Hub — collecte → `create_app.sh` → `INITIALISE.py` (14 étapes) →
  allocation ports → `make dev` → healthcheck → conventions backend
  (`DateTime(timezone=True)`, `TIMESTAMPTZ`, `TZ=UTC`, etc.).
- **Skill `hub-m2m-communication` (template)** : M2M inter-apps — discovery
  (`discover_services`), appel (`call_discovered_service` avec `X-Slug` + retry
  401 + fallback outbox), exposition d'endpoints SA (`require_service_account`),
  flag `IS_SHARED`.
- **Skill `hub-notifications` (template)** : notifications app→utilisateur —
  `send_user_message` → `POST /api/messages/m2m/send`, SSE temps réel
  (`EventSource` avec `?token=JWT`), composants `MessageBanner`/`MessageArchive`,
  accusés de lecture, action URL relatives.
- **Skill `hub-mcp-usage` (template)** : catalogue des ~85 outils MCP `hub_*`
  (apps, users, messages, backups, discovery, audit, design-system, PKI, admin)
  avec cas d'usage typiques.
- **Charte Jellycode** (`.opencode/agent/jellycode.md`) : 4 skills ajoutés aux
  listes parc (3→4) et app (9→12). **HUBapp_TEMPLATE_base** v2.4.4 → inclut
  les 3 nouveaux skills template dans `.opencode/skills/`.

## [0.16.2] - 7 juillet 2026

### 🩺 Correction vue santé des apps (NaNh + faux « Degraded »)

- **HUB_base (apps_health.py)** : la sonde HTTP ne marque plus les 4xx comme
  « degraded » — seuls les 5xx le sont. Les apps sans endpoint `/health`
  standard (Vaultwarden, etc.) étaient faussement « degraded » alors qu'elles
  répondent en 9-16ms. HUB_base v3.9.8.
- **HUB_base (apps-health.js)** : le timestamp `checked_at` doublait le `Z`
  (`"2025-...ZZ"` → `NaNh`). Correction + affichage amélioré : note « Serveur
  joignable — pas d'endpoint /health standard » pour les apps online sans
  health endpoint.

## [0.16.1] - 7 juillet 2026

### 🔒 action_ship : confirmation obligatoire avant remplacement DB prod

- **`./hubctl ship <slug>`** remplaçait silencieusement la DB de production
  par celle de l'atelier. Ajout d'un prompt de confirmation : l'utilisateur
  doit retaper le slug pour valider. Pas de `--yes` ou `--force`. Pour
  déployer le code sans toucher la DB, utiliser `./hubctl update <slug>`.

## [0.16.0] - 7 juillet 2026

### ✨ Sous-commandes CLI + auto-détection mode DEV/PROD

- **Nouvelles commandes CLI quotidiennes** : `./hubctl status` (vue d'ensemble),
  `./hubctl work <slug>` (atelier + clone DB + start), `./hubctl ship <slug>`
  (retour en prod), `./hubctl update hub|<slug>` (mise à jour avec rollback),
  `./hubctl start/stop hub|<slug>` (démarrage/arrêt). Toutes non-interactives,
  pour développeur averti.
- **Auto-détection du mode** : `APP_Workshop/` contient des apps → DEV, sinon
  → PROD. Plus de question systématique au démarrage. `--dev`/`--prod` ou
  `HUBCTL_MODE` pour forcer le mode.
- **TUI allégé** : `_choose_mode` supprimé, toggle mode sans confirmation.
- **action_start_stop étendu** : ajout du paramètre `target` pour gérer aussi
  les apps (via `app_make`), et non plus uniquement le Hub.
- **Tests** : 11 nouveaux tests (auto_detect_mode, action_status, action_work/ship,
  start_stop app, parseur sous-commandes). Suite : 208 passés.

## [0.15.9] - 7 juillet 2026

### 🔧 Quick wins MEDIUM (TZ=UTC, env atomic, recovery 0700, wireguard auto-off)

- **HUB_base (docker-compose)** : `TZ: UTC` ajouté au conteneur Postgres (convention
  obligatoire du parc). Wireguard ne démarre plus par défaut — profil `wireguard`
  requis (`docker compose --profile wireguard up`). HUB_base v3.9.7.
- **hubctl (env_manager)** : écriture atomique corrigée — `os.replace` était hors
  du bloc `try` → sur ENOSPC le `.env` était remplacé par un fichier tronqué.
- **hubctl (vault_manager)** : l'export recovery écrivait les secrets en clair en
  0644 (world-readable). Passage en 0700 + umask 077.

## [0.15.8] - 7 juillet 2026

### 🛠 hubctl update — flux séquentiel + rollback (Lot 2, C3+H3+H5+H6)

- **action_update** : la stratégie blue/green (instance test + swap) n'a jamais
  fonctionné — collision `container_name` entre l'instance test et la prod
  (C3), mauvais nom de projet pour le swap du Hub (H5), health check sur le
  mauvais port pour les apps (H3). Le code de rollback existait mais n'était
  jamais appelé (H6).
- **Rewrite** : flux séquentiel `stop → git pull → build → up → health`.
  Rollback automatique (git reset + restore DB + rebuild + re-up) à chaque
  point d'échec. `_health_check` lit désormais `API_PORT` de l'app cible (H3).
- **Suppression** de la machinerie blue/green morte : `_deploy_test`,
  `_swap_to_prod`, `_cleanup_test`, `_find_free_ports`, `_port_in_use`.
- **HUB_base (Makefile)** : ajout du target `build` (v3.9.6) — requis par le
  nouveau flux `make build`.

## [0.15.7] - 7 juillet 2026

### 🔒 Quick wins sécurité (Lot 2bis, H9 + H10)

- **HUB_base (regenerate-secret)** : l'endpoint `/me/regenerate-secret` acceptait
  l'authentification par IP Docker + header `X-Slug` sans token M2M.
  N'importe quel conteneur docker pouvait voler/révoquer le secret M2M d'une
  autre app. Token M2M désormais obligatoire (H9, HUB_base v3.9.5).
- **hubctl (_ensure_jwt_keys)** : persistait `AUTO_GENERATE_KEYS=true` dans
  le `.env` de production quand les clés JWT étaient absentes, dégradant
  silencieusement la sécurité. Avertit désormais sans modifier le `.env` (H10).

## [0.15.6] - 7 juillet 2026

### 🔒 Chiffrement des archives park-export (Lot 4, H2)

- **park-export** : les archives `park-*.tar.gz` contenaient en clair tous les
  secrets du parc (clés JWT privées, mots de passe DB, `.env` complets, dumps
  DB). Désormais chiffrées par défaut (`park-*.tar.gz.enc`, Fernet + scrypt,
  passphrase requise). Format `PARKEV1 + salt + ciphertext`, réutilise la KDF
  du coffre (`coffre.derive_key`). `--no-encrypt` pour l'ancien comportement
  (compatibilité scripts CI). Permissions 0600 systématiques. Passphrase vide
  rejetée (`--passphrase-stdin` sur stdin vide → erreur).
- **park-restore** : détecte automatiquement le format (magic `PARKEV1`) et
  déchiffre ; accepte toujours les archives `.tar.gz` legacy non chiffrées
  (rétrocompatibilité — archives existantes des lots précédents). Mauvaise
  passphrase → échec propre (`WrongPassphraseError`). `--passphrase-stdin`
  pour CI/DR. Garde-fous Lot 1 intacts (`_check_hub_is_empty`, `_restore_tree`,
  `filter="data"`).

## [0.15.5] - 7 juillet 2026

### 🔒 Sécurité auth Hub — injection install.sh + spoofing IP (Lot 3)

- **HUB_base (install.sh)** : le code Python inline faisait `open('$PROFILE')`
  avec interpolation bash du chemin → un nom de fichier profil contenant une
  apostrophe permettait l'injection de code arbitraire (RCE) à l'install.
  Lecture via `sys.stdin` (C6).
- **HUB_base (_get_client_ip)** : trustait `X-Forwarded-For` inconditionnellement
  → bypass du rate-limit de login (H7) et introspection de token non
  authentifiée (H8). N'honore désormais les headers de proxy que depuis une IP
  de confiance (réseau Docker = frontend nginx). Compatibilité préservée pour
  les déploiements standards.

## [0.15.4] - 7 juillet 2026

### Fixed
- **hubctl (cleanup_orphan_tests)** : ne fait plus `docker compose down -v`
  sur tout projet `-test` — seuls les projets hubctl-owned (`hub-test`,
  `{app}-test` pour les apps réelles) sont nettoyés. Les projets `-test`
  étrangers (`load-test`, `integration-test`…) étaient détruits silencieusement
  à chaque lancement du TUI (C2).
- **HUB_base (scheduler backups)** : `periodic_backup_scheduler` comparait
  `next_backup_at` (aware via TIMESTAMPTZ/asyncpg) avec `utcnow()` (naive)
  → `TypeError` chaque minute → aucun backup planifié ne se déclenchait.
  Normalisation via `_naive_utc` existant (C4).

## [0.15.3] - 7 juillet 2026

### ⚡ Sécurité park-restore — protection contre la perte de données (Lot 1)

- **park-restore** : la garde « Hub vierge » (`_check_hub_is_empty`) était un no-op
  — `--format {{.Status}}` ne contient jamais le nom du conteneur, donc la condition
  retournait toujours `True`, autorisant le restore sur un Hub en production.
- **park-restore** : `_restore_tree` n'avait pas de vérification de confinement
  (`is_relative_to`), permettant une traversée de répertoire via un membre `../`.
- **park-restore** : `tar.extractall` sans `filter="data"` vulnérable au tar-slip
  (CVE-2007-4559). Ajout de `filter="data"` (Python 3.12+).
- **Tests** : 10 nouveaux tests couvrant les 5 scénarios de `_check_hub_is_empty`,
  la traversée de répertoire, et le tar-slip via `restore_park()`.

## [0.15.2] - 6 juillet 2026

### 🔒 Sous-module HUB_base (v3.9.1 → v3.9.2) — durcissement sécurité P1 + P3

- **P1 — Reset token rejeté comme access token** : `verify_token()` rejette
  désormais tout token portant `scope="pwd_reset"`. Ces tokens (sans `jti` ni
  `type`) pouvaient contourner la vérification de révocation et servir de
  Bearer sur les endpoints protégés pendant `recovery_token_ttl_minutes`.
  Le flow légitime (`decode_reset_token`) n'est pas affecté.
- **P3 — CORS : plus d'injection de `localhost`** : la décision est extraite
  dans `build_cors_config()` (testable). En production avec uniquement
  `ALLOWED_ORIGIN_REGEX` (recommandé LAN), `localhost` n'est plus injecté
  dans les origines autorisées. En mode dev rien configuré, `localhost`
  reste autorisé mais sans credentials.
- **P3 — `except:` nus** remplacés par `except Exception`.

### 🐛 Sous-module HUBapp_TEMPLATE_base (v2.4.3 → v2.4.4) — hardening template

- **Backup** : introspection DB dialect-agnostique via SQLAlchemy `Inspector`
  (remplace `information_schema`/`pg_*` Postgres-only → tests SQLite valides
  et robustesse Postgres améliorée).
- **Restore** : `SET CONSTRAINTS ALL DEFERRED` restreint à PostgreSQL
  (SQLite ignoré).
- **Models** : `OutboxMessage.headers` `default=dict` (mutable default footgun).
- **hub_auth** : retrait du fallback JWKS mort dans `_try_decode` (cascade
  directe vers PEM).
- **Compose** : port 443 conditionnel via `docker-compose.https.yml` (plus de
  crash si `FRONTEND_HTTPS_PORT` vide) + fallback `APP_SLUG` sur `POSTGRES_HOST`.
- **Tests** : activation de `ENABLE_DEMO_ENDPOINTS` dans `conftest.py` (19
  tests services verts) ; `test_backup.py` réaligné sur le format générique v3.0.
- **Chores** : `python`→`python3` (Makefile), retrait `psycopg2-binary` inutilisé,
  format de date `bump_version` portable (`lstrip("0")`).

## [0.15.1] - 5 juillet 2026

### ⚡ Correction critique — capture complète des secrets (park-export + coffre + restore)

- **park-export** : `_collect_hub_secrets` codait 3 chemins inexistants
  (`jwt_private.pem`, `jwt_public.pem`, `.fernet_key`) ne correspondant à
  aucun fichier réel → les archives DR étaient produites **sans aucun secret
  Hub** (ni clés JWT, ni clés de backup, ni service_accounts). Réécriture
  en collecte récursive de `HUB_base/secrets/` conservant l'arborescence.
- **coffre** (`vault_manager`) : `backup_all` étendu en capture récursive
  (`rglob` au lieu d'`iterdir`) — les `service_accounts/` (credentials SA,
  un par app) étaient ignorés du coffre.
- **park-restore** : nouvelle aide `_restore_tree` (copie récursive sans
  écrasement) remplaçant l'ancien `iterdir`+`copy2` qui ne savait pas
  gérer les sous-dossiers. Le round-trip export/restore/recoffre est
  désormais cohérent sur l'arborescence complète.
- **Tests** : 9 nouveaux tests (161 → 161 passants) couvrant la collecte
  récursive, l'intégration archive, le restore_tree, et la capture des
  service_accounts dans le coffre.

### 🧰 Configuration

- **MCP** : serveur `zai-mcp-server` (`@z_ai/mcp-server`) ajouté dans
  `opencode.json`.

## [0.15.0] - 5 juillet 2026

### ⚡ Guide visuel du HUB (formation + référence technique)

- Nouveau guide HTML multi-pages autonome sous `docs/guide-hub/` : parcours
  opérateur + référence technique, articulé autour de `hubctl`.
- 11 pages reliées par liens relatifs : accueil (vue globale), `hubctl`,
  `make`, architecture, et 7 pages « attention » (ajouter/supprimer une app,
  bascule DEV/PROD, workshop, coffre, park-export/restore, danger `down -v`).
- Assets partagés `assets/style.css` (thème neutre) et `assets/guide.js`
  (boutons copier, surbrillance de nav, version du parc). Accordéons via
  `<details>` natifs et infobulles en CSS pur ; 100 % hors-ligne, sans
  dépendance réseau.
- Contenu aligné sur `README.md` et `hubctl_cli/menu.py` (arbre de menu réel,
  commandes make, garde-fous).
- Spec et plan d'implémentation ajoutés sous `docs/superpowers/`.

## [0.14.0] - 5 juillet 2026

### 🔒 Audit sécurité & install (HUB_base 3.9.1)

- **Clés JWT** : `install.sh` écrivait dans `secrets/jwt/` mais le code lit
  `secrets/jwt_private_key.pem` (top-level) — les clés générées n'étaient
  jamais utilisées et `AUTO_GENERATE_KEYS=true` était forcé en production.
  Chemin aligné + migration automatique des anciennes clés.
- **Mot de passe DB fail-fast** : retrait du fallback compromis
  `hub_secure_password_2025` (`${POSTGRES_PASSWORD:?}`). Un mdp DB/admin
  faible bloque désormais le démarrage en production.
- **Permissions restrictives** : clés privées et secrets en `0o600`
  (JWT, backup, `server.key` TLS, `sa_*.env`, configs WireGuard, `.env`).
- **Introspection RFC 7662** : `/api/auth/token/introspect` restreint —
  les appels externes doivent présenter un token Bearer valide.

### 🐛 hubctl — robustesse (park-restore, workshop, update)

- **park-restore** : le `pg_restore` se faisait avant `docker compose up -d`
  (conteneur inexistant → échec silencieux affiché « ✅ terminé »). Désormais :
  secrets/.env → compose up → attente DB saine → restore, avec propagation de
  l'échec et exit code non nul.
- **workshop move** : `down` → `stop` de la source (redémarrage rapide) +
  redémarrage automatique de la source en cas d'échec health check (la prod
  ne reste plus arrêtée après un rollback).
- **update** : `git pull --recurse-submodules` (rafraîchit les sous-composants).
- **health check** : respecte `HUB_API_PORT` du `.env` au lieu de hardcoded 8000.
- `requirements.txt` pinné avec borne supérieure (`rich<16`, `cryptography<50`) ;
- retrait de la mention `questionary` du README ; mock `canvas` complété (warning thread).

### 🤖 Agent Jellycode — revue du comportement

- **Visual Companion assoupli** : « systématiquement pour toute UI » →
  « au besoin (just-in-time) », conformément au skill `brainstorming`.
- **`verify-feature` scopé aux apps** dans `AGENTS.md` (le skill vit dans le
  template, l'exigence n'était pas tenable au niveau méta-repo).
- **Skills clarifiés** dans `jellycode.md` : `release-on-main` = gate
  OBLIGATOIRE avant push `main` ; skills app clairement séparés.
- Ajout d'une section « Cohabitation avec superpowers » dans `AGENTS.md`.

### 🧹 Méta-repo — nettoyage & cohérence

- **Branche renommée `master` → `main`** : aligne le méta-repo sur les 4
  submodules et ACTIVE le garde-fou `release-on-main` (auparavant désactivé
  sur le repo principal).
- **`00_INSTRUCTION_BIBLE/` supprimée** : lignée « exemple » entièrement périmée
  (HUB/ vs HUB_base/, PostgreSQL 16 vs 15, skills déplacés, référence master).
  README mis à jour pour pointer vers les docs vivantes.
- **`.github/instructions/` déplacé** vers `HUBapp_TEMPLATE_base/.github/`
  (les liens `../../backend/...` résolvent désormais depuis le template).
- **`manifest.json`** : URL HUBCSS passée en SSH (cohérent avec les 3 autres
  entrées et `.gitmodules` — évitait l'échec du clone sur poste neuf).
- **`scripts/create_app.sh`** : n'emporte plus le `.git` du template + garde-fou
  sur l'initialisation du submodule template.
- `.gitignore` : `build/` untraqué, `.superpowers/` exclu.

---

## [0.13.1] - 5 juillet 2026

### 🐛 hubctl — actions apps mode-aware (dev)
- Les actions `update`, `remove` et `logs` sur les apps utilisent désormais
  `active_apps_dir()` (mode-aware : `APP_Workshop/` en dev, `APPS/` en prod)
  comme le faisait déjà `attach_app`. En mode dev, choisir une app workshop
  dans le menu appliquait l'action sur le dossier `APPS/` (inexistant ou
  mauvaise app).
- Nouveau helper `hub_state.active_apps_dir()` + tests de non-régression.

### 🧹 hubctl — nettoyage code mort
- Suppression de `prompts.py` (wrappers `questionary` inutilisés depuis v0.11.1),
  de `intro/` (reliquat du launcher hybride Node 0.6.0, 4 fichiers trackés),
  de `utils.confirm/confirm_phrase` (bloquants, jamais appelés).
- Dépendance `questionary>=2.0` retirée de `requirements.txt`.
- `__version__` du package lit désormais le `VERSION` racine du parc (n'était
  plus synchro, bloqué à `0.1.0`).
- `hubctl_cli/recovery/` ajouté au `.gitignore` (secrets en clair exportés
  par `export_recovery`).

### 🔒 .opencode — restructuration skills + correctifs
- **Skills « app » déplacés** : les 9 skills conçus pour le contexte d'une
  app (`backup-restore-ops`, `badge-search-system`, `cache-busting-deployment`,
  `deploy-troubleshoot`, `frontend-crud-page`, `hub-messages-integration`,
  `react-list-rendering`, `release-sync`, `verify-feature`) sont déplacés de
  `POULIDOR/.opencode/skills/` vers `HUBapp_TEMPLATE_base/.opencode/skills/`
  où leurs chemins relatifs `../../../` résolvent correctement.
- **Skill `vault-manager` réécrit** : reflète le modèle sauvegarde seule
  du coffre v0.13.0 (plus de `push_env`/`pull_env`/`managed_env`).
- **`app-workshop-mover` + `vault-manager`** ajoutés à la liste des skills
  dans `jellycode.md` (étaient orphelins, non chargés par les agents).
- **Correction `master` → `main`** dans `jellycode.md:28` (cohérent avec
  `AGENTS.md` et `release-on-main` qui s'auto-désactive si ≠ `main`).

### ⚡ HUB_base — SSE EventSource (v3.9.0)
- Le endpoint SSE `/api/events/stream` accepte désormais l'auth par query
  param `?token=JWT` (fallback pour EventSource, qui ne supporte pas les
  headers custom). Corrige le bruit de fond 401 dans les apps frontend.
- UI Docker info : `docker_available: false` explicite quand le socket
  Docker n'est pas monté (mode production durci).
- Cleanup : `config.py` (code mort `unreachable return`), `TODO.md` (backup
  scheduler stale marqué résolu).

### 🧩 hub-mcp — correctifs (v0.1.1)
- `hub_app_list` et `hub_user_list` transmettent désormais leurs paramètres
  `page`/`per_page`/`search` à l'API Hub.
- `hub_call_service` accepte un `body` JSON pour les appels POST/PATCH.
- `hub_design_upload` corrige sa réponse (dict `error` → `not_implemented`).
- Ajout README + CHANGELOG. Branche renommée `master` → `main`.

### 📋 HUBapp_TEMPLATE_base — correctifs (v2.4.3)
- **Skills .opencode** déplacés du méta-repo vers le template (voir ci-dessus).
- **Versions synchronisées** : `bump_version.py` → `package.json`/`.env.example`/
  `docs/API.md` alignés sur `VERSION`.
- **Double `apply_migrations()`** retiré dans `backend/main.py`.
- **`.instructions.md`** : références Tailwind remplacées par HUBCSS, chemin
  `index.css` corrigé → `app.css`.
- **Seed HUBCSS régénéré** : `global.css` passe de 16 Ko à 38 Ko (tokens
  `--hub-space-*`, composants 0.2.x inclus).

### ⚡ hubctl — coffre en mode sauvegarde seule
- **Changement de rôle** : le coffre ne réécrit plus jamais les `.env` sur le
  disque. Il ne fait que **copier** vers lui-même (jamais de suppression /
  déplacement / écrasement). Le « mode .env managé » et les push/pull autour des
  opérations docker sont **supprimés** (`push_env`, `pull_env`,
  `auto_import_missing`, `toggle_managed`, `managed_env`, `backup_env`,
  `restore_env`, hooks `_vault_target`).
- **Contenu sauvegardé** : tous les `.env` (hub + APPS/ + APP_Workshop/) **et**
  les fichiers secrets du hub (`HUB_base/secrets/*`, stockés en base64).
- **Capture** : automatique au démarrage (après déverrouillage) + bouton
  « 💾 Sauvegarder maintenant ».
- **Récupération** : « ⬇ Récupérer (export) » écrit un dossier horodaté
  `hubctl_cli/recovery/<date>/` reproduisant l'arborescence, **sans jamais**
  toucher aux fichiers existants (garde de containment de chemin).
- **Passphrase obligatoire à chaque démarrage** (prod ET dev) ; création forcée
  si aucun coffre. **Changement de passphrase** possible dans l'option coffre.
- Divergence conservée en **informatif** (badge « modifié »).

## [0.12.0] - 4 juillet 2026

### ⚡ hubctl — rattacher une app existante
- « Ajouter une app » propose désormais un sous-choix : **Cloner depuis une URL
  git** (comportement existant) ou **Rattacher une app existante**.
- Nouvelle action `action_attach_app` (mode-aware) : initialise (`INITIALISE.py`
  si présent) puis build + démarre (`docker compose build` + `up -d`) une app
  déjà présente dans le dossier actif — `APPS/` en prod, `APP_Workshop/` en dev —
  sans passer par `app_make` (codé en dur sur `APPS/`).
- La liste de rattachement n'affiche que les apps **compatibles** (Makefile +
  docker-compose) ; les apps legacy sont exclues.

## [0.11.1] - 4 juillet 2026

### ⚡ hubctl — correctifs actions ↔ canvas (audit #1 & #3)
- **Confirmations réparées** : les actions ne lancent plus de prompt `questionary`
  incompatible avec le canvas. `action_remove_app` devient non interactive ; la
  confirmation de suppression se fait via les widgets canvas (`widgets.confirm`)
  **avant** l'exécution. `disk_guard` n'ouvre plus de prompt (abandon si `< 5%`
  d'espace). Import `prompts` retiré de `actions.py`.
- **Feedback visible** : `_ACTION_CONSOLE` écrit via `utils.StreamWriter`, qui
  route chaque ligne vers le flux de streaming actif (repli `sys.__stdout__`) —
  les messages de progression des actions (« → git pull », « ✓ … ») s'affichent
  enfin pendant l'exécution.

## [0.11.0] - 4 juillet 2026

### ⚡ hubctl — dashboard fluide, uptime et défilement des apps
- **Correction de lenteur** : le rendu ne recalcule plus l'inventaire des apps à
  chaque frame (fini le `git status` + `rglob` de taille par app et par frame,
  qui faisait chuter le rafraîchissement sous 1 fps).
- Statut **et uptime** de chaque app obtenus via un **seul** `docker ps -a`
  (remplace la sonde `curl /api/health`) ; correspondance app ↔ conteneur API par
  labels compose.
- **Thread de fond** (~3 s) qui rafraîchit `state["app_status"]` ; le rendu ne lit
  qu'un cache → coût par frame négligeable.
- Panneau `SERVICES STATUS` : section `[ APPS ]` avec point de statut coloré, nom
  et uptime ; **défilement** en fenêtre glissante (4 apps, +1 toutes les ~2 s) si
  plus de 4 apps.

## [0.10.0] - 4 juillet 2026

### ⚡ hubctl — menus unifiés dans la colonne de droite
- Tous les choix et infos s'affichent dans la colonne de droite du dashboard
  (vue principale conservée) ; le plein écran (`_modal`) est neutralisé.
- Navigation homogène **surbrillance + Entrée** : `↑`/`↓` déplacent la
  surbrillance, un chiffre pointe l'item, `Entrée` valide, `Échap`/`0` = retour.
  Pagination `1-9` par page.
- `confirm` en `1. Oui / 2. Non` surligné ; encart de commandes contextuel
  (`↑↓ naviguer · ⏎ valider · ⎋ retour`) ; suppression de la fausse invite shell.
- Clip défensif des colonnes (`canvas.clip_cell`) pour ne plus casser le cadre.

### ⚡ hubctl — apps legacy et statut API
- Détection des apps **legacy** (sans `Makefile` + `docker-compose.yml`) :
  affichées et comptées (`Apps : N (M legacy)`), grisées et non sélectionnables
  pour les actions hubctl.
- Sonde `/api/health` par app (`API_PORT` du `.env`, cache TTL) affichée dans le
  panneau `SERVICES STATUS` — un seul conteneur (l'API) par app.
- `widgets.select` accepte des items désactivés (grisés, non sélectionnables).

## [0.9.1] - 1er juillet 2026

### ⚡ Exclusion des applications du méta-dépôt
- Les applications ne sont plus incluses dans POULIDOR : `APP_Workshop/` est désormais
  ignoré (comme `APPS/`), et les sous-modules imbriqués `APP_Workshop/{exemple-app-2,exemple-app,exemple-app}`
  sont désenregistrés (`.gitmodules` + `.git/config` nettoyés, gitlinks retirés de l'index).
- Les dépôts d'app restent autonomes sur disque (leur propre `.git` + remote) — seul le
  suivi par le méta-dépôt est supprimé.

## [0.9.0] - 1er juillet 2026

### ⚡ Action Workshop — déplacer une app entre APPS/ et APP_Workshop/
- **Skill `app-workshop-mover`** : guide Jellycode pour déplacer une app dans les deux sens
  (APPS → Workshop pour développement, Workshop → APPS pour retour en production).
  Flow strict en 9 étapes : check `.dev-mode` → `docker compose down` → copie fichiers +
  volume PostgreSQL (`docker run alpine cp`) → renommage slug `-ws` → build & up →
  health check → backup tar.gz → suppression source.
- **Action `action_workshop_move()`** dans hubctl (`actions.py`) : implémente le même
  flow 9 étapes avec support `--dry-run`, rollback automatique en cas d'échec, et
  déplacement de la source vers la corbeille `_trash/`.
- **Sous-menu Workshop** (`menu.py`, option 12) : liste les apps dans `APPS/` et
  `APP_Workshop/`, propose `[→] Mettre en atelier` et `[←] Remettre en production`
  avec confirmation.
- **Dev-mode manquant** : au lieu d'abandonner, l'action propose de créer
  `HUB_base/.dev-mode` (confirmation O/N). En dry-run, passage automatique.
- **`hub_state.py`** : nouveau `WORKSHOP_DIR` et `get_workshop_apps()` (miroir de
  `get_apps()` pour `APP_Workshop/`).
- **Tests** : 7 tests unitaires couvrant les deux directions, mode dev manquant,
  source absente, destination existante, slug via `.env`. 91 tests au total.

## [0.8.0] - 29 juin 2026

### ⚡ Config Wizard + animation couleur + layout header/body
- Config Wizard intégré dans hubctl : menu `9. Setup` avec Quick Setup (mode, whitelist, admin)
  et sous-menus Réseau / Admin / Mode & avancé.
- Module `env_manager` : read/merge/write du `.env` avec préservation des commentaires.
- Module `auto_detect` : détection automatique IP serveur, CIDR LAN, subnet Docker, UID/GID.
- Layout canevas split : header (10 lignes, intro animée) + body (17 lignes, menu interagible).
- `render_header()` / `render_body()` + `ViewportHeader` pour les animations.
- Animation `welcome` : word art ASCII « Welcome to HUBctl » (~2 s).
- Extraction couleur depuis `introHUB.tsx` : 240 frames avec transparence et palette Rich.
  `hub_ascii.py` passe en `Text.from_markup()` pour le rendu couleur fidèle.

## [0.7.0] - 29 juin 2026

### ⚡ Canevas fixe 100×30 — hubctl en « fenêtre verrouillée »
- Canevas fixe 100×30 centré avec cadre letterbox (Rich `Align.center` + `Panel`).
- Écran de garde si terminal trop petit (« Agrandis ton terminal à 100×30 ») ; recentrage
  automatique au resize (SIGWINCH).
- Nouveau moteur d'input clavier maison (`keys.py`) : décodeur cbreak pour flèches,
  Échap, Entrée, backspace, Ctrl-C. Aucune dépendance supplémentaire.
- Widgets interactifs framés (`widgets.py`) : `select` (wrap + scroll), `confirm`,
  `text`, `password`. Remplacent `questionary` dans la couche navigation (menu, vues).
  `ESC` sentinel canonique partagé entre `widgets` et `prompts`.
- Surface `Canvas` (écran alternatif `rich.live.Live`) responsable du cadre, du
  letterbox, du resize et du mode passthrough (`canvas.paused()`).
- Refactor de `__main__.py` : ordre de démarrage garde → intro → menu.
- Refactor de `menu.py` : toutes les vues et choix rendus via `canvas.render()`,
  actions exécutées en passthrough (écran normal) → `actions.py` inchangé.
- Animations `hub_ascii` et `fly_to_flock` adaptées au contrat viewport
  (`play(viewport, state)` au lieu de `play(console, state)`).
- Barre de préchargement dans le cadre (progression textuelle), skip via `keys.read_key`.
- 62 tests unitaires, module `tests/` étendu (keys, canvas, widgets, menu, main).

## [0.6.0] - 29 juin 2026

### ⚡ CLI hubctl — clone git, intro hybride, confirmations
- Ajout de l'action `add` par clone git (URL) pour importer une app existante dans le parc.
- Launcher hybride : intro Node/@opentui avec fallback Python (échafaudage `intro/`).
- Confirmations en choix Oui/Non pour les actions sensibles.
- Vue « tout-en-choix » et documentation dans le README de hubctl.

### 🔧 Submodule
- `HUB_base` : alignement sur le HEAD `92a9494` (v3.8.0 — refonte VPN, import .conf).

## [0.5.0] - 28 juin 2026

### ⚡ CLI hubctl — outil interactif d'administration du parc
- Nouvel outil `hubctl` : launcher auto-venv, coffre chiffré Fernet+scrypt (vault parc),
  sondes système (docker, apps, disque, version).
- Interface interactive : menu plein écran (questionary), vues Apps/Coffre, animations
  pluggables, intro fly-to-flock, barre d'état réelle.
- Actions de gestion : `update`, `add`, `remove`, `repair`, `logs`, `start-stop`,
  avec make et garde-fous (shell, dry-run, confirmations).
- Gestion robuste du clavier : Ctrl‑C global, Échap quitte, prompts wrappers avec
  sémantique Esc/Ctrl‑C, _MergedKeyBindings pour text/confirm/password, sortie propre
  en mode non-interactif (pas de TTY).
- Gestion de l'état du serveur avec arrêt par timeout d'inactivité.

### 🖥️ Pages exemple-apps — fiche client et GED
- Nouvelles pages d'audit client : fiche client et gestion documentaire GED.
- Design dark pixel ajouté à la spec exemple-apps.

### 📚 Documentation
- Guide d'usage et vérification end‑to‑end de hubctl.
- Plan d'implémentation et spec pour l'audit UX/UI exemple-apps.
- Amendement du plan hubctl (renommage hubctl_cli).

## [0.4.1] - 28 juin 2026

### ⚙️ Jellycode défini comme agent par défaut
- `opencode.json` : `"default_agent": "jellycode"` — l'agent de développement Jellycode
  devient l'agent primaire par défaut du parc (après redémarrage d'opencode).

## [0.4.0] - 28 juin 2026

### 🤖 Persona Jellycode (assistant de développement)
- Ajout de l'agent opencode `.opencode/agent/jellycode.md` (mode `primary`) : charte en
  7 traits (Visual Companion avant toute UI, perf/stabilité > animations, harmonie HUBCSS,
  vérification post-UI via `verify-feature`, chargement du skill parc adéquat, politique
  inline vs subagent).
- Pointeur « Persona Jellycode » ajouté dans `AGENTS.md` (identité always-on).

### 🧹 Hygiène de la doc des skills
- `00_INSTRUCTION_BIBLE/CLAUDE.md` : retrait des skills fantômes `hub-ecosystem` /
  `hub-app-template` (sans `SKILL.md`) et ajout de `release-on-main` ; la table reflète
  désormais exactement les 10 skills réels de `.opencode/skills/`.
- Ajout du design spec et du plan d'implémentation dans `docs/superpowers/`.

## [0.3.0] - 28 juin 2026

### ⚡ Pages d'audit client & vue d'ensemble des process
- Ajout de nouvelles pages pour l'audit client et la vue d'ensemble des process (dev-interface).

### 🧰 Outillage IA — design de la persona « Jellycode »
- Ajout du design spec `docs/superpowers/specs/2026-06-28-jellycode-persona-design.md` :
  persona « Jellycode » (Visual Companion avant toute UI, perf/stabilité > animations,
  harmonie HUBCSS, vérification post-UI, politique inline/subagent) et hygiène des skills
  (skills fantômes `hub-ecosystem`/`hub-app-template`, resync de la table de doc,
  déduplication des skills en backlog).

### 🔧 Divers
- `HUB_base` : alignement sur le fix `optional_oauth2_scheme`.

## [0.2.1] - 28 juin 2026

### ⚡ Rescue d'une instruction HUB
- Ajout de `.github/instructions/hub-application-contract.instructions.md` (contrat
  d'application Hub), récupérée de HUB_base avant son strip — pour ne perdre aucun
  contenu unique lors de la centralisation.

## [0.2.0] - 28 juin 2026

### ⚡ Centralisation du dev-interface dans POULIDOR
- Skills partagés déplacés dans `.opencode/skills/` : `verify-feature`,
  `deploy-troubleshoot`, `backup-restore-ops`, `hub-messages-integration`,
  `frontend-crud-page`, `react-list-rendering`, `cache-busting-deployment`,
  `release-sync`, `badge-search-system`.
- Ajout de `.github/instructions/` et `.github/prompts/`.
- Principe : tout le tooling de dev vit dans POULIDOR ; les composants générés
  (apps, template) ne le portent plus.

## [0.1.0] - 27 juin 2026

### ⚡ Initialisation du versioning du stack

- Mise en place du versioning du méta-dépôt POULIDOR (fichier `VERSION` + ce
  `CHANGELOG.md`).
- Sert de point de départ pour la règle « release-on-main » (bump + changelog à
  chaque push sur `main`).
