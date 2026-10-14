## [0.72.18] - 14 octobre 2026

### ⚡ Pointeur HUBsocle 2.27.0

- **HUBsocle 2.27.0** : setting `BACKUP_INCLUDE_FILES` (défaut True,
  inchangé) — `false` pour les apps stockage de fichiers : le backup ZIP
  ne contient que la base (transferts, préférences, table uploaded_files
  avec les chemins), pas les binaires. Motivation : exemple-app —
  ses uploads SONT la donnée primaire (26 Go admissibles) ; ils restent
  dans leur volume, le backup ne porte que les métadonnées.
  Suite socle : 256 passed.

---

## [0.72.17] - 14 octobre 2026

### ⚡ Pointeurs HUBsocle 2.26.0 + template 2.30.2

- **HUBsocle 2.26.0** : backport template — backup/restore en streaming
  disque (fin du ZIP en RAM / OOM ~150 Mo), auto-réparation des volumes
  root opt-in (gosu, `USER appuser` conservé par défaut), pin
  SQLAlchemy `<2.1` (drift build). Motivation : migration exemple-app
  1.7.0 (26 Go admissibles → backup RAM risqué au backup_all du coffre ;
  volumes root sans réparation en mode strict). Suite socle : 254 passed.
- **HUBapp_TEMPLATE_base 2.30.2** : fix `allocate_ports` repli localhost
  (prérequis migration exemple-app).

---

## [0.72.16] - 13 octobre 2026

### ⚡ Resynchronisation du guide développement template (template 2.30.1)

- `docs/guide-developpement-template.md` aligné sur le template 2.30.1 /
  Hub 3.71.4 (dernière passe de fond : 15/09, template ~2.21).
- Corrections factuelles : TTL JWT 15 min → 8 h (`ACCESS_TOKEN_EXPIRE_MINUTES=480`,
  2.28.2) ; HTTPS par défaut `true` (2.23.7/2.26.0) ; fil rouge « feature de A à Z »
  réécrit — imports absolus, session par `Depends(get_db)` (l'ancien pattern
  `async with get_db()` documenté était précisément le bug corrigé en
  2.26.4→2.27.0), hooks TanStack signatures objet (`useApiQuery`/`useApiMutation`
  séparés, updates optimistes), composant canonique CSS-first
  (`PageHeader` → `hub-panel`, classes `hub-*` du seed HUBCSS 0.3.0) ;
  contenu réel de `ACTIONS/` (fin du « 12 scripts x3 OS »).
- Inventaires complétés : structure backend (`cert_sync`, `hub_transfert`,
  `logging_config`, `pytest.ini`, `entrypoint.sh`, routes `hub_data`/`docs`/
  `test_data`/`tests`) ; 27 fichiers de test + fixtures réelles
  (`client`, `authenticated_client`, `admin_client`, `viewer_client`,
  `m2m_client`, `asyncio_mode=auto`) ; Makefile (`help`, `test-seq`,
  `lint-classes`, `verify-ui`, `sync-hub-host`, `sync-hub-tooling-check`,
  `init` déprécié, `make test` xdist) ; `.env` (`LOG_LEVEL`,
  `HUB_TIME_SYNC_INTERVAL`, `HUB_INSTANCE_ID`) ; 11 features template
  2.22→2.30.1 ; annexes (nb de lignes à jour, ligne annuaire HUBCSS).
- En-tête du guide : date de synchronisation + versions de référence.

---

## [0.72.15] - 12 octobre 2026

### ⚡ Pointeur HUB_base 3.71.4 (téléchargements résilients)

- **HUB_base 3.71.4** : téléchargements résilients par tranches Range avec
  reprise — les exports chiffrés de backups, l'export ZIP d'environnement et
  les snapshots ne sont plus perdus en cas de coupure réseau (tranches 4 Mo,
  retry avec backoff exponentiel, timeout par requête, vérification de la
  taille finale, pastille de progression). Corrige l'incident
  « Failed to fetch » lors d'un export coupé à 12,6 Mo / 27 Mo.

---

## [0.72.14] - 12 octobre 2026

### ⚡ Pointeurs Hubctl 0.10.7 + HUB_base 3.71.3 (zéro action manuelle serveur)

- **Hubctl 0.10.7** : `ensure_hub_env()` — `APPS_HOST_PATH` (valeur =
  `APPS_DIR` réel du parc) est ajoutée automatiquement et de façon
  persistante au `.env` du Hub si absente/vide, avant toute invocation
  compose (update, start, cleanup, sync-db, vpn). Les serveurs installés
  avant HUB_base 3.71.1 se réparent seuls au prochain `hubctl
  update`/`start`.
- **HUB_base 3.71.3** : `install.sh` fusionne les clés manquantes dans un
  `.env` conservé au lieu de sortir sans rien faire (APPS_HOST_PATH ajoutée
  sans écrasement ; secrets manquants signalés explicitement).

---

## [0.72.13] - 12 octobre 2026

### ⚡ Pointeur HUB_base 3.71.2 (APPS_HOST_PATH auto via Makefile)

- **HUB_base 3.71.2** : fallback automatique `APPS_HOST_PATH` dans le
  Makefile — `hubctl update` corrige les serveurs installés avant la 3.71.1
  sans retouche manuelle du `.env` (calcul du voisin `../APPS` depuis
  l'emplacement du Makefile, priorité shell > .env > calcul).

---

## [0.72.12] - 12 octobre 2026

### ⚡ Pointeur HUB_base 3.71.1 (APPS_HOST_PATH dynamique)

- **HUB_base 3.71.1** : `APPS_HOST_PATH` dynamique — `install.sh` détecte et
  écrit le chemin réel de `APPS/` dans le `.env` généré (fin du chemin de
  machine de dev `/home/kkleskk/...` en dur dans compose/config/.env.example).
  Corrige le precheck « Écriture du dossier APPS » en fail (`PermissionError`)
  sur serveur distant : la variable devient obligatoire dans le compose
  (`${VAR:?}`), défaut backend neutre, tests de non-régression ajoutés.

---

## [0.72.11] - 12 octobre 2026

### ⚡ Pointeur hubctl 0.10.6 + doc skill atelier (subnet fail-hard)

- **hubctl 0.10.6** : atelier — subnet dédié garanti (fail-hard). La
  création d'un atelier est refusée si aucun /24 du pool `10.210.x`
  n'est libre ou si l'état Docker est inconnu ; fin du repli « subnet
  prod réutilisé » qui créait des ateliers en conflit réseau avec la
  prod. `APP_SUBNET` toujours écrit dans `.workshop.env` (parité voie
  UI) ; warning si le compose de l'app n'épingle pas `APP_SUBNET`
  (apps legacy, réseau atelier dynamique) ; ateliers legacy signalés au
  menu.
- Skill parc `app-workshop-mover` : documentation alignée (contrat
  8 clés, fail-hard, signalement des ateliers legacy).
- **Pointeur** : `hubctl_src` → `201b73e` (0.10.6).

---

## [0.72.10] - 11 octobre 2026

### ⚡ Pointeur HUB_base 3.71.0

- **HUB_base 3.71.0** : déploiement — precheck des prérequis avant la
  modale de mise en place (`GET /deploy/precheck` + garde 422 au POST) :
  git/PAT, Makefile (cibles build/up, sans clone), .env(.example),
  déploiement en cours, ports+subnet, outils conteneur (git/make/docker
  compose), démon Docker, écriture APPS_HOST_PATH. Bloquant strict sur
  l'API GitHub. Fin des déploiements lancés à l'aveugle sur des hubs mal
  montés (droits d'écriture) — la liste des manques est affichée à la
  place de la modale.

---

## [0.72.9] - 11 octobre 2026

### ⚡ Pointeurs HUB_base 3.70.2 + hubctl 0.10.5 + HUBsocle 2.25.2

- **HUB_base 3.70.2** : déploiement — réconciliation subnet Hub ↔ réseau
  Docker vivant avant l'écriture du `.env` (`get_project_network_subnets`
  + `reconcile_subnet_with_docker`, le réseau gagne) : Compose ne recrée
  plus jamais le réseau d'une app vivante, cause racine des échecs
  « Échec (2) de 'make' » (exemple-app) et « network not found »
  (exemple-app-test). Sous-réseaux d'allocation non plus scopés par host
  (démon Docker partagé, host instable) — fin des collisions cross-host.
- **hubctl_src 0.10.5 + HUBsocle 2.25.2** : releases documentées en
  0.72.8/0.72.7, pointeurs déjà alignés (leur statut « modifié » provenait
  du contenu non-tracké `.worktrees/` de leurs dépôts, pas d'un déplacement
  de pointeur) — clarifié ici.

---

## [0.72.8] - 10 octobre 2026

### ⚡ Pointeur hubctl 0.10.5

- hubctl 0.10.5 : atelier — le health check accepte désormais le format
  `{"status":"ok"}` des apps Node d'ancien template (ex. exemple-app),
  au lieu du seul `{"status":"healthy"}` du template courant. Cause
  racine des rollbacks systématiques à la création d'atelier sur ces
  apps, quel que soit le timeout.

## [0.72.7] - 10 octobre 2026

### ⚡ Pointeurs hubctl 0.10.4 + HUBsocle 2.25.2

- **hubctl_src 0.10.4** : atelier — le clone DB copie vers le volume
  réellement monté par le projet `-ws` (résolu depuis
  `docker compose config`, fallback convention historique) au lieu de la
  convention `<ws-slug>-postgres-data` jamais référencée ; timeout health
  de création 30 s → 90 s (surchageable
  `WORKSHOP_HEALTH_TIMEOUT_CREATE`) car un premier boot sur DB vierge
  (initdb + migrations + seed) dépasse régulièrement 30 s → faux échec +
  rollback systématique ; rollback health passe tous les fichiers compose.
- **HUBsocle v2.25.2** : merge fix/socle-2.25.2-derived (dérivés version,
  préexistant poussé sur origin HUBsocle — pointeur aligné).

## [0.72.6] - 10 octobre 2026

### ⚡ Pointeur HUBCSS 0.3.1 — roadmap directive simplicité

- HUBCSS 0.3.0 → 0.3.1 : ROADMAP consigne la direction 0.3.0 (étage
  structurel) et la règle d'expansion fixée par la directive simplicité du
  parc (le DS ne livre que ce qui retire du travail à l'IA) ; lock
  resynchronisée sur le package (react-dom peerDependency depuis 0.3.0) ;
  `.worktrees/` gitigné dans HUBCSS (infrastructure d'isolation agents
  poussée par erreur puis retirée de l'arbre).
## [0.72.5] - 8 octobre 2026

### ⚡ Pointeur HUBapp_TEMPLATE_base 2.30.1 — directive IA sèche

- Template 2.30.0 → 2.30.1 : `frontend/README.md` dématricé (la directive :
  « classes `hub-*` du seed, c'est tout » — la matrice seed/vendor/Verdaccio
  sort de la doc template) ; skills frontend resynchronisés
  (`frontend-crud-page` reçoit la directive « UI Directive — read first »,
  références `DataTable.jsx` → `ExampleList.jsx` dans `react-list-rendering`,
  `badge-search-system`, `bulk-operations`).
## [0.72.4] - 8 octobre 2026

### ⚡ Pointeur HUBapp_TEMPLATE_base 2.30.0 — Phase 2 template exemplaire CSS-first

- Template 2.29.5 → 2.30.0 : structure canonique (`components/PageHeader.jsx`,
  routes réécrites `PageHeader > toolbar unique > hub-panel`), purge de la
  duplication DS dans app.css (8 composants socle migrés hub-*), seed
  HUBCSS 0.3.0 livré, INITIALISE rebranding bruyant + regex h1 multiligne,
  frontend/README.md (recette + matrice de consommation HUBCSS).
- Exécuté en subagent-driven + e2e app fraîche (rebranding et structure
  canonique validés d'emblée). Détails dans le CHANGELOG du template.
## [0.72.4] - 8 octobre 2026

### ⚡ Pointeur HUB_base 3.70.1 — sync préférences M2M authentifiée

- HUB_base 3.70.0 → 3.70.1 : la synchronisation des préférences
  (tags) depuis une app source (ex. exemple-app-api-v3) échouait en
  401/502 — `routes/tags.py` appelle désormais les apps avec un token
  de service éphémère (Bearer) et `import_m2m` tolère le format
  `{"values": [...]}`. Détails dans le CHANGELOG HUB_base.

## [0.72.3] - 8 octobre 2026

### ⚡ Pointeur HUBapp_TEMPLATE_base 2.29.5 — fix TDZ logout AuthContext

- Template 2.29.4 → 2.29.5 : fix bloquant `frontend/src/context/AuthContext.jsx`
  (useEffect référençant `logout` avant sa définition — TDZ, crash de toute
  app neuve au premier render ; régression 05a2aff, détectée par le test e2e
  lab-hubcss). Détails dans le CHANGELOG du template.
## [0.72.2] - 8 octobre 2026

### ⚡ Pointeur HUBCSS 0.3.0 — étage structurel (PageHeader, Modal, panel--padded, scroll)

- HUBCSS 0.2.4 → 0.3.0 : composants structurels `PageHeader` (h1 unique, back,
  badge, pastille version dynamique, meta, actions wrap) et `Modal` (portal,
  Escape, focus trap, scroll-lock, tailles sm/md/lg, panneau bas mobile, fade
  scrim réel) + tokens z-index + `hub-panel--padded` + `100dvh` (fallback
  minifieur-proof) + `setIconSpriteHref()` (sprite surchargeable par app).
- Doc « Structure de page » (recette canonique + 4 règles anti page-dans-page)
  et démo PageHeader/Modal. Dérive manifest.json corrigée (0.2.1 → 0.3.0).
- Exécuté en subagent-driven (7 tâches reviewées) + validation e2e sur app
  neuve `lab-hubcss` (créée depuis le template, consommation paquet React +
  seed CSS) — findings reportés au template (TDZ AuthContext, Dockerfiles
  vendor, rebranding Header).
## [0.72.1] - 7 octobre 2026

### ⚡ Audit structurel HUBCSS + template — roadmap anti « page dans une page »

- Nouveau `docs/plans/2026-10-07-hubcss-template-audit-roadmap.md` : audit
  statique exhaustif de HUBCSS v0.2.4 (atomes sans étage structurel, Timeline-h
  = composant d'app dans la DS, double échelles espace/typo, z-index magiques,
  piège `@source` démo), du template (3 couches CSS, DataTable monolithe 410 l.,
  alias legacy) et des apps (exemple-app, exemple-app : doubles retours, cartes dans
  cartes, scrolls imbriqués, 3 toolbars/page, 12 variantes de Header).
- 7 règles cibles de structure de page + roadmap en 3 phases (HUBCSS structurel,
  template exemplaire, socle partagé) avec critères de succès mesurables.
## [0.72.0] - 7 octobre 2026

### ⚡ Rapatriement sélectif du fork exemple_stack — fix https-flotte + outil migration legacy

- `scripts/https-flotte/activer.py` : rebuild frontend via un override
  jetable `docker-compose.build-host-tmp.yml` (`build.network: host`) —
  le DNS du bridge BuildKit peut faire échouer transitoirement le fetch
  des dépôts de paquets (registry.npmjs.org, dl-cdn.alpinelinux.org),
  là où le réseau host passe ; l'override est supprimé après le build.
  `test_activer.py` étendu (3 × `-f` attendus, suppression vérifiée) —
  suite complète : 95 passed.
- Nouveau `scripts/legacy-migration/import_to_stack.py` (v1) : import
  users / applications / rôles depuis l'export JSON du hub legacy
  hub-legacy (`export_env.py`) vers l'API admin du hub neuf — dry-run par
  défaut (`--apply` pour appliquer), mots de passe temporaires +
  `must_change_password`, URLs réécrites `localhost` →
  `host.docker.internal`, existants inchangés ; service_accounts en
  rapport-only (secrets Fernet legacy = chantier dédié). Stdlib only.
- Rapatrié du fork privé `Federation-exemple-50/exemple_stack` (84 commits
  d'avance) : le banc de test `scripts/bench-legacy/`, le suivi de
  campagne et les artefacts de session restent volontairement côté
  fork (périmètre prod = fixes et outils opérationnels uniquement).

## [0.71.25] - 7 octobre 2026

### ⚡ Pointeur HUB_base 3.70.0 — onglet « Environnement » dans la page Sauvegardes

- Pointeur `HUB_base` → 3.70.0 (197da6e).
- **3.70.0 — feature UI** : réactivation de l'écran d'export/import
  d'environnement (routes 3.69.0) en 3e onglet de la page Sauvegardes
  (Applications / Snapshots / **Environnement**), look « Ops Console »
  retenu via Visual Companion : avertissement sensibilité, résumé env
  en 4 stats, export JSON/ZIP à switches (clés JWT désactivées par
  défaut), import avec preview compteurs, catégories cochables, mode
  de conflit et carte de résultat. Contrôle croisé 37/37 IDs DOM,
  frontend de test rebuilde, déployé et vérifié (v=3.70.0 servie).


## [0.71.23] - 6 octobre 2026
### ⚡ Pointeur HUB_base 3.69.1 — `make test-docker` vert (script purge copié au conteneur)
- Pointeur `HUB_base` → 3.69.1 (930a1f8).
- **3.69.1 — fix tests** : depuis 3.67.0, la cible `test-docker` ne copiait
  pas `scripts/purge_orphan_backups.py` (contexte image `./hub` uniquement)
  → 6 tests échouaient en conteneur. La cible copie désormais le script
  sous `/code/scripts/` et le test résout son chemin en remontant les
  parents de `__file__`. `make test-docker` : 1306 passed, 1 skipped,
  0 failed.
## [0.71.22] - 6 octobre 2026
### ⚡ Pointeur HUB_base 3.69.0 — réimplémentation des routes export/import d'environnement
- Pointeur `HUB_base` → 3.69.0 (f18a251).
- **3.69.0 — feature** : les routes `/api/admin/backup/{export,export/download,
  import,import/upload,import/preview}` (supprimées par erreur en juin,
  remplacées par les snapshots) sont réimplémentées dans
  `hub/app/routes/admin_backup.py` — les outils MCP
  `hub_backup_export_env` / `hub_backup_import_env` et le module frontend
  `backup-import.js` refonctionnent. Le middleware anti-DoS élargit la
  limite de body (défaut 512 MB) aux 3 routes d'upload d'environnement :
  un fichier > 10 Mo recevait un 413 « max 10 MB » trompeur (le middleware
  court-circuitait avant le 404 des routes disparues). 22 tests dédiés,
  suite hôte 1342 passed, vérifié runtime en conteneur (upload 11 Mo → 200).
## [0.71.24] - 7 octobre 2026
### ⚡ Pointeur HUB_base 3.69.2 — compteur de connectivité sans les ateliers
- Pointeur `HUB_base` → 3.69.2 (b7346bb).
- **3.69.2 — fix** : le compteur « X/Y applications en ligne » de la vue
  admin n'inclut plus les ateliers (`-ws`, souvent arrêtés) — fini le
  « 14/20 » avec 6 ateliers éteints ; les entrées par app restent servies
  pour les icônes de la table. 2 tests dédiés.
## [0.71.21] - 6 octobre 2026
### ⚡ Pointeur HUB_base 3.68.0 — téléchargement de la CA racine depuis la page Hub
- Pointeur `HUB_base` → 3.68.0 (92c054b).
- **3.68.0 — feature** : bouton « Certificat » dans la navbar du Hub —
  téléchargement de la CA racine (`GET /api/pki/ca.crt`, public,
  `ca.key` jamais servi) + empreinte SHA-256/validité (`/api/pki/ca/info`)
  + guide d'installation par plateforme (Windows, macOS, Linux, Firefox,
  Android, iOS). Objectif : supprimer les avertissements « certificat
  auto-signé » sur les postes utilisateurs (CA installée une fois, Hub et
  apps HTTPS couverts). Tests dédiés (4), suite conteneur 12/12.
## [0.71.20] - 6 octobre 2026
### ⚡ Pointeur HUB_base 3.67.0 — purge one-shot des backups morts
- Pointeur `HUB_base` → 3.67.0 (bc84b36).
- **3.67.0 — ops** : `scripts/purge_orphan_backups.py` — purifie le
  stockage backup d'un Hub déployé en un geste (dry-run par défaut,
  `--apply` pour agir) : lignes `app_backups` d'apps supprimées + fichiers
  `*.zip`/`*.encrypted` orphelins + répertoires vides ; fichiers des
  lignes vivantes toujours intouchables, garde d'âge 7 j.
  6 tests dédiés, suite hôte 1320 passed.
## [0.71.19] - 6 octobre 2026
### ⚡ Pointeur HUB_base 3.66.0 — propagation IP en un geste
- Pointeur `HUB_base` → 3.66.0 (4654fd3).
- **3.66.0 — réseau** : `POST /api/config/network/propagation-plan/apply-and-recreate`
  (écrit l'IP dans les `.env` des apps validées puis recrée leurs conteneurs,
  opérations atelier tracées) ; résolution slug→répertoire par `APP_SLUG`
  (les apps `exemple-app`/`exemple-app`, jusque-là `no_env`, deviennent
  propageables) ; champ `env_dir` dans le plan ; UI onglet Réseau :
  « Propager et recréer (N) » + sélection des apps à propager + polling du lot.
  9 tests dédiés, suite hôte 1314 passed.
## [0.71.18] - 6 octobre 2026
### ⚡ Pointeur HUB_base 3.64.0 — acteur M2M exposé dans la liste/détail des erreurs (+ rattrapage pointeur)
- Pointeur `HUB_base` → 3.64.0 (9c9cdb6).
- **3.64.0 — audit erreurs** : `GET /api/audit/errors` renvoie désormais
  `service_account_id` + `service_account_client_id` (résolu comme
  l'export CSV) ; le détail `/api/audit/errors/{id}` expose aussi le
  `client_id`. UI Audit : helper `errorActorHtml()` — username (user),
  badge « M2M » + client_id tronqué (service account), repli id brut.
  4 tests dédiés, suite hôte 1296 passed.
- **⚠️ Rattrapage pointeur** : l'entrée 0.71.17 documentait « pointeur
  HUB_base 3.63.4 » mais le gitlink committé pointait en réalité sur
  3.61.1 (e7219c2, checkout sous-module périmé au moment du commit).
  Ce bump réaligne le pointeur sur 3.64.0 et embarque donc aussi les
  versions intermédiaires non pointées (3.62.x VPN flotte, 3.63.x VPN
  toggle hardening + TTL réservations ports, déjà documentées ici).
---
## [0.71.17] - 5 octobre 2026
### ⚡ Pointeur HUB_base 3.63.4 — TTL réservations ports (fuite prepare catalogue)
- Pointeur `HUB_base` → 3.63.4 (fbfe618) : une allocation de ports sans
  app associée (prepare catalogue GitHub, /allocate-ports orphelin)
  expire après `PORT_RESERVATION_TTL_MINUTES` (défaut 30 min, 0 =
  historique) — purge paresseuse, ports/subnet réattribuables. Fin de la
  fuite définitive des « Ajouter au HUB » abandonnés (constat 2026-10-05,
  3 réservations fantômes en prod). Suites : hôte 1292 passed, docker
  1252 passed.
---
## [0.71.16] - 5 octobre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base 2.29.4 — plugin hub API V2
- Pointeur `HUBapp_TEMPLATE_base` → 2.29.4 (d0386d2) : plugin
  `hub.ts` migré au format API V2 (sync plugin hub V2, alignement
  méta 0.70.7) + libellé changelog 2.29.4.
---
## [0.71.15] - 5 octobre 2026
### ⚡ Pointeur HUB_base 3.63.3 — minors revue finale VPN
- Pointeur `HUB_base` → 3.63.3 (c94722a) : réparation d'un
  `wg0.conf` préexistant en 0444 (500 → succès), bannière « conf
  absente » rafraîchie après enregistrement des réglages, purge
  `sync_version.py` dans `test-docker`, hygiène tests. Suites :
  hôte test_vpn 37 passed, docker 1246 passed.
---
## [0.71.14] - 5 octobre 2026
### ⚡ Pointeurs HUB_base 3.63.2 + hubctl_src 0.10.3
- Pointeur `HUB_base` → 3.63.2 (4dfcc10) : durcissement VPN toggle
  (status `conf_exists`, création wg0.conf en 0600, garde anti
  double-fire UI, bannière Réparer, docs GUIDE_ADMIN) + lane docker de
  tests reparée (cp sync_version.py). Suites : hôte 1285 passed,
  docker 1245 passed.
- Pointeur `hubctl_src` → 0.10.3 (ec9365e) : message `hubctl vpn`
  renvoie au toggle OFF→ON (auto-réparation) au lieu de l'init.
---
## [0.71.13] - 5 octobre 2026
### 📝 Correction — parc-isolate : contrat stale assumé (revue finale)
- Précision suite à revue : le cas `core.worktree` stale était déjà
  rejeté proprement par le `die` amont (`is-inside-work-tree`) — le
  CHANGELOG 0.71.12 annonçait à tort « crash bash brut avant ». La
  garde `cd` du script est conservée en défense en profondeur (races),
  commentaires du script et du test alignés sur ce contrat.
---
## [0.71.12] - 5 octobre 2026
### 🔧 parc-isolate : garde stale + tests fallback — doc VPN à jour
- **`scripts/parc-isolate`** : `die` explicite si `core.worktree` pointe
  un checkout déplacé (crash bash brut avant) ; test de régression
  étendu au chemin dépôt normal (isolate + `--list` + cleanup) et au
  cas stale (revue froide 05/10).
- **`docs/guide-parc-poulidor.md`** : `hubctl vpn` — « wg0.conf absente
  » renvoie désormais au toggle OFF→ON de l'UI (auto-régénération,
  HUB_base ≥ 3.62.4) au lieu de l'init.
---
## [0.71.11] - 5 octobre 2026
### ⚡ Pointeur `HUB_base` 3.62.10 → 3.63.0 — audit des échecs de login + rattachement utilisateur aux erreurs
- **Pointeur `HUB_base` 3.63.0** — nouvelles entrées `AuditLog(action="login_failed")`
  avec l'identifiant tenté (`target`) sur les deux endpoints de login, et
  `error_logs.user_id` / `service_account_id` désormais alimentés via décodage
  JWT Bearer (signature vérifiée, expiration ignorée). UI Audit : colonne
  « Utilisateur » dans la table Erreurs, label + badge « Connexion échouée »,
  filtre username élargi aux identifiants tentés, export CSV enrichi.
  12 tests d'intégration ; 1281 passed (hôte) / 1230 passed (Docker).
---
## [0.71.10] - 4 octobre 2026
### 🔧 Hotfix — `scripts/install-version-guard.sh` : chemin double `hooks/hooks/`
- L'installateur écrivait dans le hook chaîné le chemin
  `<GIT_DIR>/hooks/hooks/pre-push-version-guard.sh` (double `hooks/`) :
  chaque push échouait (`No such file or directory` → fail-closed, tous les
  pushs bloqués sur les clones où le hook est installé). Chemin corrigé ;
  hook files locaux réparés. Hotfix immédiat post-merge (fichier introduit
  en 0.71.9).
---
## [0.71.7] - 4 octobre 2026
### ⚡ Logging horodaté à l'heure du Hub — 3 pointeurs + guide
- **Convention parc** : tous les logs backend (hub, apps, socle) sont
  horodatés **ISO 8601 UTC à l'heure du Hub** (autorité temps du parc) —
  `2026-10-04T12:34:56.789Z | LEVEL | logger | message`. Apps : offset
  (heure hub − heure locale) synchronisé via `GET /api/system/time`
  (`epoch_ms`) au point médian request/réponse, au boot puis toutes les
  `HUB_TIME_SYNC_INTERVAL` s (défaut 300) ; fallback heure locale UTC
  (règle n°10). Nouveaux réglages : `LOG_LEVEL`, `HUB_TIME_SYNC_INTERVAL`.
- **Pointeur `HUB_base` 3.62.7 → 3.62.8** — `app/logging_config.py`
  (`setup_logging`, root + uvicorn) + **`epoch_ms`** dans
  `/api/system/time` (contrat de synchro, rétro-compatible frontend/MCP).
- **Pointeur `HUBapp_TEMPLATE_base` 2.29.2 → 2.29.3** —
  `backend/logging_config.py`, `hub_client.sync_hub_time()`, boucle de
  fond + lifespan, `.env.example`. (Suite : 266 passed.)
- **Pointeur `HUBsocle` 2.25.1 → 2.25.2** — miroir socle +
  `create_app(setup_logging=True)` (opt-out possible) ; dérivés version
  resynchronisés (`package.json`, `__version__.py`). (Suite : 246 passed.)
- **`docs/guide-developpement-template.md` §3.7** : convention
  documentée (mécanique, fallback, réglages, opt-out socle).
- Les apps existantes (`APPS/*`) hériteront à leur prochaine synchro
  template (`migrate-app-template`).
## [0.71.6] - 4 octobre 2026
### 🔧 Fix — plugins OpenCode V2 (superpowers + hub.ts) & pointeur template 2.29.2
- **Pin superpowers `896224c` (v6.0.3) → `8ca22db` (tag v6.4.2)** dans
  `opencode.json` — l'ancien pin n'exportait qu'un plugin format V1
  (`SuperpowersPlugin` nommé), rejeté par l'API plugin V2 d'OpenCode
  (`Plugin must export a default definition…`) : tous les skills
  superpowers (brainstorming, test-driven-development,
  systematic-debugging, verification-before-completion…) étaient absents.
  v6.4.2 est dual-compatible V1/V2 ; clé `plugin` renommée `plugins`
  (format canonique V2). Validé en runtime : chargement sans erreur.
- **`.opencode/plugins/hub.ts` migré au format plugin V2** — export
  `default { id: "poulidor-hub", setup(ctx) }` + hook
  `ctx.permission.hook("evaluate", …)` (remplace `permission.ask` V1).
  Garde-fou destructeurs inchangé (rétrogradation `allow` → `ask`).
- **Pointeur `HUBapp_TEMPLATE_base` 2.29.1 → 2.29.2** — même fix côté
  template (pin + copie hub.ts synchronisée, `make sync-hub-tooling-check`
  vert). Les apps `APPS/*` (gitignées, hors périmètre submodule) garderont
  leur ancien pin jusqu'à leur prochaine synchro template.
## [0.71.9] - 4 octobre 2026
### 🔧 Outillage release — garde-fous anti-écrasement croisé du méta-repo
- **Incident 2026-10-04** : double 0.71.6 (deux sessions bumpant patch en
  parallèle) puis régression VERSION (0.71.6 poussée après 0.71.7).
- **`scripts/hooks/pre-push-version-guard.sh`** (même hook que HUB_base) :
  refuse le push d'une VERSION strictement inférieure à celle de la branche
  distante — dernier rempart git, multi-hooks chaînables, partagé avec les
  worktrees via le common dir.
- **`scripts/check-release-guard.sh <version>`** : garde manuel à invoquer
  avant tout bump (le méta-repo n'a pas de sync_version.py) — origin pas en
  avance (fetch + comparaison, silencieux hors-ligne) + numéro CHANGELOG non
  déjà pris. Exit 1 avec la marche à suivre.
- **`scripts/install-version-guard.sh`** : installe le hook
  (`.git/hooks/pre-push`) — exécuté sur ce clone.
- Vérifié en conditions réelles : `check-release-guard 0.71.9` avant ce
  bump (origin 0.71.8 = local → passage) ; hook testé E2E sur repo simulé
  (régression refusée, avance autorisée).
---
## [0.71.8] - 4 octobre 2026
### 🔧 Fix — pointeur HUB_base 3.62.9 : badge « Échec déploiement » sur le menu principal
- **Pointeur `HUB_base` 3.62.8 → 3.62.9** :
  - **Scénario rapporté (cartes fantômes)** : une app créée depuis le front
    dont le déploiement échoue restait affichée sur le menu principal comme
    les autres — carte active, rien de fonctionnel derrière. Le dashboard
    affiche désormais un **badge rouge « Échec déploiement »** (date dans le
    tooltip, rappel du redéploiement admin) via `last_deployment` déjà
    exposé par `GET /api/apps`.
  - *(3.62.8, autre session : logging horodaté à l'heure du Hub + contrat
    `epoch_ms` sur `GET /api/system/time`.)*
- **Incident de release encaissé** : la release 3.62.8 a été poussée en
  parallèle par une autre session pendant le merge — bump décalé en 3.62.9
  automatiquement ; placeholder 3.62.9 poussé vide par erreur puis complété
  immédiatement (commit `0bc2d73`). CHANGELOG méta : en-têtes 0.71.3/0.71.4
  restaurés (`8f199f5`).
---
### 🔧 Fix — pointeur HUB_base 3.62.7 : 4 anomalies vue « Apps GitHub »
- **Pointeur `HUB_base` 3.62.6 → 3.62.7** — anomalies relevées par la
  campagne de tests fonctionnels de tous les contrôles de la vue :
  1. **Persistance du toggle cartes/table** (localStorage désormais réellement
     lu au boot — la valeur initiale le court-circuitait) ;
  2. **`fetched_at` global** : un filtrage sans résultat n'affiche plus
     « jamais synchronisé » ;
  3. **Timezone** : temps relatifs cohérents (timestamps naïfs traités en
     UTC — plus de « il y a 2 h » juste après une sync en UTC+2) ;
  4. **« Voir l'app »** : recherche sur le slug de l'APP liée
     (`integrated_app_slug` ajouté à `GET /api/apps/github/repos`) —
     exemple-app-2 trouve désormais l'app `exemple-app` ; POULIDOR pointe `hub`
     (app système, non listée dans l'onglet Applications).
- **Re-test E2E post-déploiement** : les 4 points vérifiés sur le Hub réel
  (v3.62.7) — table restaurée après reload, « sync il y a 6 h » conservé sur
  filtre vide, `exemple-app` affiché (1/13) après « Voir l'app ».
---
## [0.71.4] - 3 octobre 2026
### 🎨 UI — pointeur HUB_base 3.62.6 : refonte de la vue « Apps GitHub »
- **Pointeur `HUB_base` 3.62.5 → 3.62.6** — la vue admin « Apps GitHub »
  adopte le langage visuel du reste de l'admin : en-tête standard `h5` +
  `bi-github`, badge d'état du token, toolbar en card (recherche/owner/
  toggle), **toggle cartes/table** mémorisé (défaut cartes), modal Bootstrap
  pour le token, empty states en pattern `bi`, « Voir l'app » fonctionnel
  (onglet Applications + recherche préremplie). CSS dédié `.gh-*` sur tokens
  `:root` — zéro emoji, zéro style inline. Fix au passage : l'icône du bouton
  Synchroniser n'est plus écrasée au premier clic.
- **Validation** : maquettes approuvées (Visual Companion), parcours réel
  vérifié sur le Hub (vue cartes 3 colonnes, vue table, modal token, badge
  « token valide », exemple-app marqué « Intégré » via le fix already_
  integrated), logs backend propres, `node --check` vert sur tout le front.
---
## [0.71.3] - 3 octobre 2026
### 🔧 Fix — pointeur HUB_base 3.62.5 : déploiement GitHub des apps réparé
- **Pointeur `HUB_base` 3.62.4 → 3.62.5** — trois causes d'échec du
  déploiement d'apps depuis le front-end corrigées et validées E2E
  (cobaye `exemple-app-test`, template v0.3.0) :
  1. `get_hub_host()` en exécution conteneurisée (critique) — l'IP interne
     Docker (`10.42.x.x`) était poussée aux apps déployées : health KO,
     `hub_connected=false`, aucun auto-enregistrement ;
  2. URLs SSH (`git@host:path`) jamais converties en HTTPS — le clone
     échouait sans binaire ssh (4 échecs exemple-app) ;
  3. catalogue GitHub : repo affiché « Dispo » alors que son slug était déjà
     pris par une app sans `git_repo_url` (409 au clic).
- **Validation E2E post-fix** : déploiement #10 `exemple-app-test` success,
  `hub_connected=true`, auto-enregistrement avec l'IP LAN
  (`http://192.0.2.10:9005`), 0 warning HUB_HOST, 299 tests verts.
---
## [0.71.2] - 3 octobre 2026
### 🔧 Fix — `parc-isolate` : opère sur le bon dépôt pour les submodules
- **Problème (constaté le 02/10/2026)** : `MAIN_ROOT` était dérivé de
  `dirname(git-common-dir)`. Pour un submodule (`HUB_base`…), le git dir vit
  dans `<super>/.git/modules/<nom>` → `MAIN_ROOT` pointait `<super>/.git/modules`
  et **toutes** les commandes `git -C` remontaient au superprojet : branche,
  push upstream, worktree et registre créés sur POULIDOR au lieu du submodule
  (worktree même créé dans `.git/modules/…`).
- **`scripts/parc-isolate`** : si le config commun porte `core.worktree`
  (layout submodule), la racine est résolue depuis cette clé ; sinon fallback
  `dirname` (dépôts normaux, comportement inchangé). Corrige aussi `--list`,
  `--cleanup` et `--release-lock` (même variable).
- **Test de régression** `scripts/tests/test_parc_isolate.sh` : fixture
  superprojet+submodule (remotes locaux), asserte branche/push/worktree/
  registre côté submodule + aucune fuite superprojet + cleanup. Rouge prouvé
  sur l'ancien code ; preuve live sur `HUB_base` (isolation + cleanup jetables).
---
## [0.71.1] - 2 octobre 2026
### ⚡ Pointeur HUB_base 3.62.4 — fix VPN toggle ON régénère wg0.conf
- Pointeur `HUB_base` → 3.62.4 (186db03) : fix auto-réparation VPN — le
  toggle ON régénère `wg0.conf` depuis la DB si le serveur est initialisé
  mais le fichier absent (incident 02/10/2026 : toggle OFF puis ON →
  conteneur wireguard sans config, « conf=ABSENTE » côté `hubctl vpn sync`).
  + tests rouge/vert du scénario incident ; suites hôte (1223 passed) et
  Docker (1183 passed) vertes.
---
## [0.71.0] - 1er octobre 2026
### ⚡ Charte Jellycode + pointeur template
- Charte Jellycode (`.opencode/agent/jellycode.md`) : `data-generate`
  ajouté à la liste des skills app — générer des données de test sans
  données réelles (synthétique, ou anonymisation via exemple-app).
- Pointeur `HUBapp_TEMPLATE_base` → 2.29.0 (679f42a) : nouveau skill socle
  `data-generate` (règle de parc : jamais de données réelles en dev/test ;
  voie A synthétique seedée, voie B anonymisation exemple-app obligatoire)
  + charte template à jour.
---
## [0.70.0] - 30 septembre 2026
### ⚡ Docs design app exemple-app
- **Ajouté** : `docs/specs/2026-09-30-exemple-app-design.md` — spécification complète de la nouvelle app `exemple-app` (anonymisation de données CSV/XLSX/ODS, génération statistique ≤ 1M lignes, validation KS/Wasserstein/TVD)
- **Ajouté** : `docs/plans/2026-09-30-exemple-app-implementation.md` — plan d'implémentation en 17 tâches (exécuté intégralement, app livrée en v0.1.0 dans `APPS/exemple-app`)
---
## [0.70.1] - 1er octobre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base 2.28.4 — header responsive mobile
- Pointeur du sous-module `HUBapp_TEMPLATE_base` : `f073671` → `8cc990e` (v2.28.4).
- Au programme : media query ≤ 768px sur le `header` des apps instanciées — les
  groupes (titre / nav / actions) s'empilent en colonne au lieu de déborder
  horizontalement sur mobile ; `.header-actions` en `flex-wrap` width 100%.
- Réparation au passage : retire `56b8f1c` (screenshots poussés par erreur lors
  de la release du template — cf. `322b5f3`).
---
## [0.69.1] - 30 septembre 2026
### ⚡ Pointeur HUB_base 3.62.3 — auto-détection robuste du hub-host
- Pointeur du sous-module `HUB_base` : `a093220` → `1723926` (v3.62.3).
- Au programme : `get_hub_host()` ignore désormais une IP configurée absente
  des interfaces locales du poste (Hub déplacé/cloné/restauré PRA) — les apps
  ne resynchronisent plus en boucle l'ancienne IP via `GET /api/config/hub-host`.
  Correction au passage de la route qui lisait une référence `settings` figée
  à l'import de `main.py`. Détails complets dans le CHANGELOG de HUB_base.
---
## [0.69.0] - 30 septembre 2026
### ⚡ Wrapper parc-vcompanion — Visual Companion diffusé sur le LAN
- `scripts/parc-vcompanion` : enveloppe le `start-server.sh` du skill superpowers
  `brainstorming` avec `--host 0.0.0.0` + `--url-host <IP LAN>` (auto-détection
  `hostname -I`) — le serveur du Visual Companion est désormais joignable depuis
  les autres devices du LAN (validation multi-devices) au lieu de localhost seul.
- STDOUT reste le JSON pur du serveur (ligne d'info sur stderr) ; l'accès reste
  gated par la clé de session `?key=…` ; les flags passés après surchargent les
  défauts. Sélection de la copie superpowers la plus récente du cache npm par
  timestamp de chemin (plusieurs copies coexistent).
- Charte Jellycode (règle 1) : lancement du Visual Companion toujours via le
  wrapper, jamais via `start-server.sh` directement ; URL complète (avec clé)
  systématiquement transmise.
- Testé sur banc : écoute 0.0.0.0 confirmée (`ss`), URL joignable sur
  192.0.2.10, arrêt propre.
## [0.68.0] - 30 septembre 2026
### ⚡ Skill parc git-test-hygiene — hygiène git des cycles de test
- Nouveau skill `.opencode/skills/git-test-hygiene/` : état propre avant test
  (`git status` réflexe, `git stash -u`, cycle rouge/vert sans pollution WIP,
  stash nommé systématique, « le stash n'est pas une poubelle »), staging
  discipliné (`git add` ciblés, `add -p`, commits atomiques par intention,
  `reset --soft` avant push), boucle de test graduée (unitaires ciblés → scope
  élargi → `verify-feature` en fin de cycle ; stash pour comparer deux
  variantes ; bisect réservé aux régressions historiques).
- Câblage : règle 8 « Hygiène git des tests » dans la charte Jellycode
  (`.opencode/agent/jellycode.md`) ; lien croisé à l'étape 3 « Travail » et
  table Skills liés de `agent-isolation-git`.
## [0.66.14] - 29 septembre 2026
## [0.67.0] - 30 septembre 2026
### ⚡ Suite de tests campagne flotte — merge feat/maj-flotte-simulation-tests
- `scripts/campagne-flotte/` : inventaire de flotte, scénarios de mise à jour,
  tests de sync app↔hub — suite validée **75/75 sur banc** (run 4) pendant la
  préparation de la campagne de réintégration 26/09.
- Runner banc : rapports générés ignorés (`scripts/campagne-flotte/rapport-campagne.*`),
  union `.gitignore` (checkpoint/ conservé).
- Ledger SDD de la campagne intégré (`.superpowers/sdd/progress.md`).
### ⚡ Pointeur template 2.28.3 — réparation auto des permissions de volumes au boot
- `HUBapp_TEMPLATE_base` : f68d833 → f073671 (**2.28.3**) — l'entrypoint de
  l'api démarre en root, corrige la propriété des volumes de données
  (storage/uploads/certs/data) puis bascule en appuser via gosu ; caps
  CHOWN/SETUID/SETGID ajoutées au service api du compose.
- Motivation : incident prod exemple-app (site exemple exemple-org) — volumes créés
  par root → app non-root en lecture seule (SQLite readonly, locks Hub) →
  500 sur toute création. Un simple redémarrage répare désormais tout.
# Changelog — POULIDOR
## [0.66.13] - 28 septembre 2026
### ⚡ Guide technique visualDev_guide.html à jour (audit complet vs code)
- Audit ligne à ligne de `docs/visualDev_guide.html` contre le code réel (HUB_base
  3.62.2, hubctl 0.10.2, template 2.28.2) ; corrections factuelles :
  - Hub : 27 routeurs FastAPI (24 avant) ; access token JWT 8 h par défaut (30 min avant).
  - hubctl v0.10.2 : wrapper `./hubctl` + TUI documentés ; flags réels des
    sous-commandes (export `--no-encrypt`, debug `--model`/`--status`,
    pra-restore `--snapshot/--apps/--yes/--force`, seed `-o/--force`,
    socle build `--force`) ; vault : sous-commandes CLI réelles
    (backup/restore/status/export/import/app list/app set-url).
  - Template : import `from hub_auth import` (absolu) ; 25 fichiers pytest (15 avant) ;
    hiérarchie rôles viewer<user<manager<admin ; datation allocation ports
    (Hub depuis 2.13.0, propagation POSTGRES_PORT corrigée 2.18.2).
  - Makefile apps : 39 cibles (35 avant) + section enrichie (sync-env, health,
    db-shell, ssl, lint-classes, verify-ui, refresh-design-seed, clean) ;
    `make test` = SQLite en mémoire, parallèle.
  - Migrations : précision rejeu si échec réel (migration non marquée appliquée).
- Points vérifiés exacts, inchangés : 4 services Hub, ~36 tables, PG16 Hub/PG15 apps,
  endpoints SSO/M2M, OIDC 30 échecs/60 s, jwt overlap 24 h, pra-restore 7 étapes,
  PARKEV1, atelier ports 10000-10499 / subnet 10.210.x, 14 sous-commandes hubctl.
## [0.66.12] - 28 septembre 2026
### ⚡ parc-isolate : support submodules et repos imbriqués
- `MAIN_ROOT` résolu depuis le dépôt **courant** : cas dépôt classique (gitdir
  commun `<racine>/.git`, appel depuis le principal ou un worktree lié) et cas
  submodule/dépôt imbriqué (racine via `core.worktree` relative au gitdir
  commun, puis fichier `gitdir`, puis toplevel courant).
- **Garde-fou** : abort propre si la racine déduite ne partage pas le gitdir
  commun du dépôt courant — au lieu d'opérer silencieusement sur un autre dépôt.
- Contexte (incident 28/09/2026) : exécuté depuis HUB_base (submodule), le
  script résolvait `MAIN_ROOT=.git/modules` et créait branche poussée + worktree
  sur le méta-repo, avec registre écrit dans `.git/modules/.worktrees/_agents/`.
- Tests : `--list` depuis POULIDOR / HUB_base / HUBsocle / worktree lié ; E2E
  isolation + cleanup dans HUB_base (worktree au bon endroit, registre local,
  push sur le bon origin) ; garde-fou vérifié.
## [0.66.11] - 26 septembre 2026
### ⚡ Pointeur HUB_base 3.61.1 → 3.62.1 (rattrapage 3.62.0 inclus)
- **HUB_base 3.62.0** — Notifications temps réel sans refresh + badge messages
  filtrable : SSE `error_logged` enrichi + `active_users_changed` (cooldown 2 s) ;
  badge messages navbar filtrable par priorité (préférence globale instance,
  `GET/PUT /api/messages/badge-priorities`, roue crantée vue admin Messages) ;
  10 nouveaux tests, suite 1213 passed.
- **HUB_base 3.62.1** — Fix test flaky `test_app_deploy` (placeholder `?` hors
  alphabet token_urlsafe, ~1/64 de faux échec) + suppression de l'entrée
  CHANGELOG placeholder orpheline [3.61.1] du 20/09.
## [0.66.10] - 26 septembre 2026
### ⚡ Checklist campagne réintégration apps + guide de mise en place à jour
- **Checklist imprimable** : `docs/checklists/2026-09-26-campagne-reintegration.md` —
  Phase 0 pré-campagne (coffre, nettoyage disque, parasites, down global sans `-v`,
  vérif hub seul), 5 services d'appui, 10 apps parc en blocs phases A→E (verdict
  GO/NO-GO), 23 apps legacy MIGRATION (down + priorités de migration suggérées),
  carte des 10 pièges connus, mémo outils, journal de campagne.
- **Audit guide de mise en place (26/09)** : `install.sh`, `update-hub.sh`,
  `architecture.html` conformes ; dérives corrigées — `README.md` (badge 0.66.9,
  HUB_base 3.61.x, template 2.28.x, hubctl 0.10.x, 63 outils MCP, PG 15 apps / 16 hub,
  emplacement des versions HUBCSS/hub-mcp), `docs/guide-hub/` (version parc
  0.54.1 → 0.66.9 via `guide.js` + 12 footers ; `hubctl.html` : + sous-commande `jwt`
  [keys/rotate/revoke/cleanup] et TUI dashboard à accès direct 1-6/0 à la place de la
  navigation menu plat ; `make.html` : + cibles test/test-seq/test-cov/test-docker ;
  `presentation.html` : 14 sous-commandes), `docs/guide-parc-poulidor.md` (instantané
  versions 26/09, Makefile hub 6 cibles d'exploitation + 4 de test aux §2.3/§6.1,
  110 fichiers de tests), `install.sh` (usage avec `--no-runner`).
## [0.66.9] - 24 septembre 2026
### ⚡ TTL tokens : alignement docs + hubctl sur 8h LAN
- **Doc** : `migrate-app-template` §D.3.1 — le contexte « access tokens HUB 30 min » est
  marqué historique (TTL actuel 480 min = 8h en LAN ; refresh proactif du dashboard
  2 min avant expiration, `HUB_base/frontend/public/js/api.js`).
- **Pointeurs** : `hubctl_src` → 82fd01c (**v0.10.2** : `hubctl init` génère désormais
  `ACCESS_TOKEN_EXPIRE_MINUTES=480` au lieu de 30 — cause réelle des sessions 30 min
  sur les déploiements initialisés via hubctl) ; `HUBapp_TEMPLATE_base` → f68d833
  (**v2.28.2** : skill app `hub-notifications`, doc TTL JWT 15 min → 8h).
## [0.66.8] - 23 septembre 2026
### ⚡ Runbook : socle minimum 2.28.1 (garde HUB_HOST legacy)
- `docs/runbook-exemple-app-apps-socle.md` : socle requis passé de 2.28.0 à
  **2.28.1** — le garde `HUB_HOST` (sync_hub_host) est indispensable sur le
  banc legacy (sinon écrasement par l'IP docker interne du hub, register M2M
  en timeout). Cycle pilote validé : app `test-socle-228` scaffoldée depuis
  2.28.0, fallback subnet 198.51.100.20/24, register M2M 200 au hub legacy,
  hub_connected: true.
## [0.66.7] - 23 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base → 2.28.1
- `HUBapp_TEMPLATE_base` 2.28.1 : sync_hub_host conserve `HUB_HOST` quand le
  Hub y répond déjà — le hub legacy annonce l'IP docker interne de son
  conteneur, qui écrasait l'IP LAN joignable à chaque `make sync-env`
  (register M2M en timeout). Découvert par le pilote `test-socle-228` sur le
  banc exemple-app.
## [0.66.6] - 23 septembre 2026
### ⚡ Runbook exemple-app + pointeur HUBapp_TEMPLATE_base → 2.28.0
- `HUBapp_TEMPLATE_base` 2.28.0 : les apps socle tournent désormais sur le hub
  legacy hub-legacy (3.9.x, pré-H9) sans blocage de sous-réseau —
  `scripts/set_app_subnet.py` (écriture manuelle de `APP_SUBNET`, plage dédiée
  exemple-app `198.51.100.20/16`, disjonction réseaux Docker actifs + `.env`
  voisins, `--check`/`--force`/backup horodaté) + fallback local automatique
  dans `ACTIONS/PYTHON/allocate_ports.py` (hub sans `allocate-ports` →
  allocation locale ; hub neuf inchangé). +23 tests, smoke réel banc.
- **Ajouté** : `docs/runbook-exemple-app-apps-socle.md` — procédure de déploiement
  d'une app socle sur exemple-app (propagation 2 fichiers, plage 198.51.100.20/16
  vs 10.50/16 hub neuf et 10.210.x ateliers, dégradations legacy acceptées :
  SSE, grâce refresh, PKI, deps/sync-report, et risque recovery M2M si le
  hub legacy est patché ≥ 3.9.5).
## [0.66.5] - 22 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base → 2.27.1
- `HUBapp_TEMPLATE_base` 2.27.1 : suite d'audit du socle — backup streaming
  (data.json écrit sur disque par batchs, restore sans BytesIO du ZIP
  complet), PyJWKClient sorti de la boucle asyncio (fetchs en to_thread,
  décodage sans réseau, refresh + retry sur kid inconnu), snippets des
  skills badge-search/bulk-operations en async. +13 tests (249 verts).
## [0.66.4] - 22 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base → 2.27.0
- `HUBapp_TEMPLATE_base` 2.27.0 : release d'audit du socle — correction des
  bloquants P0 (ports `make dev`, endpoints `/api/hub/data` cassés, messagerie
  SSE jamais câblée), sécurité/fiabilité P1 en TDD (path traversal du storage,
  crash-recovery et verrou outbox, `require_role` fail-closed, migrations
  partielles non marquées appliquées), cohérence P2 (MSW aligné sur l'API
  réelle, démo DEV-only, docs MCP à 77 outils, garde-fou plugin, skills
  réancrés) et hygiène P3 (Pydantic v2 natif, refs obsolètes, ESLint
  frontend). +36 tests (236 verts).
## [0.66.1] - 22 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base → 2.26.4
- `HUBapp_TEMPLATE_base` 2.26.4 : le serveur MCP `hub` (~66 outils) est
  **désactivé par défaut** dans l'`opencode.json` du template, complété par les
  commandes `/hub-on` `/hub-off` pour la bascule à la demande (fichiers identiques
  au méta-repo 0.66.0 — parité de maintenance). Suite directe de l'allègement de
  contexte agent (~20K tokens/tour) opéré en 0.66.0 côté méta-repo.
## [0.66.0] - 22 septembre 2026
### ⚡ Allègement du contexte agent + fast-path isolation
- **`scripts/parc-isolate`** : fast-path du skill `agent-isolation-git` — registre
  (sous lock, collision détectée parmi les `active`), branche depuis `origin/main`,
  worktree et push upstream en 1 appel ; `--list`, `--cleanup <branche>`,
  `--release-lock` ; rollback registre+branche si échec `worktree add`. Validé en
  selftest (création → refus doublon → cleanup → registre propre).
- **Contexte opencode allégé (~20K tokens/tour)** : MCP `hub` (~66 outils) et
  `zai-mcp-server` (9 outils) désactivés par défaut dans `opencode.json` ;
  nouvelles commandes `/hub-on` et `/hub-off` pour basculer (redémarrage opencode
  requis ; en attendant, opérations Hub via `hubctl`/bash).
- **Seuils superpowers** (`AGENTS.md` + `jellycode.md`) : `brainstorming` réservé aux
  vraies features / changements de comportement notables ; TDD réservé à la logique
  métier/backend (UI → `verify-feature`) ; `verification-before-completion` et
  `systematic-debugging` toujours applicables.
- **Skill `agent-isolation-git`** : procédure fast-path scriptée documentée
  (politique stricte inchangée — worktree obligatoire sans exception).
- **Descriptions de skills parc resserrées** (migrate-app-template, exemple-app,
  hub-oidc-manager, app-workshop-mover) : triggers conservés, prose explicative
  coupée (chargées dans chaque prompt système).
## [0.65.1] - 21 septembre 2026
### ⚡ Guide de migration définitif — validé pas à pas sur banc neuf
- `docs/handover/2026-09-20-migration-legacy-hub-neuf-runbook.md` restructuré en
  **guide opérationnel définitif** : 4 phases (prérequis/inventaire, préparation cible,
  répétition sur cible, fenêtre jour J) + validation 48 h + rollback + incidents.
- Chaque étape : commande exacte, sortie attendue ligne à ligne, case à cocher,
  critère de succès — **exécutée dans cet ordre sur banc neuf** (VM `client-mig-gd`
  + banc legacy exemple-lab, zéro improvisation) : restore legacy complet, purge/rejeu
  fourche 027, comptages hub et données métier identiques, apps hub_connected zéro 403.
## [0.65.1] - 21 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base → 2.26.3
- `HUBapp_TEMPLATE_base` 2.26.3 : le garde-fou d'instance Hub
  (`sync_hub_host.py`) documente désormais la procédure de bascule
  volontaire (corriger `HUB_HOST`, supprimer `HUB_INSTANCE_ID`, relancer
  `make sync-env`) — retour d'expérience exemple-app 1.1.2.
---
## [0.66.3] - 22 septembre 2026
### 🧪 Cheatsheet dev banc + scripts de reset
- **`docs/cheatsheet-dev-banc.md`** (nouveau, ~190 lignes) : l'outil de travail des
  devs disposant d'un parc complet en local — installer/réinstaller (install, seed,
  vm-lab), itérer sur le code du Hub (up-dev ⚠️ sans hot-reload depuis les incidents
  du 14/09, bascule de branche, tests), réinitialisations (scripts + version manuelle +
  re-registration FORCE_REPLACE_APP/.hub_credentials), comptes & tokens de test (login
  admin, user de test, approbation des pending en curl), M2M (discover, JWKS,
  socle-check), debug (psql, SQL utiles), pièges du banc.
- **`scripts/banc/reset-hub.sh`** : reset du Hub en 3 niveaux (`--db-only` défaut /
  `--full` secrets+certs / `--env` + hubctl init --force), confirmation tapée RESET,
  `--dry-run`, health check, rappel re-registration.
- **`scripts/banc/reset-app.sh`** : dé-enregistrement API admin (depuis .secrets),
  compose `down -v` prod + atelier, balayage des volumes **par label compose**
  (jamais par préfixe), purge .hub_credentials, `--full` = backup tar.gz + rm dossier.
- Guide : matrice §6.2 enrichie ; corrige « uvicorn --reload » (3 occurrences — le
  dev overlay n'a PAS de hot-reload API depuis le 14/09/2026) ; README : ligne cheatsheet.
## [0.66.2] - 22 septembre 2026
### 📖 Guides du parc mis à jour (0.66.1 → état réel) + Quick Actions
- **`docs/guide-parc-poulidor.md`** : versions actualisées (parc 0.66.1, Hub 3.61.1,
  hubctl 0.10.1, socle 2.25.1, template 2.26.4) ; **nouvelle §1.4 « Quick actions »** —
  ~30 commandes directes en 5 catégories (parc entier, Hub seul via `./hub.sh update`,
  app précise via atelier ou voie directe, résilience/PRA avec dry-run d'abord,
  sécurité/socle/HTTPS) ; §3.2 portée à **14 sous-commandes** (`jwt`, `socle`) + note
  `hub.sh` ; §4.3 à **39 cibles** Makefile (`update-env`, `test-seq`, `lint-classes`,
  `verify-ui`) ; §2.2 « Évolutions 3.51→3.61.1 » (cloisonnement M2M atelier/prod,
  socle-check, moniteur PAT GitHub, self-client OIDC, ajout d'app fiable, trousseau
  JWT multi-kid ⚠️ snapshots forward-only ≥ 3.59.0, PKI apps) ; §5.3 note forward-only ;
  cheat-sheet et matrice docs enrichies (PROCEDURE-CA, activer.py, runbook migration,
  outillage, migrationv1_rapport).
- **`docs/visualDev_guide.html`** : nouvelle section **« ⚡ Actions rapides »** (5 cartes
  copiables + nav) ; versions 5 composants ; 14 sous-commandes (lignes jwt/socle) ;
  caption PRA forward-only ; nav « Agent IA » restaurée.
- **`docs/migrationv1_rapport/`** commité (23 fichiers, bilan 35 apps sur 2 hubs —
  référencé par la matrice du guide).
- Passe du 15/09 (préexistante, non commitée) préservée dans un commit dédié (0c2e5b2).
## [0.65.0] - 21 septembre 2026
### ⚡ Outillage migration one-shot legacy → hub neuf (répété et validé en VM)
- **`scripts/migration-legacy/extract_legacy.sh`** : extraction à froid d'un serveur
  hub legacy → archive chiffrable au format park-export (modes `--inventory`/`--extract`,
  stop échelonné -t 30 + attente readiness pg, dumps via démarrage temporaire des seuls
  postgres, garde d'appartenance compose `working_dir`, trap EXIT de relance, manifest
  contractuel + self-check). Testé sur banc exemple-lab : 34/34 dumps, zéro PANIC.
- **`scripts/migration-legacy/encrypt_archive.py`** : chiffrement PARKEV1 (réutilise
  `park_export.encrypt_archive`) — round-trip déchiffrement `hubctl restore` prouvé.
- **`scripts/migration-legacy/rewrite_urls.py`** : réécriture idempotente des URLs hub
  après changement d'IP (`--dry-run`), prouvée avec psql réel.
- **Runbook jour J** `docs/handover/2026-09-20-migration-legacy-hub-neuf-runbook.md` :
  séquence complète enrichie des 7 leçons de la répétition VM (bootstrap admin →
  `compose down` hub avant restore, seed = conteneurs créés + slugs legacy, récupération
  DB hybride, approbation apps pending, re-pointage `.env`, URLs résiduelles + ZIP
  fichiers, durées : fenêtre 1 h–1 h 30).
- **Pointeur `hubctl_src` → 0.10.1** : reset DB hub avant `pg_restore` + réconciliation
  migrations fourchues 027 (fixes prouvés en répétition VM : restore legacy complet,
  027 purgée puis rejouée, comptages hub identiques, 3/3 apps hub_connected zéro 403).
- Spec : `docs/handover/2026-09-20-migration-legacy-hub-neuf-design.md` ;
  plan + journal VM : `build/vm-lab/client-mig-legacy/journal.md`.
bre 2026
### ✨ `scripts/update-submodules.sh` — filet de sécurité de mise à jour
- **Ajouté** : script autonome qui aligne TOUS les sous-modules sur les pointeurs
  du méta (`git submodule update --init --recursive`) — à utiliser quand
  `./hubctl update` ne fonctionne pas.
- Par défaut : fetch + fast-forward `origin/main` d'abord ; si le ff est refusé
  par un WIP local en conflit, aligne sur les pointeurs **locaux** avec
  avertissement explicite (non bloquant).
- Options : `--no-fetch` (pointeurs locaux), `--force` (écarte les modifications
  locales des sous-modules, confirmation requise sauf `--yes`), garde-fou
  branche `main`, état avant/après + versions des composants affichés.
## [0.63.5] - 20 septembre 2026
### ⚡ template → 2.26.2 (fix carte hub : version poussée au register)
- **HUBapp_TEMPLATE_base → 2.26.2** (depuis 2.26.1) : `register()` du socle
  app court-circuitait quand `.hub_credentials` existait déjà et ne poussait
  jamais la version — la carte des applications du hub restait figée sur
  l'ancienne version après chaque mise à jour d'app. Désormais, le fichier de
  credentials porte la version du dernier enregistrement ; si elle diffère de
  `APP_VERSION` (déploiement d'une montée de version), un register complet
  met la version du hub à jour. Détail : CHANGELOG template 2.26.2.
---
## [0.63.4] - 20 septembre 2026
### 📚 template → 2.26.1 (doc HUB_MCP alignée sur le MCP 0.4.2)
- **HUBapp_TEMPLATE_base → 2.26.1** (depuis 2.26.0) : `docs/HUB_MCP.md` ne liste
  plus `hub_auth_create_bootstrap_token` / `hub_auth_list_bootstrap_tokens`
  (supprimés du MCP v0.4.2). Catalogue doc : **63 outils**.
## [0.63.3] - 20 septembre 2026
### 🔌 hub-mcp → 0.4.2 (retrait des 2 outils bootstrap morts)
- **hub-mcp → 0.4.2** (depuis 0.4.1) : `hub_auth_create_bootstrap_token` et
  `hub_auth_list_bootstrap_tokens` supprimés — fonctionnalité jamais implémentée
  côté HUB (stubs d'erreur depuis v0.4.0). Catalogue : 65 → **63 outils**.
- Vérifié : aucun endpoint bootstrap dans `HUB_base/hub/app/routes/`.
## [0.63.2] - 20 septembre 2026
### 🤖 Persona `jellycode.md` — liste Skills app corrigée
- **Skill fantôme retiré** : `hub-messages-integration` (n'existe pas — ancien nom
  de `hub-notifications`).
- **Ajouts** : `bulk-operations`, `app-dependencies` — la liste couvre à nouveau
  les 13 skills du template.
- **MCP** : « ~85 outils » → « ~65 outils » (65 réellement exposés, comptés sur
  hubctl 0.10.0).
## [0.63.1] - 20 septembre 2026
### 🏷️ Skill `proxy-ia` renommé `exemple-app`
- Le skill suit le renommage de l'application de référence : **Proxy Métier**
  (slug Hub `exemple-app`, ex-exemple-app / PhiliaNG).
- Dossier `.opencode/skills/proxy-ia/` → `.opencode/skills/exemple-app/`,
  frontmatter `name`, titre et nom du pattern alignés. Aucune autre référence
  dans le repo (le persona `jellycode.md` ne cite pas le skill).
## [0.63.0] - 20 septembre 2026
### 📚 Resync des skills parc (audit vs code réel)
- **vault-manager** : réécrit — le coffre n'est plus « read-only » : `restore()`/`restore_all()`
  (coffre → disque : .env + secrets + DB + re-clone apps), passphrase auto-générée + clé locale
  `parc.vault.key`, dump DB (7 tables) + réplication PRA dans `backup_all`, purge `ws:`, CLI `hubctl vault`.
- **release-on-main** : cas `scripts/bump_version.py`/`make bump-*` (apps — gap constaté en release réelle),
  cas `pyproject.toml` (hub-mcp), dérivés HUB_base/HUBCSS, pointeur sous-module = release méta,
  garde-fou « git status avant bump » (incident 17/09).
- **create-hub-app** : 3 faits faux (`make health` sans retry, dérivés sync-env, ref README),
  skill fantôme `hub-messages-integration` retiré, flags non-interactifs, note env opencode, HTTPS par défaut.
- **migrate-app-template** : refs « 2.8.0 » → lecture dynamique de `HUBapp_TEMPLATE_base/VERSION`, G.1 aligné `release-on-main`.
- **app-workshop-mover** : atelier miroir prod (hubctl 0.10.0) — `HTTPS_ENABLED` (7+1 clés),
  `_ws_compose_files`, slugification, `input()`, numéros de ligne retirés (anti-drift).
- **proxy-ia** : app de référence renommée **Proxy Métier** (slug `exemple-app`, ex-exemple-app).
- **hub-oidc-manager** : espace parasite dans un trigger.
## [0.62.1] - 20 septembre 2026
### 🔧 Pointeur submodule — HUB_base 3.61.1 (SAN certs : localhost)
- **HUB_base → e7219c2 (3.61.1)** : le SAN des certs émis par `cert/issue`
  inclut `PKI_CERT_DOMAINS` (localhost) — `curl --cacert ca.crt
  https://localhost:<port>` passe la vérification. Ré-émission automatique
  par cert_sync (changement de SAN détecté).
---
## [0.62.0] - 19 septembre 2026
### 🔒 HTTPS par défaut sur la flotte — template 2.26.0, hubctl 0.10.0, HUB_base 3.61.0 (PKI apps)
- **Template → 2.26.0** (`HUBapp_TEMPLATE_base` f7572c1) : `HTTPS_ENABLED=true`
  par défaut (docker-compose api+frontend, docker-entrypoint.sh, config.py,
  Makefile `up` opt-out explicite `false`) ; docs/HTTPS.md ; fix `generate-ssl.sh`
  clé 644 (bug dormant 2.24.2 : `USER nginx` + mount `:ro` cassait le boot HTTPS).
- **hubctl → 0.10.0** (33c48a0) : `HTTPS_ENABLED=true` garanti dans le `.env`
  généré (choix app respecté) ; ateliers HTTPS (`.workshop.env` + override
  `docker-compose.https.yml` si embarqué).
- **HUB_base → 3.61.0** (2fb0e8d) : `POST /api/apps/cert/issue` — émission des
  certs apps par la PKI « Hub Local CA » (cherry-pick feat/apps-github-refonte,
  anti cross-slug inclus ; 7 tests).
- **Campagne flotte** : 22 apps activées en HTTPS (backup + checkpoint + vérifs,
  playbook `scripts/https-flotte/`), portail mis à jour automatiquement (re-register
  JIT), banc de campagne PASS 75/75. Reportées (socle sans mécanisme SSL, à leur
  migration) : exemple-app, exemple-app, exemple-app. Rapport : `scripts/https-flotte/rapport-https.md`.
- `PROCEDURE-CA.md` : import de la CA sur les postes (Windows + Firefox) — zéro
  avertissement navigateur une fois la CA importée.
---
## [0.61.2] - 19 septembre 2026
### ⚡ Pointeur submodule — complément release HUB_base 3.60.1
- **HUB_base → ff7ec5a** : commit manquant du bump (VERSION + fichiers
  dérivés INTEGRATION.md / index.html restés sur 3.60.0 dans le commit de
  release 3.60.1 — pattern incident du 17/09, rattrapé).
## [0.61.1] - 19 septembre 2026
### ⚡ Pointeurs submodules — fix backups volumineux (OOM) + nginx 1G
- **HUBapp_TEMPLATE_base → 2.25.0** (b1bb1e9) : création de backup en
  streaming disque (fin de l'OOM > 150 Mo, incident exemple-app du 19/09),
  mem_limit api 1G, nginx client_max_body_size 1G. Détail : CHANGELOG du
  submodule.
- **HUB_base → 3.60.1** (02b6782) : nginx client_max_body_size 50M → 1G
  (imports de gros backups). À appliquer au hub au prochain redéploiement
  frontend. Rattrape aussi le pointeur 3.60.0 resté non commité.
- Nettoyage : suppression de `main` du template des 2 commits d'app
  instanciée par erreur (ctrl-tg 0.0.1, VBA) — lignée 2.x rétablie.
## [0.61.0] - 17 septembre 2026
### 🛠️ CI du parc — pointeurs submodules + health des hubs (runner self-hosted)
- **Nouveau workflow** `.github/workflows/ci.yml` (2 jobs, runner self-hosted
  `[POULIDOR]` — org GitHub gratuite, zéro minute facturée) :
  - `submodule-pointers` : chaque pointeur de submodule doit être **poussé ET mergé**
    sur l'`origin/main` de son dépôt — dynamique (`git ls-tree`), couvre les 6
    submodules actuels ; c'est le garde-fou de l'incident type du 17/09 ;
  - `hub-health` : health `/api/health` des hubs, ports via la variable de repo
    `HUB_PORTS` (défaut `8000` = prod) — hubv2/legacy se réajoutent via la variable.
- Scripts : `scripts/ci/check_submodule_pointers.sh` et `check_hub_health.sh`
  (verbatim de l'archive `hub-base-an1-an2`, tip `394ca32`) ; `install_runner_ci.sh`
  déjà sur main (identique).
- Adaptations du portage (spec `docs/superpowers/specs/2026-09-17-portage-ci-parc-design.md`,
  approche A) : déclencheurs `push main` + `pull_request` (au lieu de toutes les
  branches), et clone via `git fetch origin "$GITHUB_REF_NAME"` qui fonctionne aussi
  sur les évènements `pull_request` (le `--branch` d'origine cassait sur `N/merge`).
- **Runner à installer** (op, hors code) : `sudo DRY_RUN=true ./scripts/install_runner_ci.sh`
  puis installation réelle — la CI restera « queued » tant qu'aucun runner n'est enregistré.
- Consigne conservée de la source : pas d'`actions/checkout` (extraheaders GITHUB_TOKEN
  incompatibles avec les submodules privés), `GIT_CONFIG_GLOBAL=/dev/null`, SSH natif.
## [0.60.0] - 17 septembre 2026
### 🛡️ Politique — isolation worktree obligatoire (règle stricte du parc)
- **Nouvelle règle permanente** : toute intervention qui touche du code (ou la
  configuration des outils) dans un dépôt du parc passe par `agent-isolation-git`
  AVANT la moindre modification — 1 agent = 1 worktree = 1 branche, registre partagé,
  merge sérialisé sous lock. Aucune exception (questions et lecture hors périmètre).
- `AGENTS.md` : nouvelle section « Isolation git obligatoire (règle stricte) ».
- `.opencode/agent/jellycode.md` : nouveau point 6 de la Charte (non négociable).
- `.opencode/skills/agent-isolation-git/SKILL.md` : description et « When to Use »
  passent de « cas d'usage occasionnel » à « obligatoire, systématique ».
- **Motivation** : incident HUB_base du 17/09/2026 — une session parallèle active a
  failli entrer en collision sur VERSION/CHANGELOG (bump empilé sur une release non
  commitée) ; le critère « d'autres agents pourraient être actifs » est remplacé par
  « systématique ». Le présent re-pointeur dédoublonne aussi l'entrée [0.59.3]
  (doublon issu de la fusion avec l'entrée non commitée de la session parallèle).
- Appliqué immédiatement : cette politique elle-même a été développée, mergée et
  releasée via le cycle complet du skill (registre `jellycode-405a5f1b`, branche
  `feat/isolation-worktree-obligatoire`, merge `--no-ff` sous lock).
## [0.59.3] - 17 septembre 2026
### ⚡ Pointeur HUB_base → 3.59.3 (correctifs critiques portail + perf + docs compatibilité)
- **HUB_base → 3.59.3** (merge `fix/api-class-closing-brace`, `c0a262b`) :
  - accolade fermante `class HubAPI` perdue en 3.58.0 (`api.js`) — écran de
    chargement infini du portail (ni login ni dashboard) ;
  - `GET /api/users` 500 sur email legacy `@hub.local` (lecture tolérante,
    écriture toujours stricte) ;
  - cache `{kid: PEM public}` du trousseau JWT — ~250 ms gagnés sur chaque
    requête authentifiée (`auth/me` : 250 → 9 ms mesurés en prod) ;
  - access token 8 h aligné sur le cookie OIDC ;
  - test anti-régression `node --check` sur les 40 JS du frontend.
- **Inclus dans la release** (docs rédigés par session parallèle, intégrés au commit
  `d74024b`) : `docs/COMPATIBILITE.md` réécrit (instantané 17/09 — versions réelles
  des 6 composants, contrat app↔Hub factuel, OIDC one-shot+PKCE documenté) et
  `JWT_KEY_OVERLAP_HOURS=24` ajouté au `.env.example`.
- Détails complets : `HUB_base/CHANGELOG.md` [3.59.3].
## [0.59.2] - 17 septembre 2026
### 📖 Refonte des READMEs du parc (7 dépôts) + pointeurs composants
- **Mécanique** : refonte des READMEs selon le canevas commun (bannière + badge de
  version, rôle, place dans le parc avec Mermaid, démarrage vérifié, docs liées) —
  spec : `docs/superpowers/specs/2026-09-16-readmes-parc-design.md`.
- **README racine** : vitrine du parc — badges, diagramme d'architecture Mermaid,
  tableau des 6 composants avec versions, arborescence corrigée (HUBCSS et hub-mcp
  y manquaient), provider OIDC et snapshots ajoutés au résumé Hub SSO, sous-commande
  `jwt` ajoutée à la liste hubctl.
- **HUB_base → 3.59.2** : création du README (rôle, fonctionnalités des 23 routeurs,
  stack réelle vanilla JS, place dans le parc, démarrage, 9 docs liées).
- **HUBsocle → 2.25.1** : README réécrit (socle pip/npm, images, CI, versionnage).
- **Hubctl → 0.9.1** : README racine créé (13 sous-commandes à jour du parser) +
  bannière hubctl_cli.
- **hub-mcp → 0.4.1** : README complété (catalogue des 65 outils, place dans le parc).
- **HUBCSS → 0.2.4** : badge de version + section « Place In The POULIDOR Park » (EN) ;
  inclut aussi le commit distant 0.2.3 (`docs/CASCADE.md`) au pointeur.
- **HUBapp_TEMPLATE_base → 2.24.2** : bannière + place dans le parc + section
  « Commandes make » (~37 cibles) ; fichiers dérivés resynchronisés (2.23.7 → 2.24.2).
## [0.59.1] - 16 septembre 2026
### 📖 Pointeur HUB_base → 3.59.1 (cahier des charges — réponses aux points d'audit)
- **HUB_base 3.59.1** (`6ff26dc`) : cahier des charges porté à l'état de l'art v3.59.0 —
  rotation des clés documentée (trousseau multi-kid, JWKS dynamique, aucun redémarrage
  côté apps), SPOF assumé avec stratégie de reprise bare-metal explicite (§3.3/§7.6),
  quiesce clarifié (délégation à l'application, HUB sans accès aux volumes), chiffres
  réactualisés (tests ≈1050, 107 fichiers). Livrable HTML reconstruit + vitrine alignée.
## [0.59.0] - 16 septembre 2026
### ⚡ Pointeurs HUB_base → 3.59.1 (rotation multi-kid JWKS + cahier des charges) + hubctl → 0.9.0
- **HUB_base 3.59.1** (`6ff26dc`, incl. 3.59.0 `4a22e5e`) : rotation multi-kid du JWKS (trousseau `secrets/jwt_keys/`,
  overlap 24 h, révocation d'urgence, endpoints `/api/auth/keys*`, kid thumbprint RFC 7638)
  + découplage du chiffrement des snapshots sur la paire `backup_*.pem` (repli legacy intégral,
  PRA rehearsal validé sur VM lab ; 3.59.1 = cahier des charges (réponses audit rotation/SPOF/quiesce)). Forward-only : les snapshots créés en ≥ 3.59.0 exigent ≥ 3.59.0.
- **hubctl 0.9.0** (`eba23ff`) : sous-commande `hubctl jwt keys|rotate|revoke|cleanup` ;
  fix login admin (`/api/auth/token`, l'ancien `/api/token` est mort).
- Validé extivement sur VM lab (jwks-359 + jwks-359b, from scratch) : install propre,
  rotation sans rupture, compromission, PRA, repli legacy, coffre statique.
## [0.58.5] - 15 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base → 2.24.1 (tests tolérants au slug instancié)
- HUBapp_TEMPLATE_base 2.24.1 (`32c510e`) : mocks de tests sur `settings.APP_SLUG`
  (38 échecs `test-docker` si slug d'app instanciée ≠ `mon-app`) + `test-seq` dans `.PHONY`.
- Les apps hériteront à leur prochaine migration template.
## [0.58.4] - 15 septembre 2026
### 🐛 install.sh — keyring Docker idempotent (2e run)
- **Corrigé** : `gpg --dearmor -o` refuse d'écraser `/etc/apt/keyrings/docker.gpg` existant
  → `curl (23)` au 2e run de install.sh → retombée fallback docker.io/docker-compose-v2
  (crash Debian). Prouvé et corrigé via validation fresh-install en VM labo Debian 12
  (`gpg --dearmor --yes`). Installation complète re-testée verte au 3e run.
## [0.58.3] - 15 septembre 2026
### 🐛 install.sh — dépôt Docker de la bonne distro (Debian 12 fresh install cassée)
- **Corrigé** : la détection Docker routait TOUJOURS vers `download.docker.com/linux/ubuntu`
  (codename `UBUNTU_CODENAME`→`VERSION_CODENAME`) — sur Debian 12 cela produisait une URL
  sans Release file → fallback `docker.io` + `docker-compose-v2` (inexistant côté Debian)
  → `set -e` tuait install.sh en phase 1. Trouvé par la validation fresh-install en VM labo.
- Désormais : route `debian` vs `ubuntu` (Mint/neon/pop remappés vers ubuntu) selon `ID`
  d'`/etc/os-release`, avec l'URL du dépôt et le gpg de la bonne distro.
## [0.58.2] - 15 septembre 2026
### 📖 HUB_base 3.58.1 — cahier des charges mis à jour v3.58.0
- Pointeur submodule `HUB_base` → b06f95f (release 3.58.1) : cahier des
  charges porté de v3.37.0 à **v3.58.0** — intégration du delta 3.38→3.57
  (self-service OIDC, socle-check, pilotage atelier depuis la vue Santé,
  moniteur jeton GitHub, changement d'IP propagé, backups par mot de passe,
  identité stable + renommage, atelier réécrit), retrait de la fonction
  « Droits Philia » reflété (23 modules), chiffres réactualisés
  (tests ≈1020, tables 36, endpoints ≈270). Livrable HTML reconstruit.
## [0.58.1] - 15 septembre 2026
### ⚡ HUB_base 3.58.0 — retrait de la fonction « Droits Philia » du portail
- Pointeur submodule `HUB_base` → f25628b (release 3.58.0) : la gestion des
  droits PhiliaNG quitte l'admin du hub (UI + route proxy `/api/philia-rights/*`
  + tests) pour vivre exclusivement dans l'app exemple-app (page
  `/users-rights`). Infra SNI/certs `service.example.org` inchangée.
## [0.58.0] - 15 septembre 2026
### ⚡ Outillage parc : gh, tests parallèles, Node.js, doctor enrichi
Spécification `docs/superpowers/specs/2026-09-15-outillage-parc-design.md` :
- **install.sh** : `gh` (repo officiel GitHub CLI en secours sur Debian) + `nodejs`/`npm` —
  fresh install complète ; vérifs post-install non bloquantes.
- **scripts/gh-auth.sh** (nouveau) : authentification gh par le token du parc (`.secrets`
  puis DB hub `app_settings.github_token`, mécanique identique à install.sh), fallback
  interactif device flow. Idempotent, `--check` non mutant.
- **scripts/check-import.sh** : sections S8 (gh présence + authentification), S9 (Node.js ≥ 18
  + npx), S10 (QEMU/KVM, optionnel labo vm-lab) — read-only, non bloquantes.
- **docs/outillage.md** (nouveau) : inventaire central des outils du parc + pointeur README.
- **Skill migrate-app-template** : note « test parallèle par défaut v2.24.0+ » (propagation apps).
- **Pointeurs submodules** : HUB_base → 3.57.0 (`10c3108`), HUBapp_TEMPLATE_base → 2.24.0
  (`a596a40`) — `make test` parallèle par défaut (pytest-xdist) dans les deux dépôts.
## [0.57.1] - 14 septembre 2026
### ⚡ HUB_base 3.56.0 — déploiement UI des apps aligné sur la voie manuelle
- Pointeur submodule `HUB_base` → e14e5e9 (release 3.56.0) : le déploiement
  déclenché depuis l'admin hub suit désormais strictement la voie manuelle
  (`make sync-env` → `make build` → `make up` via le Makefile de l'app).
- Correctifs : plus de fuite de l'env du hub-api dans le make/compose de
  l'app (env allowlistée, parité atelier/recreate) ; `.env` écrit en parité
  `hubctl _write_app_env` (`APP_SUBNET` dès le déploiement,
  `SECRETS_ENCRYPTION_KEY` réellement persistée, chmod 0600) ; échec
  explicite si l'app n'a pas de Makefile (fin du fallback `docker compose`
  nu) ; `git pull --ff-only`.
- Suite HUB_base : 1105 passed / 0 failed (7 nouveaux tests
  `test_app_deploy.py`, cycle TDD).
---
## [0.57.0] - 14 septembre 2026
### ⚡ HUB_base 3.55.0 — self-service OIDC M2M (/api/oidc/self-client)
- Pointeur submodule `HUB_base` → dddc824 (release 3.55.0) : une app
  enregistrée peut créer/régénérer SON client OIDC via token M2M
  (`POST|GET /api/oidc/self-client`, FK `oauth_clients.app_id` résolue
  serveur, secret une seule fois, SA multi-apps 409, JWT user 403).
- Finalité : premier déploiement d'app 100 % automatique — SSO Vikunja
  sans `HUB_ADMIN_PASSWORD` côté app (spec :
  `APPS/MIGRATION/exemple-app/docs/superpowers/specs/2026-09-14-oidc-self-provisioning-design.md`).
- Suite HUB_base : 1098 passed / 0 failed (10 nouveaux tests
  `test_oidc_self_client.py`).
---
## [0.56.1] - 14 septembre 2026
### ⚡ Docs : runbook de portage du fix socle jsonb (exemple-app, exemple-app)
- Nouveau `docs/runbook-portage-socle-jsonb.md` : procédure complète (TDD :
  test porté, RED, patch exact, GREEN ; release-on-main app ; déploiement
  prod ; vérifications ; rollback) pour publier le fix HUBsocle v2.23.4
  dans les releases futures de `exemple-app` et `exemple-app`
  (ces apps embarquent une copie historique de `routes/backup.py`).
- Procédure validée sur clone scratch (RED vérifié, 7/7 GREEN, patch depuis
  les extraits de la doc elle-même).
## [0.56.0] - 14 septembre 2026
### ⚡ Ajouté : `scripts/install_runner_ci.sh` — installation dédiée du runner CI
- Mini-script autonome extrait de la Phase 3.5 d'`install.sh` : installe le
  runner GitHub Actions self-hosted **sans relancer toute l'installation**.
- Résolution du PAT de parc (DB du hub → variable `GH_PAT` → prompt),
  auto-détection du repo depuis le remote, service systemd
  (`User=RUNNER_USER`, labels `POULIDOR`), idempotent.
- `DRY_RUN=true` prévisualise les commandes sans root ; options
  `--repo OWNER/NAME` et `--user USER`.
- Tester avant usage : `DRY_RUN=true bash scripts/install_runner_ci.sh`.
## [0.55.8] - 14 septembre 2026
### ⚡ Runner CI GitHub self-hosted intégré à l'installation
- `install.sh` : nouvelle **Phase 3.5** — installe un runner GitHub Actions
  self-hosted en service systemd (User=REAL_USER, labels `POULIDOR`), pour
  exécuter la CI du méta sans consommer de minutes Actions (org free) et
  permettre le job « Health des hubs » (LAN-only).
- Sources du PAT de parc : DB du hub (`app_settings.github_token`), variable
  `GH_PAT`, sinon prompt interactif ; `--no-runner` pour ignorer l'étape.
- Idempotent (skip si `.credentials` + service actif), mode `DRY_RUN=true`
  pour prévisualiser les commandes ; tests harness (positif, sans PAT, PAT DB).
- Runner version : dernière release `actions/runner` (fallback 2.337.0).
## [0.55.7] - 14 septembre 2026
### ⚡ Pointeur HUBsocle v2.23.4 — restore : colonnes jsonb/json rejetées par asyncpg
- HUBsocle v2.23.4 : `_import_table_data` passait aux requêtes les dict/list
  reconstruits par `_deserialize_value` (contenu JSON des colonnes jsonb) ;
  asyncpg exige une **chaîne JSON** pour ces types → DataError
  « invalid input for query argument $N: {} » → ligne rejetée et
  « importés: 0 » rapporté en succès par le restore.
- Corrigé dans le socle : `_normalize_db_value()` (dict/list → `json.dumps`,
  scalaires inchangés) branchée sur chaque valeur importée. TDD :
  `backend/tests/test_backup_jsonb_values.py` (7 tests), suite complète
  **203 passed**.
- Détecté par les tests de transfert des bancs isolés (13-14/09) :
  `exemple-app`, `exemple-app`, `exemple-app` ; image
  `poulidor/socle-api:2.23.4` construite, apps bancs reconstruites.
- Note : les apps embarquant une copie historique de `routes/backup.py`
  (exemple-app, exemple-app) devront porter le fix à leur
  prochaine release.
## [0.55.6] - 12 septembre 2026
### ⚡ Pointeur HUB_base v3.52.2 — passage en atelier depuis la vue santé (apps au dossier ≠ slug)
- HUB_base v3.52.2 : les routes atelier contrôlaient le dépôt git sur
  `APPS/{slug}/` — pour les apps dont le dossier diffère du slug
  (ex. `exemple-app` → « exemple-app »), le bouton « Créer l'atelier »
  de la vue Santé échouait en 400 « pas de repo git ». Tous les contrôles
  passent désormais par le résolveur `_app_dir(slug)` (v3.52.1) : le passage
  en atelier fonctionne de bout en bout pour ces applications.
- Voir le CHANGELOG HUB_base v3.52.2 pour le détail.
## [0.55.5] - 12 septembre 2026
### ⚡ Pointeur HUB_base v3.52.1 — bloc atelier visible pour les apps au dossier ≠ slug
- HUB_base v3.52.1 : le Hub résolvait le dossier d'une app par `APPS/{slug}/` ;
  pour les apps dont le dossier technique diffère du slug (ex. `APPS/exemple-app`
  pour « philia-proxy »), l'atelier apparaissait inexistant dans la vue Santé
  (pas de bloc « Atelier : … », absent du filtre « Atelier actif ») et les
  opérations atelier depuis le Hub étaient vouées à l'échec. Nouveau résolveur
  `_app_dir` (scan des `APP_SLUG` des `.env`, repli historique), branché sur
  les 8 points d'appel du workshop_service. Tests workshop : 29 verts.
- Voir le CHANGELOG HUB_base v3.52.1 pour le détail.
## [0.55.4] - 11 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base v2.21.2 — alignement socle 2.23.2
- HUBapp_TEMPLATE_base v2.21.2 : portage des fixes HUBsocle 2.21.1→2.23.2
  applicables au template monolithique — propagation IS_SHARED au register
  cache (AN-3) + deadlock flock ré-entrant, backup list triée/métadonnées
  cohérentes (AN-4), health/detailed discovery LIVE (AN-5), erreurs restore
  surfacées (AN-7), formatApiError front. Les futures apps créées depuis le
  template naissent avec le fix AN-3 ; suite template 165 tests verts.
- Voir le CHANGELOG HUBapp_TEMPLATE_base v2.21.2 pour le détail.
## [0.55.3] - 11 septembre 2026
### ⚡ Pointeur HUB_base v3.52.0 — fixes de sécurité M2M (AN-1/AN-2, banc 2026-09-10)
- HUB_base v3.52.0 : deux tickets 🔴 de la campagne de banc du socle traités.
  **AN-1** — `/api/apps/me/credentials` retourne désormais l'app propriétaire
  du service account (par `client_id` du token), plus jamais une app
  arbitraire de la relation N-N (409 en cas d'ambiguïté réelle).
  **AN-2** — périmètre M2M minimal : parité atelier↔prod systématique sur
  les partages `IS_SHARED`, claim JWT `apps` filtré (actives + approuvées +
  même contexte), purge one-shot des liens croisés existants (13 retirés sur
  l'instance). Impact parc : les SA d'ateliers n'ont plus d'accès M2M aux
  apps prod (et inversement) ; le discovery prod↔prod est préservé.
- Voir le CHANGELOG HUB_base v3.52.0 pour le détail technique.
## [0.55.2] - 11 septembre 2026
### ⚡ Pointeur HUB_base v3.51.0 — page admin « Droits Philia » (phase 1)
- HUB_base v3.51.0 : nouvel onglet Admin > « Droits Philia » — lecture des
  périmètres PhiliaNG (habilitations mo + agences/groupes) et suppression
  d'un droit, exécutée via l'app philia-proxy (proxy Hub→app authentifié par
  token de service TTL 90 s, audit des deux côtés).
- Voir le CHANGELOG HUB_base v3.51.0 pour le détail technique.
## [0.55.1] - 10 septembre 2026
### ⚡ Pointeur HUBsocle 2.23.2 — fixes de la campagne de banc
- **HUBsocle 2.23.2** (tag `v2.23.2`) : propagation `IS_SHARED` au register
  caché, fix deadlock flock M2M, liste backups triée/cohérente,
  `discovered_count` live, erreurs restore surfacées, conftest hermétique —
  191 tests. Campagne de banc : 24✅/0❌/4⚠️ (2 tickets 🔴 filés HUB_base).
- **exemple-app 1.4.2** en prod sur ce socle (pilote à jour).
## [0.55.0] - 10 septembre 2026
### ⚡ HUBsocle 2.23.0 — INITIALISE v2 (générateur d'apps fines)
- **HUBsocle 2.23.0** (tag `v2.23.0`) : `INITIALISE.py` génère une app fine
  nouvelle en une commande (pattern canari/pilote embarqué : ordre d'init
  settings, commits explicites, herméticité tests, frontend socle via
  `file:`/`additional_contexts`). `docs/REFERENCE-APP-FINE.md` = doc vivante
  du pattern. 188 tests.
- Pilote phase 2b déployé : exemple-app 1.4.1 (frontend socle + ticket
  get_db, socle 2.22.5).
## [0.54.4] - 11 septembre 2026
### ⚡ hub.sh selftest — validation réelle du cycle stop→start
- **Nouvelle sous-commande `./hub.sh selftest`** : état initial → stop (assertion :
  services cœur api/db/frontend arrêtés) → start (assertion : hub-api healthy) →
  verdict avec version déployée. En cas d'échec du start : récupération
  automatique (up -d --force-recreate + retry health), sinon logs d'erreur
  hub-api et verdict ÉCHEC explicite. Indisponibilité ~1 min, volumes
  préservés (jamais -v).
- Assertion stop ciblée sur les **services cœur** : le VPN (wireguard-server)
  est volontairement hors cycle (cycle de vie géré par hubctl vpn + boot hook)
  et reste up pendant un down.
- Testé en réel sur le hub de prod local : cycle complet stop→start validé,
  version 3.50.10 confirmée au health final.
## [0.54.3] - 11 septembre 2026
### ⚡ hub.sh — CLI d'exploitation du HUB depuis la racine POULIDOR
- **Nouveau `./hub.sh`** : sous-commandes `update` / `start` / `stop` / `restart` /
  `rebuild` / `logs` / `status` (+ `--dev`, `--dry-run`, `--help`) — plus besoin
  d'aller dans HUB_base pour piloter le hub.
- `stop` = compose down **jamais -v** (règle d'or : volumes préservés) ;
  `rebuild` = make build + up sans git pull ; `status` = conteneurs + health + version.
- **`update-hub.sh` devient un alias** rétrocompatible de `hub.sh update`.
- Fix au passage : le refactor initial exécutait compose depuis la racine du
  méta-repo (echec « no such file ») — le cd dans HUB_base est désormais global.
- Testé en réel : dry-runs (5 commandes), start, restart, rebuild, logs, status
  → HUB opérationnel v3.50.10 à chaque étape.
## [0.54.2] - 11 septembre 2026
### ⚡ update-hub.sh — mise à jour + déploiement du HUB en une commande
- **Nouveau script `./update-hub.sh`** (racine POULIDOR) : enchaîne `git pull --ff-only`
  + `git submodule update --init --recursive` + `make build` + déploiement du HUB
  (prod par défaut, `--dev` pour le stack DEV détaché ; `--dry-run` pour prévisualiser).
- Health check final `/api/health` avec comparaison version déployée ↔ VERSION du repo
  (prod : bloquant si KO) — cible le cycle exécuté manuellement après chaque release.
- Testé en réel : dry-run (prod/dev), config compose DEV validée (`config -q`),
  exécution complète prod → HUB opérationnel 3.50.10.
## [0.54.1] - 9 septembre 2026
### ⚡ Pointeur HUBsocle 2.22.1 — services_overrides storage câblé
- **HUBsocle 2.22.1** (tag `v2.22.1` publié) : `create_app(services_overrides=
  {"storage": impl})` fonctionnel (setattr module + registre) ;
  `routes/backup.py` résout `storage_manager` à l'appel via proxy lazy —
  8 sites d'usage inchangés. 175 tests. Pré-requis du pilote phase 2.
- **Pilote phase 2 déployé** : exemple-app 1.3.0 en prod sur le socle
  (`APP_SOCLE_VERSION=2.22.1`) — première app « à jour » de `hubctl socle status`.
## [0.54.0] - 9 septembre 2026
### ⚡ Sous-module HUBsocle + hubctl 0.8.0 — socle applicatif versionné (phase 1)
- **HUBsocle 2.22.0** (nouveau sous-module) : socle applicatif versionné du parc —
  factory `create_app()` (paquet pip `hub-socle`), paquet npm `@poulidor/hub-socle`,
  images de base `poulidor/socle-api` / `poulidor/socle-web`, pipeline offline-first
  (`hubctl socle build/status`). 171 tests verts, boot offline prouvé en conteneur.
  Spec : `docs/superpowers/specs/2026-09-09-socle-versionne-design.md`.
- **hubctl 0.8.0** (pointeur `hubctl_src` → `08189d4`) : commandes `socle build
  [--force]` (construction locale des images de base, cache par tag) et `socle
  status` (drift flotte `APP_SOCLE_VERSION` par app).
- Les apps existantes ne changent pas (forks template) ; les nouvelles apps
  naîtront « fines » via INITIALISE v2 (phase 3, à venir).
## [0.53.22] - 8 septembre 2026
### ⚡ Pointeur HUB_base 3.50.3 — suite de tests verte (1015/1015)
- **HUB_base 3.50.3** : les 11 échecs résiduels de la suite Hub sont corrigés —
  `croniter` installé dans l'env locale de dev (déjà dans `requirements.txt`,
  8 tests), chemins container `/code/*` rendus monkeypatchables dans
  `snapshot_engine` (constante `SNAPSHOT_STORAGE_DIR`, comportement inchangé),
  `test_oidc_launch` aligné sur la feature de purge de session Vikunja
  (`ff8d2a4`), `test_hub_host` déterministe hors container.
- **Validation** : suite complète Hub **1015 passed, 0 failed** (avant :
  1004 passed, 11 failed). Aucun changement de comportement runtime → pas de
  rebuild hub-api requis (la prochaine release déployée synchronisera).
## [0.53.21] - 8 septembre 2026
### ⚡ Pointeur HUB_base 3.50.2 — allocation de subnets : réseaux Docker épinglés manuellement exclus
- **HUB_base 3.50.2** : `POST /api/apps/allocate-ports` pouvait attribuer un
  sous-réseau déjà occupé par un réseau Docker créé hors Hub (épinglage
  manuel, stack tiers) — constaté sur exemple-app : allocation de
  `198.51.100.41/24` alors que `exemple-app-network` l'occupe → `docker compose up`
  en échec « Pool overlaps with other one on this address space ». Les ports
  étaient déjà filtrés par scan Docker du réel ; ce n'était pas le cas des
  sous-réseaux (seule la table `port_allocations` était consultée).
- **Fix** : `DockerScanner.get_used_network_subnets()` (scan IPAM best-effort,
  symétrique de `get_used_host_ports`) + `docker_occupied_subnets()`
  (flag `subnet_scan_docker_enabled`, host local, thread) fusionné dans
  `allocate_ports_for_app` (allocation neuve **et** backfill paresseux).
  6 tests TDD, suite port_allocation 26/26.
- **Validation** : rebuild `hub-api` en prod locale — allocation exemple-app
  renvoie désormais `198.51.100.43/24` en sautant 10.50.5/.6/.7 épinglés
  manuellement ; allocations orphelines exemple-app purgées du registre.
- **Nettoyage parc** : instance doublon `hubv2-exemple-app` (dépôt POULIDOR-lab)
  supprimée (containers + volumes + réseau 198.51.100.44/24) ; reliques de volumes
  `lab-exemple-app-*` supprimées ; exemple-app ré-épinglée sur `198.51.100.42/24`
  (premier slot libre du pool au moment du fix).
## [0.53.20] - 7 septembre 2026
### 📣 Pour les utilisateurs
- **Corrigé** : le numéro de version affiché en haut à gauche du Hub (à côté du logo) est de nouveau fiable — il reste correct même après une mise à jour du Hub, sans avoir à recharger plusieurs fois la page.
### ⚡ Pointeur HUB_base 3.50.1 — badge de version navbar fiable (/api/health)
- **HUB_base 3.50.1** : le badge de version de la navbar fetchait `/health`,
  non proxifié par nginx (fallback SPA → `index.html` en 200 `text/html`) →
  `resp.json()` en SyntaxError, catch silencieux → badge figé sur le fallback
  statique baked au build, périmé après bump `VERSION` + restart API sans
  rebuild image frontend. Fix : `fetch('/api/health')` (même handler,
  proxifié nginx, convention `/api/*`) dans `init.js` (badge) et
  `admin-snapshots.js` (polling post-restore qui déclarait le Hub
  « opérationnel » même API down — nginx répondait 200 sur du HTML).
- **Validation** : en prod locale — `/api/health` 200 JSON `3.50.1`, badge
  statique servi `v3.50.1`, JS corrigé servi, conteneurs healthy.
## [0.53.19] - 7 septembre 2026
### ⚡ Pointeur HUBapp_TEMPLATE_base 2.21.1 — self-healing M2M compatible Hub legacy
- **hub_client (template 2.21.1)** : `_recover_credentials` gère les Hubs
  legacy sans rotation M2M au register (ex. exemple pré-H9) — register 200 sans
  `client_secret` → fallback `POST /api/apps/me/regenerate-secret`
  (`X-Slug`/`X-Client-ID`, whitelist réseau Docker). Corrige la déconnexion
  Hub des apps à jour du template après perte de credentials sur un Hub
  legacy (log « Hub sans correctif T1 ? »).
- **Validation** : TDD (2 tests, suite template 157 passed) + E2E poulidor-lab
  contre le hub legacy `exemple-lab` (recovery OK, token M2M réel) — voir
  `build/vm-lab/poulidor-lab/journal.md` session 3.
- **APPS/exemple-app v0.4.0** (dépôt séparé, hors pointeurs) : hub_client
  synchronisé + release incluant rôles manager / édition conditionnelle.
## [0.53.18] - 7 septembre 2026
### 📣 Pour les utilisateurs
- **Corrigé** : après une mise à jour (`git pull`), la nouvelle version du Hub
  ne s'appliquait pas forcément — numéro de version absent du bandeau du Hub
  et nouveautés invisibles. L'installation (`sudo ./install.sh`) met désormais
  tout le monde d'accord : composants internes resynchronisés et Hub relancé
  avec la bonne version.
- **Amélioré** : la procédure de mise à jour est documentée pas à pas dans le
  README (les composants du parc sont des « sous-modules » : un simple
  `git pull` ne suffit plus).
### 🐛 Mise à jour du parc : synchro submodules + reconvergence install.sh
- **install.sh — synchro submodules (Phase 3a-prec)** : `git submodule
  update --init --recursive` avant toute initialisation — un simple
  `git pull` du méta-repo ne déplace pas le pointeur des submodules
  (HUB_base resté sur un vieux commit : badge de version absent de la
  navbar, commits « manquants »).
- **install.sh — reconvergence si hub déjà opérationnel (Phase 3b)** :
  au lieu de skipper entièrement, `make -C HUB_base build` + `up-prod`
  (cache Docker) — en prod les fichiers statiques du frontend sont cuits
  dans l'image (`COPY public/`), un restart sans rebuild sert l'ancienne
  version même avec le code à jour.
- **README.md** : nouvelle section « Mise à jour du parc » — procédure
  correcte (`git pull --recurse-submodules` → `git submodule update
  --init --recursive` → `./hubctl update`) et explication du piège
  pull/submodules + image frontend.
## [0.53.17] - 7 septembre 2026
### ✨ Pointeurs HUB_base → 3.50.0 + HUBapp_TEMPLATE_base → 2.21.0 — fin des fermetures d'onglets
- **HUB_base 3.50.0** (fc92c59..68be54c) : période de grâce 60 s sur la
  rotation des refresh tokens (migration 059 `replaced_by_token`) — un
  double refresh (course d'onglets, SSE `user_permissions_changed`) ne
  produit plus de 401 « Refresh token invalide ou expiré » ; access token
  porté à 8 h (LAN, aligné cookie OIDC). 6 tests dédiés + validation terrain
  (double refresh réel 200/200, post-grâce 401).
- **HUBapp_TEMPLATE_base 2.21.0** (7a1e2b4..dd123cf) : `refreshAccessToken`
  sous verrou Web Locks inter-onglets + adoption du token de l'onglet rival,
  synchronisation d'état via événement `storage`, re-lecture localStorage
  avant logout (désormais dernier recours).
## [0.53.16] - 7 septembre 2026
### ✨ Pointeur HUB_base 3.49.1 → 3.49.2 — modale droits : layout compact une ligne
- **HUB_base 3.49.2** (18bfd16..fc92c59) : lignes de la modale des droits en
  layout compact (variante B validée en companion visuel) — checkbox + nom
  (ellipsis, mini-badges profil/override en icônes) + reset + rôle + « Atelier »
  sur une seule ligne alignée, même avec profil + override.
## [0.53.15] - 7 septembre 2026
### 🐛 Pointeur HUB_base 3.49.0 → 3.49.1 — modale droits : ligne app/rôle/Atelier
- **HUB_base 3.49.1** (c47f9b7..18bfd16) : la colonne « Atelier » (3.48.3)
  faisait déborder `.app-role-row` dans la modale des droits — nom, rôle,
  Atelier, indice profil et badge « Modifié » se compressaient. Fix : flex-wrap
  structuré (2e ligne dédiée aux badges profil/override), nom shrinkable,
  rôle/Atelier fixes. Handlers insensibles à la nouvelle hiérarchie DOM.
## [0.53.14] - 7 septembre 2026
### ✨ Pointeur HUB_base 3.48.3 → 3.49.0 — onglets admin à 2 niveaux
- **HUB_base 3.49.0** (152e47b..c47f9b7) : la page Administration est
  réorganisée en 2 niveaux — 4 onglets principaux (Applications,
  Sauvegardes, VPN, Configuration) + 5 sous-onglets en pilules derrière
  « Configuration » (Groupes, Service Accounts, Clients OIDC, Apps GitHub,
  Réseau). Dernier sous-onglet utilisé mémorisé (localStorage
  `hub.admin.subtab`), badges et lazy-load intacts, aucune modification des
  modules métier. Design et plan dans
  `docs/superpowers/specs/2026-09-07-admin-tabs-regroupement-design.md`
  et `docs/superpowers/plans/2026-09-07-admin-tabs-regroupement.md`.
## [0.53.13] - 7 septembre 2026
### ✨ Pointeur HUB_base 3.48.2 → 3.48.3 — accès atelier par utilisateur
- **HUB_base 3.48.3** (c45149a..152e47b) : un admin peut activer, par
  utilisateur et par app de base, la visibilité de l'atelier `{slug}-ws`
  (table `user_workshop_access`, socle 3.48.0) — indépendamment du rôle sur
  la prod. Dynamique : l'atelier apparaît dès sa création (SSE), l'activation
  persiste après suppression. Tokens utilisateurs (7 sites) portent
  `{slug}-ws: "user"` ; gardes `/launch` et `/sso` étendus ; API admin
  `workshop_access` en full-sync ; checkbox « Atelier » dans la modale des
  droits. Opérations atelier toujours admin. 17 tests dédiés, suite
  intégrale 1000 passed.
## [0.53.12] - 7 septembre 2026
### 🔧 Pointeur HUB_base 3.48.1 → 3.48.2 — « Mon rôle » idempotent sous concurrence
- **HUB_base 3.48.2** (f340b5e..c45149a) : `update_my_role`
  (`PUT /api/apps/me/role/{slug}`) ne renvoie plus 500 sous concurrence —
  double-émission du sélecteur « Mon rôle » : le second PUT percute
  l'unicité `(user_id, app_id)` posée par le premier. Fix idempotent
  (rollback → reprise de la ligne concurrente → 200), course réelle couverte
  par test (2 connexions, INSERT pendant la fenêtre).
## [0.53.11] - 7 septembre 2026
### 🐛 Pointeur HUB_base 3.48.1 — fix envoi de messages avec `expires_at` timezone-aware
- **HUB_base 3.48.1** (89a7a7a..f340b5e) : `POST /api/messages/send` (admin) et
  `/api/messages/m2m/send` (apps) répondaient 500 (`asyncpg DataError: can't
  subtract offset-naive and offset-aware datetimes`) dès que `expires_at` ou
  `scheduled_at` était envoyé en ISO 8601 avec `Z`/offset — Pydantic v2 produit
  un datetime aware que asyncpg refuse pour les colonnes `TIMESTAMP WITHOUT
  TIME ZONE`. Tout broadcast/ciblage admin avec expiration était impossible.
- Fix à la source dans `schemas.py` : helper `to_naive_utc()` (vrai décalage
  `astimezone(UTC)`, pas un strip) + `field_validator` sur `MessageCreate`
  (`expires_at`, `scheduled_at`) et `MessageM2MCreate` (`expires_at`).
  Régression : `test_message_schemas_tz.py` 4 failed avant fix → 7 passed ;
  non-régression 62 tests messages/M2M. **Rebuild `hub-api` requis** (code
  copié dans l'image, non monté en volume).
## [0.53.10] - 6 septembre 2026
### 🔧 Pointeur HUBapp_TEMPLATE 2.20.7 → 2.20.8 — resync séquences robuste (validé terrain)
- **HUBapp_TEMPLATE 2.20.8** (0ce9319..7a1e2b4) : le resync des séquences
  abortait la transaction sur les tables sans colonne `id`
  (`schema_migrations`) → COMMIT d'une transaction abortée = rollback
  général des données restaurées. Structure corrigée : reset du rôle avant
  le resync, savepoint par table, pré-check colonne via
  `information_schema`. 155 tests passants.
- **exemple-app 1.12.4** (repo dédié) : même fix — backup b6d61ff0 restauré
  506/506 lignes (181 phone_users, 1 groupement, 2 voicemails, 313
  import_changes, 2 csv_imports), séquences resynchronisées. La migration
  de save exemple-app fonctionne de bout en bout.
## [0.53.9] - 6 septembre 2026
### 🔧 Pointeurs HUBapp_TEMPLATE 2.20.7 (+ fix transaction abortée restore)
- **HUBapp_TEMPLATE 2.20.7** (4bd31fa..0ce9319) : pré-check
  `pg_get_serial_sequence` avant `setval` + reset
  `session_replication_role` tolérant — le restore des apps ne rollback
  plus générallement après l'import des données. Porté sur
  exemple-app 1.12.3 (parité).
## [0.53.8] - 6 septembre 2026
### ⚡ Skill migrate-app-template enrichi (retour d'expérience 8 migrations réelles)
- **Règle d'or documentée** : fusion « template d'abord, métier réinjecté » pour
  `main.py`/`config.py`/`schemas.py`/`conftest.py`/`config.js`/`vite.config.js`/compose
  (patcher l'original = worker outbox/cert_sync/items perdus silencieusement).
- **Table symptôme → cause → correction** (17 entrées réelles) : imports union manquants
  (`date`/`Union`/`timezone`/`JSON`…), doublons de modèles, helpers/constantes top-level
  ratés à l'extraction, mock `decode_token` écrasé en multi-clients, `require_any_role`
  avec liste, `@asynccontextmanager` orphelin, conflits de ports, `links: api:backend`
  perdu, validation `FRONTEND_HTTPS_PORT`, `.dockerignore` vs `CHANGELOG.md`.
- **Méthode de qualification A/B** (worktree + `docker cp` + `--force-recreate`) pour
  distinguer échec de test pré-existant vs régression de migration.
- **Compléments ciblés** : `cert_sync.py` ajouté aux copies C.2, `items.py`/`test_data.py`
  à C.4 (imports obligatoires du `main.py` template), dépendances ACTIONS/scripts du
  Makefile 2.20 en B.1, registre d'allocation ports/subnets en premier boot, checklist
  frontend en 6 points, bump final vérifié via `/api/health`.
# Changelog - POULIDOR (HUB stack)
> Historique des versions du méta-dépôt agrégeant le HUB et les applications du parc.
## [0.53.8] - 6 septembre 2026
### 🔧 Pointeur HUBapp_TEMPLATE 2.20.5 → 2.20.6 — restore : cycles FK + resync séquences
- **HUBapp_TEMPLATE 2.20.6** (ae57c00..4bd31fa) : suite du fix restore —
  `session_replication_role=replica` pendant l'import (cycles de FK non
  déferrables) + resynchronisation des séquences après import (ids
  explicites). 155 tests passants. Porté sur exemple-app 1.12.2.
## [0.53.7] - 6 septembre 2026
### 🔧 Pointeur HUB_base 3.47.5 → 3.48.0 — atelier : socle accès par utilisateur
- **HUB_base 3.48.0** (9c9f4ab..89a7a7a) : merge de `feat/atelier-user-access`
  (rebasée, 27 tests de l'état fusionné passants) — migration 058
  `user_workshop_access` (activation référencant l'app de base, survit aux
  cycles atelier), modèle + helpers de visibilité `-ws`, 9 tests. Spec :
  `docs/superpowers/specs/2026-09-06-atelier-user-access-design.md`.
  Lots suivants (endpoints + UI) à venir sur le même sillage.
## [0.53.6] - 6 septembre 2026
### 🔧 Pointeur HUB_base 3.47.4 → 3.47.5 — snapshots : exclusion auto-référence du dump
- **HUB_base 3.47.5** (e6fffd1..9c9f4ab) : `run_pg_dump` ajoute
  `--exclude-table=hub_snapshots` — la ligne du snapshot en cours (statut
  `running` au dump) n'embarque plus dans l'archive ; au restore, le
  kill-switch ne la requalifiait plus `failed`. Effet bord assumé :
  l'historique des snapshots ne transite plus par l'archive ; la ligne
  manuelle du runbook bare-metal survit au `pg_restore --clean`.
- **hub-legacy 3.9.1** (e8074a4..0562af8) : même fix porté au hub legacy.
## [0.53.5] - 6 septembre 2026
### 🔧 Pointeur HUB_base 3.47.3 → 3.47.4 — fix 413 imports backups + réconciliation snapshot legacy
- **HUB_base 3.47.4** (ccb208c..e6fffd1) :
  - **Fix 413 nginx** : `client_max_body_size 50M` sur les 3 server blocks
    (`nginx.conf` :80, `nginx-ssl.conf` :80/:443) — les imports de backups
    chiffrés > 1 Mo étaient rejetés par le reverse proxy (défaut nginx 1 Mio)
    avant d'atteindre l'API. Cohérent avec `nginx-philia-ng.conf`.
  - **Réconciliation snapshots legacy** : `_reconcile_forked_migrations()` dans
    `restore_snapshot.py` — purge de `schema_migrations` des migrations
    homonymes divergentes (fourche 027 : `add_port_allocations` vs
    normalisation de données legacy), détectées par l'absence de la table
    attendue ; no-op prouvé sur restore normal (3 tests SQLite). Requis pour
    la migration legacy → hub neuf.
  - Déployé et vérifié sur le hub de production locale (images rebâties).
## [0.53.4] - 6 septembre 2026
### 🔧 Pointeur hubctl_src 0.7.3 → 0.7.4 — atelier : allowlist env compose (parité hub-api 3.47.3)
- **hubctl 0.7.4** (dabf196..7572afe) : `_ws_compose_env` ne transmet plus
  l'env du shell hôte au `docker compose` atelier (allowlist PATH/HOME/
  locales + `DOCKER_*` + `.workshop.env`) ; les 4 fallbacks
  `dict(os.environ)` passent à `_compose_base_env()`. Même cause que le fix
  hub-api 3.47.3 : collision de nom `HUB_HTTPS_ENABLED` (deux sens opposés)
  → atelier en « Mode dégradé ». Actif immédiatement (CLI interprété via le
  symlink `./hubctl`). 492 tests hubctl passés.
## [0.53.3] - 6 septembre 2026
### 🔧 Pointeur HUB_base 3.47.2 → 3.47.3 — atelier : fuite d'env hub + fiches -ws fantômes
- **HUB_base 3.47.3** (fca45e5..ccb208c) : deux fixes du cycle atelier piloté
  depuis la vue Santé — (1) plus aucune variable d'environnement du conteneur
  hub-api ne fuite vers les apps (allowlist `env_base` dans `_run_cmd`) : la
  collision `HUB_HTTPS_ENABLED` (hub = « sert du HTTPS » ≠ app = « joindre
  l'API en HTTPS ») cassait l'enregistrement et l'auth des ateliers (« Mode
  dégradé », invisibles du hub) — couvre aussi `_op_recreate` vers les apps
  prod ; (2) la suppression d'atelier (remove/ship) supprime désormais la fiche
  `Application {slug}-ws` (fini les lignes fantômes qui ouvraient la mauvaise
  app après réattribution des ports). 10 nouveaux tests, 43/43 workshop.
## [0.53.2] - 5 septembre 2026
### 🔁 Pointeur HUB_base 3.47.1 → 3.47.2 — SLO poste partagé : revoke distant normalisé
- **HUB_base 3.47.2** (ed0449b..fca45e5) : `propagate_remote_revoke` résout
  l'identifiant du cookie (désormais un `oidc_sub` immuable) vers l'utilisateur et
  révoque par **username courant d'abord puis oidc_sub** (double appel best-effort
  dédupliqué). Pour un utilisateur renommé, la révocation des sessions distantes
  (traducteurs exemple-app) ne manque plus la session indexée sous le nouveau nom.
  Best-effort préservé : 404/500 loggés, jamais bloquants.
## [0.53.1] - 5 septembre 2026
### 🛡️ Pointeur HUB_base 3.47.0 → 3.47.1 — backup/restore des ancres identitaires
- **HUB_base 3.47.1** (9f29457..ed0449b) : `UserExport` porte désormais le quatuor
  identitaire (`uuid`, `oidc_sub`, `prenom`, `nom`). Un restore sur hub vide ne
  régénère plus d'identifiants : les liaisons exemple-app-16 (`user_uuid`) et les
  liaisons OIDC des renommés survivent à un disaster recovery, prénom/nom préservés.
  Backups legacy rétrocompatibles (fallback génération) ; branche update inchangée.
- Clôture du follow-up backup/restore du projet identité utilisateur + OIDC sub immuable.
## [0.53.0] - 5 septembre 2026
### 🔗 Pointeur HUB_base 3.46.0 → 3.47.0 — OIDC `sub` immuable (`oidc_sub`)
- **HUB_base 3.47.0** (9fcc77c..9f29457) : le `sub` OIDC devient un identifiant
  immuable (`users.oidc_sub`, backfill = username — les liaisons clients existantes
  restent valides, zéro bascule). Émission (`id_token`/`access_token`/`userinfo`)
  et résolutions (cookie session, authorize, back-channel logout, SLO poste partagé)
  basculées sur `oidc_sub` avec fallback username pour les sessions pré-déploiement.
  Email synthétique figé `{oidc_sub}@hub.internal`. **Le renommage d'un login est
  désormais invisible pour les clients OIDC (Vikunja…) — rattachement automatique,
  plus de réassociation manuelle.** Migration additive automatique, rollback trivial.
- Docs : `docs/superpowers/specs/2026-09-05-oidc-sub-immuable-design.md`,
  `docs/superpowers/plans/2026-09-05-oidc-sub-immuable.md`.
## [0.52.1] - 5 septembre 2026
### 📄 Handover — centralisation des synchronisations des apps
- Nouveau `docs/handover/2026-09-05-sync-centralisation.md` : transfert de connaissances
  de la session exemple-app-16_API_v3 (v1.12.0, incluse dans la 1.13.0 déployée) à
  destination du chantier d'orchestrateur central de synchronisation : topologie des
  flux (exemple-app → exemple-app / exemple-app-7 → exemple-app), invariants de
  sécurité (liaison matricule-only, fiabilité `match_confidence >= 100`, homonymes →
  refus, seuil de désactivation à 3 syncs), réconciliation assistée des matricules,
  purge admin avec dry-run, incident de format d'identifiant divergent (`000xxx` vs
  `S00xxx`) et détection d'un jeu de données de démo, état final prod vérifié, suivi
  planifié en place (rapport quotidien observation-only) et recommandations
  priorisées pour l'orchestrateur (P1 identifiant canonique / fiabilité / idempotence,
  P2 planification + outbox + observabilité, P3 détection démo, contract tests,
  sécurité M2M, cycle de vie des départs).
## [0.52.0] - 5 septembre 2026
### 🆔 Pointeur HUB_base 3.46.0 — identité utilisateur : UUID stable, nom éditable, renommage du login
- **HUB_base 3.46.0** (2b568d3..9fcc77c) : `users.uuid` (identifiant stable immuable,
  backfillé au démarrage) + `users.prenom`/`users.nom` éditables par les admins ;
  claims `uid`/`prenom`/`nom` dans les JWT applicatifs et OIDC (`sub` inchangé) ;
  endpoint `POST /api/users/{id}/rename` (409 unicité, révocation tokens applicatifs
  ET OAuth refresh tokens, audit, force_logout) ; UI admin (champs état civil +
  renommage d'identifiant avec suggestion `pnom`). Migration additive automatique —
  aucun action manuelle, rollback trivial.
- Apps du parc (hors submodules, releases indépendantes synchronisées sur la feature) :
  **exemple-app-16_API_v3 1.13.0** — matching contact par `user_uuid` (fallback legacy
  `sam_account_name` + backfill à la connexion), préférences immunes au renommage,
  nom hub priorisé à l'affichage ; **exemple-app_v3 0.3.0 → 0.3.1** — ré-import CSV :
  `nom_usuel`/`prenom` rafraîchis si fournis (propagation mariage depuis la paie).
- Specs + plan : `docs/superpowers/specs/2026-09-05-identite-utilisateur-rename-uuid-design.md`,
  `docs/superpowers/plans/2026-09-05-identite-utilisateur-rename-uuid.md`.
## [0.51.7] - 3 septembre 2026
### 🐛 Pointeur HUB_base 3.45.0 → 3.45.1 — dropdown rôle du dashboard + toggles checkboxes
- **HUB_base 3.45.1** : le délégué click global (`app.js`) ne dispatche plus les
  champs de formulaire (`SELECT`, `INPUT`, `TEXTAREA`, `OPTION`…) — un `<select>`
  natif émet un `click` à l'ouverture de sa liste, ce qui relançait
  `updateMyAppRole` + `loadApps()` sur le dashboard : le re-render remplaçait le
  `<select>` pendant que sa liste était ouverte (dropdown « refermé tout seul »,
  obligeant à maintenir le bouton enfoncé).
- Effet secondaire corrigé : le `preventDefault()` du délégué click bloquait le
  toggle natif des checkboxes `data-action` (sélection de messages, select-all
  docker, confirmations restore/import…) et déclenchait leurs actions sur un
  état périmé — toggle natif + `change` rétablis.
## [0.51.6] - 3 septembre 2026
### 🧪 Pointeur HUBapp_TEMPLATE_base 2.20.3 → 2.20.4 — tests « démarrage depuis zéro » `update_env.py`
- **Template 2.20.4** : suite portée à 10 cas — **8a** : `.env` inexistant → refus
  propre (exit 1, aucune création, aucun backup — règle « fusion, jamais
  régénération » verrouillée) ; **8b** : flow premier boot sanctionné
  (`cp .env.example .env` → `update-env` complète `FRONTEND_HTTPS_PORT` et
  `APP_SUBNET`, conserve les placeholders INITIALISE, zéro duplication).
## [0.51.5] - 3 septembre 2026
### ⚡ Doc POULIDOR resynchronisée + pointeur hubctl 0.7.3 (coffre retrouvé)
- **hubctl_src 0.7.2 → 0.7.3** : chemins runtime (`vault/`, `backups/`,
  `recovery/`) résolus depuis le paquet (`hubctl_src/hubctl_cli/`) avec repli
  legacy — la suppression du symlink racine `hubctl_cli` (0.51.0) rendait le
  coffre introuvable (traité comme neuf : prompt passphrase au lieu du
  déverrouillage par `parc.vault.key`, risque d'orphelinage au `vault backup`).
- **Doc guide-hub** : instantané de versions à jour (méta 0.51.4, Hub 3.45.0,
  template 2.20.0, hubctl 0.7.2), cible `make update-env` documentée
  (template 2.20.0), throttle anti-abus OIDC (HUB_base 3.45.0), slug atelier
  normalisé (hubctl 0.7.2), chemins `hubctl_src/hubctl_cli/…` après
  restructuration (coffre, backups, _trash, .venv), note « blue-green »
  résiduelle du guide visuel retirée (atelier = sandbox), `presentation.html`
  reliée depuis toutes les navs.
- **README** : création d'app documentée via seed/`create_app.sh` (l'entrée
  TUI « Apps → Ajouter » n'existe plus), tables Documentation et Skills
  complétées (`presentation.html`, guide-parc, guide-template, debug-agent,
  `migrate-app-template`, `hub-oidc-manager`).
## [0.51.4] - 3 septembre 2026
### 🧪 Pointeur HUBapp_TEMPLATE_base 2.20.2 → 2.20.3 — tests de non-duplication `update_env.py`
- **Template 2.20.3** : `scripts/test_update_env.py` — 8 cas autonomes (sans Docker
  ni pytest) verrouillant la fusion B.0 : clés existantes avec valeur intouchées,
  orphelines préservées, clé vide remplacée en place, clé absente ajoutée une seule
  fois (régression fix 2.20.2), détecteur réseau indisponible, idempotence
  (2ᵉ exécution = no-op), invariant « chaque clé exactement une fois ». 8/8 OK.
## [0.51.3] - 3 septembre 2026
### 🔧 Pointeur HUBapp_TEMPLATE_base 2.20.1 → 2.20.2 — fix `update_env.py`
- **Template 2.20.2** : `scripts/update_env.py` perdait silencieusement les clés
  dérivées (`FRONTEND_HTTPS_PORT`, `APP_SUBNET`) **absentes** (pas seulement vides)
  du `.env` — `re.sub` ne remplaçait aucune ligne mais le rapport annonçait
  « ✅ fusionné ». Correctif : `re.subn` + ajout en fin de fichier. Cas réel validé
  (exemple-app : `APP_SUBNET` désormais écrit, valeurs critiques inchangées).
- **exemple-app v1.15.0** (repo indépendant) : `make update-env` câblé (B.0),
  clé `FRONTEND_HTTPS_PORT` ajoutée au `.env.example` personnalisé, hygiène
  `.gitignore` `.env.pre-*` (backups = secrets).
## [0.51.2] - 2 septembre 2026
### 🔧 Pointeur HUBapp_TEMPLATE_base 2.20.0 → 2.20.1 — skill `app-dependencies` aligné sur l'atelier réel
- **Template 2.20.1** : skill `app-dependencies` resynchronisé sur le modèle atelier
  implémenté — retrait des références fictives (menu « APPS → Atelier » avec sélection
  `[→]`, groupe de deps emmené automatiquement, vérification dans `APP_Workshop/`,
  `resolve_group`, `hubctl_cli/dependencies.py::build_graph()`) ; la section devient
  « Dépendances et atelier » : l'atelier `-ws` tourne à côté de la prod (qui reste en
  place), les appels M2M résolvent vers les instances prod, pas de groupe à emmener.
  `report_sync` / `depends.yaml` / endpoints Hub (réels) inchangés.
- **Propagation aux copies d'apps** (repos indépendants, releases patch poussées) :
  exemple-app 0.3.1, exemple-app 0.12.1, exemple-app 0.9.1, exemple-app 1.10.1,
  exemple-app 0.10.1 (master) — cette dernière avec réparation du frontmatter YAML
  du skill (absent → skill non chargé). **Non propagé** : exemple-app (atelier
  actif + working tree dirty — à resynchroniser après clôture de l'atelier) ;
  copie dans `hubctl_src/hubctl_cli/_trash/` ignorée (corbeille).
## [0.51.1] - 2 septembre 2026
### 🔧 Alignement doc/skills sur le modèle atelier implémenté (`hubctl atelier`)
La vague v0.51.0 avait introduit une régression documentaire : skills et README décrivaient
un modèle atelier **jamais implémenté** (copie physique `APP_Workshop/<slug>-ws`,
commandes `work`/`ship`/`deploy`, `--copy-db`, multi-slug, marqueur `.dev-mode`,
déploiement blue-green). Alignement de tous les documents sur le code réel
(`hubctl_src` v0.7.2, `actions.py` + `__main__.py`) et sur le contrat partagé avec le
Hub (`workshop_service`, `.workshop.env` 7 clés) :
- **Skill `app-workshop-mover`** : restauration de la version exacte — cycle
  `./hubctl atelier X` / `--maj [--ref R]` / `--prod` / suppression via menu, projet
  compose `-p X-ws`, override `APPS/X/.workshop.env`, working tree partagé (jamais de
  `git pull` manuel), Red Flags anti-`work`/`ship`/`--copy-db` rétablis.
- **Skill `create-hub-app`** : suppression du mode « copie vers `APP_Workshop/<slug>-ws` »
  et du marqueur fictif `.dev-mode` — une app se crée toujours dans `APPS/<slug>` ;
  l'atelier est un cycle séparé (`./hubctl atelier`). Étape D.2 rewordée (`make dev` =
  choix hot-reload, pas un marqueur).
- **Skill `vault-manager`** : entrée coffre `ws:<nom>` → `APPS/<nom>/.workshop.env`
  (aligné sur `_target_path` de `vault_manager.py`) ; note sur les entrées legacy
  `ws:` conservées mais plus restaurées par `export_recovery`.
- **`README.md`** : liste de commandes remplacée par les 12 sous-commandes réelles
  (`start stop update atelier init export restore pra-restore debug vpn vault seed`) ;
  suppression du blue-green fictif ; arborescence `hubctl_src/` (le symlink racine
  `hubctl` pointe vers `hubctl_src/hubctl`), retrait d'`APP_Workshop/`.
- **`docs/guide-parc-poulidor.md`** : retrait du terme « blue-green » (sections 3.4/5.2
  et entrée de glossaire) — l'atelier est une sandbox de test, pas une bascule de trafic.
  Les `make db-shell` (cible Makefile du template) restent valides.
- **`APP_Workshop/`** : dossier vide (héritage du schéma legacy) supprimé du disque,
  règles `.gitignore` associées retirées.
## [0.51.0] - 2 septembre 2026
### ⚙️ Restructuration repo + resynchronisation doc & skills + fix MCP z.ai
- **Restructuration hubctl** : le wrapper `hubctl` de la racine devient un symlink
  `hubctl → hubctl_src/hubctl` (résolution de symlinks gérée côté wrapper), le symlink
  `hubctl_cli` est supprimé (références doc migrées vers `hubctl_src/hubctl_cli`).
  Pointeur sous-module `hubctl_src` : v0.7.1 → **v0.7.2** (wrapper symlink-safe, `.secrets`
  lu depuis `PARC_ROOT`, slug atelier strict `_`→`-` pour la résolution des rôles JWT,
  subnet IPAM None-safe).
- **`install.sh` épuré** : support restreint à Ubuntu/Debian-like via repo Docker
  (Mint remappé sur `noble`), retrait de l'init des submodules et de l'installation du
  firewall VPN — la gestion VPN est prise en charge par `hubctl vpn` (volume
  `hub_base_vpn-config`, toggle `vpn_enabled` en DB).
- **`opencode.json`** :
  - MCP hub lancé en direct (`python3 -m hub_mcp.server` dans `hub-mcp/`).
  - **Corrigé** MCP `zai-mcp-server` : clé invalide `env` → `environment` (clé
    attendue par le schéma `McpLocalConfig`), placeholder `"your_api_key"` →
    interpolation `{env:Z_AI_API_KEY}` (la clé ne transite jamais dans git).
    Nouveau script `scripts/set-zai-key.sh` : persistance idempotente de la clé dans
    `~/.bashrc` (bloc marqué), modes `--show`/`--mode ZAI|GLM`.
- **`.gitignore`** : les seeds ne sont plus ignorés — `seed-apps.yaml` (déploiement
  déclaratif de 4 apps) et `seed-export-2026-07-31.yaml` (export de parc) sont
  committés, URLs git SSH uniquement (aucun secret).
- **Guide HTML (`docs/guide-hub/`)** : vague de resynchronisation (0.23.4 → 0.51.0) —
  nouvelle page `presentation.html` (liée depuis la nav de toutes les pages), hubctl
  0.7.x documenté fidèlement (touches par mode PROD/DEV, sous-commandes, atelier via
  `APPS/<slug>/.workshop.env` + projet compose `-p X-ws`, coffre/PRA), footers de
  version resynchronisés.
- **Docs parc** : `guide-parc-poulidor.md` (instantané à jour, 24 routeurs Hub),
  `guide-developpement-template.md` (modes `INITIALISE`, `APP_SUBNET`,
  `POSTGRES_PORT`), `README.md` (arborescence `APP_Workshop/`, CLI hubctl re-listé),
  `docs/debug-agent.md` (Ollama, 3 nouveaux outils MCP), archivage de
  `DEV_MODE_MIGRATION.md`.
- **Skills & charte agent** : `AGENTS.md` + `agent/jellycode.md` allégés (référentiel
  visuel migré vers HUBCSS, sections obsolètes retirées) ; réécriture
  `app-workshop-mover` (modèle sandbox `APP_Workshop/<slug>-ws` + déploiement
  code-only par défaut, `--copy-db` destructif CLI-only) ; `create-hub-app` (Phase E
  conventions backend, Phase F renvois skills) ; `hub-oidc-manager` autoportant
  (diagramme IdP, vars OIDC, endpoints) ; `release-on-main` (question patchnote
  systématique) ; `vault-manager` (entrée coffre `ws:<nom>`).
- **Journal SDD** (`.superpowers/sdd/`) : trace les 3 projets récents (refonte UI admin
  v1.7.0, banc lab coexistence v1/v2 + changement de port HUB, plan correctifs
  gestion IP/port).
- **`.secrets.example`** : retrait du bloc documentaire `HUB_BASE_URL`/`HUB_ADMIN_*`
  (placeholders, plus d'actualité).
## [0.50.0] - 2 septembre 2026
### 🔐 Skill migrate-app-template : fusion automatique du `.env` (B.0) + pointeur HUBapp_TEMPLATE_base v2.19.0 → v2.20.0
- **Skill `migrate-app-template`** : nouvelle étape **B.0 — Migration du `.env`** (obligatoire, avant tout rebuild). Le `.env` d'une app existante contient des valeurs absentes du `.env.example` (`HUB_INSTANCE_ID`…) et il lui manque les nouvelles clés du template ; `make sync-env` ne fusionne rien. Règle : **fusion, jamais régénération** (`cp .env.example .env` casse les identifiants DB du volume existant).
  - Voie automatisée : `scripts/update_env.py` (copié depuis le template) / `make update-env` — sauvegarde horodatée, ajout des clés manquantes, valeurs existantes et orphelines préservées, vérification des variables requises du compose (`${VAR:?}`) avec exit 1 explicite, dérivées recalculées (`FRONTEND_HTTPS_PORT`, `APP_SUBNET` relu sur le réseau Docker existant). Fonctionne sans Hub ni make (serveurs de déploiement).
  - Voie manuelle conservée en repli + table des valeurs critiques à ne jamais changer (`POSTGRES_*`, ports, `APP_SLUG`, `APP_SUBNET`, `HUB_INSTANCE_ID`).
  - Incident réel documenté (déploiement client) : compose neuf tiré par git + `.env` ancien → `APP_SUBNET` manquant, puis `cp .env.example .env` hasardeux.
  - Description du skill enrichie (triggers : `.env` obsolète, base inaccessible après migration).
- **2.20.0** : `scripts/update_env.py` + cible `make update-env` dans le template, `.gitignore` `.env.pre-*` (sauvegardes de `.env` = secrets).
- Application du parc migrée avec ce processus : **exemple-app** (UI HUBCSS 0.2.0, fix tables 0.2.1, update-env 0.3.0 — dépôt `exemple50/exemple-app`, indépendant du méta-repo).
---
## [0.49.0] - 1er septembre 2026
### 🛡️ Pointeur sous-module HUB_base v3.44.4 → v3.45.0
- **3.45.0** : throttle anti-abus sur `/api/oidc/token` — après le retrait du
  rate-limit IP (3.44.4), frein posé sur les **échecs** (400/401) par
  `client_id` : 30 échecs / 60 s → 429 + `Retry-After`. Les succès ne sont
  jamais comptés (SSO légitime incapable d'être pénalisé), garbage sans
  client_id plafonné par IP, isolation par client, log WARNING d'observabilité.
  Motivé par l'audit du risque résiduel post-3.44.4 (hammering bcrypt/DB sans
  plafond).
---
## [0.48.2] - 1er septembre 2026
### 🐛 Pointeur sous-module HUB_base v3.44.3 → v3.44.4
- **3.44.4** : retrait du rate-limit IP sur `/api/oidc/token` — en SSO hub-only,
  l'échange code→token est server-to-server (une seule IP source pour tous les
  utilisateurs d'une app) ; le plafond 10 req/min/IP provoquait des
  `429 Too Many Requests` sur les connexions Vikunja rapprochées. Protection
  conservée : client secret, codes one-shot, PKCE + rate-limit 5/min/IP sur la
  saisie de mot de passe. Tests OIDC mis à jour, cahier des charges aligné.
---
## [0.48.1] - 31 août 2026
### 🔧 Pointeur sous-module HUB_base v3.44.0 → v3.44.3
- **3.44.1** : badge de version navbar dynamique (servi par `/health` — source
  unique de vérité), `sync_version.py` durci (attributs tolérés)
- **3.44.2** : détection de l'IP LAN du serveur (`GET /api/config/network/detect-host-ip`,
  conteneur jetable en réseau host + iproute2) — bouton « Détecter » de l'onglet Réseau
- **3.44.3** : hygiène — `secrets/hub_instance_id` retiré du dépôt (artefact runtime,
  gitignoré)
---
## [0.48.0] - 31 août 2026
### 🌐 Pointeur sous-module HUB_base v3.44.0 — changement d'IP validé par l'admin
- **HUB_base 3.43.0** : correctifs de la gestion des ports (injection compose des
  pools, `Settings.hub_api_port`, `instance_id` exposée, Makefile override, hygiène)
- **HUB_base 3.44.0** : changement d'IP du Hub validé par l'admin — état réseau,
  `PUT/DELETE /api/config/network/hub-host` (persistance + mutation à chaud +
  override boot), plan de propagation (`GET/POST propagation-plan`, validation par
  liste de slugs), `POST /api/apps/{slug}/recreate` (`--force-recreate` + health),
  onglet admin « Réseau »
- **HUBapp_TEMPLATE_base 2.19.0** : sync-env propage ports + garde `HUB_INSTANCE_ID`
- **hubctl 0.7.1** : `OIDC_ISSUER` réécrit au changement de port, résumé ports réels
- Source : diagnostic banc de coexistence — docs/superpowers/specs/2026-08-31-hub-port-change-lab-rapport.md
---
## [0.47.0] - 31 août 2026
### 🔧 Correctifs gestion des ports du HUB (diagnostic banc)
- HUB_base 3.43.0 : injection compose des pools, Settings hub_api_port,
  instance_id exposée, hub-host renvoie les ports, Makefile override, hygiène
- HUBapp_TEMPLATE_base 2.19.0 : sync-env propage les ports + garde d'instance
  (exit 1 sur hub différent, fini la validation silencieuse du mauvais hub)
- hubctl 0.7.1 : OIDC_ISSUER réécrit au changement de port, résumé ports réels
- Source : docs/superpowers/specs/2026-08-31-hub-port-change-lab-rapport.md
  (18 écarts du banc POULIDOR-lab)
## [0.46.2] - 31 août 2026
### ⚡ Pointeur sous-module HUBapp_TEMPLATE_base v2.18.2
- Audit complet de la chaîne des ports du template (.env → compose → backend →
  frontend/nginx) : plus aucun port hôte en dur. Fixes inclus (détail : CHANGELOG
  HUBapp_TEMPLATE_base [2.18.2]) :
  - certs PKI écrits dans `/app/ssl` (SSL_DIR) — atteignaient `/ssl` hors volume,
    nginx ne voyait jamais le renouvellement en prod ;
  - `POSTGRES_PORT` réellement dynamique (PGPORT sur le conteneur postgres) ;
  - actions générées `START`/`UPDATE` passent par sync-env (plus d'échec au
    premier démarrage avec ports vides) ;
  - `depends.yaml` résolu dans `backend/` (visible en conteneur).
## [0.46.1] - 30 août 2026
### ⚡ Pointeur sous-module HUBapp_TEMPLATE_base v2.18.1
- Fix boot apps sur hub legacy : `HUB_API_PORT`/`HUB_FRONTEND_PORT` vides → fallback
  8000/80 (validator pydantic + défauts docker compose) au lieu d'un crash uvicorn.
  Détail : CHANGELOG HUBapp_TEMPLATE_base [2.18.1].
## [0.46.0] - 27 août 2026
### 🚀 Configurer le dépôt git d'une app depuis l'UI (HUB_base v3.39.0)
- Bouton « Configurer le dépôt git » dans la vue Santé (apps sans remote, avec ou sans
  atelier) : modale configurer-**et-tester** — enregistre l'URL en DB, configure `origin`
  du repo local, teste `ls-remote` immédiat avec verdict (✓ N branches / ✗ cause git).
  HTTPS uniquement (SSH refusé). Le form admin synchronise le remote best-effort.
- **PAT GitHub branché dans les fetch du cycle atelier** : mises à jour/déploiements
  d'atelier fonctionnent désormais sur les repos **privés** (token `github_token`
  existant, jamais affiché). Validé en live contre un repo privé GitHub du parc.
- Fix verdict : la cause git utile est conservée (préfixe technique retiré).
## [0.45.2] - 27 août 2026
### ⚡ HUB_base → 3.38.2 (page Audit : heatmap quasi instantanée, plage limitée au mois)
- **HUB_base → 3.38.2** (depuis 3.38.1) : heatmap d'activité de la page Audit réécrite en
  O(sessions + heures couvertes) et exécutée hors event loop (`anyio.to_thread`) — mesuré
  sur la prod (~3 700 sessions) : **13,3 s → 5 ms** à 90 j. La vue d'ensemble
  (KPIs/alertes/sessions live) ne bloque plus sur le graphique (chargement découplé +
  garde anti-réponse-périmée). Bouton 90j retiré du sélecteur de période (plage
  24h/7j/30j), endpoint API inchangé. +2 tests backend : équivalence stricte vs
  référence naïve (propriété) et garde-fou perf 90 j / 4 000 sessions < 1 s.
## [0.45.1] - 27 août 2026
### 📖 Guide du parc — carte du territoire pour développeurs & admins
- **Nouveau `docs/guide-parc-poulidor.md`** (~1080 lignes, 6 sections) : démarcation
  HUB_base / hubctl / template, **toutes les commandes** (12 sous-commandes hubctl,
  6 cibles Makefile Hub, 35 cibles template, options exactes vérifiées dans le code),
  inventaire des fonctionnalités (21 routeurs en 8 blocs, 12 blocs clé-en-main du
  template, 13 skills), 4 cas d'usage pas-à-pas (créer une app, déployer via atelier,
  sinistre — arbre vault/restore/pra-restore, secrets), cheat-sheet 28 commandes,
  matrice « quel doc pour quel besoin », pièges classiques. 6 schémas conceptuels ASCII
  (architecture Hub, SSO/JWT, parc vu par hubctl, coffre & kit PRA, cycle atelier,
  anatomie d'une app). Construit tâche par tâche avec revues : 12 faits transversaux
  échantillonnés en revue finale — 0 erreur ; 21/21 liens validés.
- **Nouveau `docs/visualDev_guide.html`** (guide visuel compagnon, navigateur) :
  5 diagrammes **Mermaid** validés par parsing réel (séquences SSO/JWT et M2M,
  flowcharts atelier+rollbacks, décision sinistre, couches de résilience), table des
  12 sous-commandes, TUI réel (raccourcis PROD/DEV, garde UI 3.38.0), pools prod vs
  atelier, services du Hub, footer renvois. Correctifs factuels : PostgreSQL 15 (pas
  16) pour les apps, table `outbox`, deps pip → `make build` (pas restart-api),
  SAVEPOINT par statement, ports Nginx internes.
- **README** : section « Documentation » (fusionnée avec l'existante) ; corrections
  `--validate` fantôme → `atelier --maj/--prod`, TUI « Apps → Ajouter » obsolète →
  `create_app.sh` + INITIALISE.
- Note guide : pilotage atelier UI (Hub 3.38.0+) — ne pas lancer hubctl et l'UI
  simultanément sur la même app.
- **Submodule `HUB_base` → v3.38.1** (atelier UI + fixes retour terrain ; le pointeur
  0.45.0 avait été omis dans 8c5825f).
## [0.45.0] - 27 août 2026
### 🚀 Atelier pilotable depuis l'UI HUB (HUB_base v3.38.0)
- Le cycle atelier complet (créer / mettre à jour / déployer en prod / supprimer) est
  pilotable depuis la vue « Sante des Applications » (admin) : bloc d'état sur chaque carte
  (`main @ commit · version`), confirmations renforcées (ship / suppression), modal de
  progression avec polling 2 s. 6 endpoints admin `/api/apps/{slug}/workshop*` exécutés par
  `workshop_service` (pattern deploy : une opération à la fois, suivi en DB, purge 30 j).
- Dualité UI/CLI assumée : hubctl v0.6.1 reste l'outil de secours HUB-down ; `.workshop.env`
  (7 clés) = contrat partagé figé par contract tests. Garde-fous parité hubctl : ship
  `origin/main` uniquement, commit testé, atelier conservé si échec prod. Subnet atelier
  dédié (pool `10.210.x`, plages ports hubctl) → coexistence prod + atelier.
- Skill `app-workshop-mover` mis à jour (section Pilotage UI).
- Spec : `docs/superpowers/specs/2026-08-23-workshop-ui-sante-design.md` —
  plan : `docs/superpowers/plans/2026-08-23-workshop-ui-sante.md`.
## [0.44.0] - 25 août 2026
### 🤖 Persona Jellycode + template 2.18.0 (opencode)
- **HUBapp_TEMPLATE_base → 2.18.0** (depuis 2.17.0) : persona agent `jellycode`
  (`default_agent` + plugin `superpowers` pinné) ajouté au template — hérité par chaque
  app générée/migrée.
- **jellycode.md** : listes de skills complétées (5 parc + 1 app manquants), chemins
  corrigés (`styles/app.css`, `components/demo/FormDemo.jsx`), note d'auto-découverte ajoutée.
## [0.43.1] - 25 août 2026
### 📖 HUB_base → 3.37.1 (cahier des charges mis à jour)
- **HUB_base → 3.37.1** (depuis 3.37.0) : cahier des charges mis à jour à l'état de l'art
  v3.37.0 — nouveaux modules « Déploiement automatique des applications » (§7.7) et
  « Suivi d'usage et présence (uptime) » (§8.4), chiffres clés réactualisés (tests ≈726,
  tables ≈34, domaines 22).
## [0.43.0] - 24 août 2026
### 🔐 Fin de la saisie manuelle de la passphrase du coffre
- **hubctl_src → 0.7.0** (depuis 0.6.1) : la passphrase du coffre (`parc.vault.enc`) est désormais
  **générée automatiquement** (`secrets.token_urlsafe`) et conservée dans
  `hubctl_cli/vault/parc.vault.key` (chmod 0600, gitignoré) — plus aucune saisie à l'installation
  ni au démarrage : déverrouillage silencieux dans le TUI, le sous-menu Coffre et `hubctl vault …`.
- **Migration douce** : les coffres existants (passphrase saisie à la main) demandent la passphrase
  une dernière fois puis la mémorisent ; « 🔑 Changer la passphrase » resynchronise la clé.
- **Kit PRA** : `parc.vault.key` est répliqué avec le coffre sur l'emplacement secondaire (sans elle
  le kit serait indéchiffrable) ; `pra-restore` lit la clé du kit (repli saisie pour les kits anciens).
- **Sécurité (assumée)** : la clé vit en clair à côté du coffre — le coffre est une sauvegarde
  lecture-seule, pas une frontière (les `.env` sont déjà en clair sur disque). 479 tests (+19).
- **Docs** : skill agent `vault-manager` mis à jour (règle de cycle §1, API `unlock_stored` /
  `generate_passphrase`).
## [0.42.0] - 23 août 2026
### 🚀 Uptime utilisateur fiable + présence par application
- **HUB_base → 3.37.0** (depuis 3.35.0) : fiabilisation complète du suivi d'uptime — stabilisation
  sessions/segments (v3.35.1 : heartbeats perdus, fermetures SSE non committées, timestamps futurs,
  dédoublonnage, cleanup au boot), présence par application via le heartbeat SSE `?app=<slug>`
  (v3.36.0 : segments parallèles par couple (session, app), fermeture ciblée `disconnect`), traçage
  SSO OIDC (v3.37.0 : `ensure_session_presence` sur authorize/launch). E2E validé en prod.
- **HUBapp_TEMPLATE_base → 2.17.0** : l'URL SSE construite par les apps porte `&app=<slug>`
  (`VITE_APP_SLUG`) — rétrocompatible, déployable avant le HUB. **Rollout parc requis** pour
  activer la présence par app (14 stacks, phase 4 du plan — `docs/superpowers/plans/
  2026-08-23-uptime-utilisateur-fiable.md`, spec heatmap incluse).
- UI Audit : « Activité de la journée » refonte en heatmap app × tranches 3h (design validé),
  répartition une barre par app, KPI « Segments ».
## [0.41.0] - 23 août 2026
### 🚀 Atelier — test de mise à jour + déploiement prod (hubctl v0.6.1)
- L'atelier peut désormais **tester une montée de version** : `./hubctl atelier X --maj` récupère
  `origin/main` (ou `--ref <branche|tag>`) et la rebuild sur le clone de DB — migrations rejouées au
  boot, zéro risque prod. `./hubctl atelier X --prod` déploie le main validé (garde-fous : atelier
  sain, commit testé == origin/main) puis supprime l'atelier ; échec prod → rollback, atelier conservé.
- Subnet atelier dédié (pool `198.51.100.0/24` – `198.51.100.10/24`, overlap vérifié) : prod et atelier
  coexistent sur les apps du template actuel (subnet épinglé).
- Revue finale : sûreté dry-run (Ctrl-C ne déclenche plus de rollback réel), worktree fail-closed
  sans upstream, restore git sur échec SYNC, allocation subnet par élément.
- Skill `app-workshop-mover` mis à jour (cycle complet maj/ship, garde-fous, dry-run global,
  récupération post-interruption) + README hubctl.
- Spec : `docs/superpowers/specs/2026-08-23-workshop-update-ship-design.md` —
  plan : `docs/superpowers/plans/2026-08-23-workshop-update-ship.md`.
## [0.40.2] - 23 août 2026
### ⚡ MCP hub standalone robuste au contexte de lancement
- **Ajouté** : `mcp-hub.sh` (racine) — wrapper autonome du serveur MCP `hub` : chemins résolus depuis la position du script (insensible au cwd d'opencode), source `.secrets` avant lancement (`set -a`/`set +a`, même pattern que le wrapper `hubctl` → indépendant du shell appelant), avertissement stderr explicite dès le démarrage si `.secrets` est absent. Aucun secret committé (`.secrets` reste gitignoré).
- **Corrigé** : `opencode.json` — la commande MCP `hub` (`cd hub-mcp && python3 -m hub_mcp.server`, chemin relatif + creds hérités de `~/.bashrc`) listait bien les outils mais faisait échouer **chaque appel** quand opencode était lancé hors shell interactif bash (IDE, lanceur graphique, autre shell : `HUB_BASE_URL`/`HUB_ADMIN_USERNAME`/`HUB_ADMIN_PASSWORD` absents → `StandaloneHubClient` levait « variables d'environnement manquantes »). La commande devient `["bash", "mcp-hub.sh"]`.
- **Vérifié** : probe protocole MCP complet (initialize → tools/list → tools/call) lancé depuis un cwd étranger avec les 3 variables retirées de l'env → 65 outils exposés, `hub_health` et `hub_app_list` (login admin via `.secrets` sourcé par le wrapper) OK ; régression OK en conditions normales ; mode dégradé sans `.secrets` → avertissement stderr + erreur explicite à l'appel.
---
## [0.40.1] - 23 août 2026
### 🔺 Sous-modules
- **HUB_base v3.35.0** — refonte UI de la vue Préférences (visible par tous les utilisateurs) : composants de sélection à seuil automatique (chips ≤ 12 valeurs / sélecteur avec recherche insensible aux accents > 12), autosave avec indicateur d'état (debounce 600 ms, fin du bouton « Enregistrer mes choix »), sommaire sticky avec pastilles de progression, onglets admin-only (les non-admin voient le contenu directement). Fixes : toggle chips cassé par le `preventDefault` du délégateur `data-action`, SSE `tags_updated` bruyant à chaque autosave (refresh token silencieux — tags dans les claims JWT — + re-render limité aux actions `category_*`), création de catégorie CSV en 422 (`m2m_endpoint: null` refusé par le schéma depuis `211d622`). Aucun changement backend.
---
## [0.40.0] - 23 août 2026
### 🔺 Sous-modules
- **HUBapp_TEMPLATE_base v2.16.0** — garde de fraîcheur d'image pour `make test-docker` / `test-docker-cov` : script `ACTIONS/PYTHON/check_image_freshness.py` (stdlib, codes de sortie 0/1/2) + cible make interne `ensure-api-fresh` (auto-rebuild `sync-env` → `build api` → `up -d api` quand les sources sont plus récentes que l'image ; dry-run respecté ; mode dev ignoré sans jamais recréer le conteneur). Stamp `.api-image.stamp` corrigeant la boucle de rebuild infinie quand BuildKit réutilise le cache. Fix `backend/VERSION` parasite (mountpoint créé par le montage `./VERSION:/app/VERSION:ro` du compose dev, qui écrasait `/app/VERSION` au `COPY backend/` → crash FastAPI) : exclusion `.dockerignore` + `COPY VERSION` après `COPY backend/` + `.gitignore`.
---
## [0.39.5] - 23 août 2026
### 🔺 Sous-modules
- **HUB_base v3.34.3** — fix régression « opérations en masse » utilisateurs (data-args apostrophés, bouton Analyser CSV mort, handlers CSP-bloqués) ; complétion de la migration CSP `data-action` (156 handlers inline restants sur 25 fichiers, 176 attributs collés, retrait de l'escape-hatch `new Function`) avec support `data-arg1..9` dans le délégateur ; coercions `parseInt` sur 16 récepteurs d'ids (boutons Modifier muits) ; UX backups des apps lien only (badge + actions masquées, `is_unmanaged` exposé API) ; `js/window-close.js` CSP-safe pour les pages autonomes.
---
## [0.39.4] - 22 août 2026
### 🔺 Sous-modules
- **HUBapp_TEMPLATE_base v2.15.2** — conformité HUBCSS du template (audit complet) : badges `.role-*`/`.category-*` en tokens `*-soft` (fix illisibilité dark mode), suppression des overrides `[data-theme="dark"]` manuels, rgba/hex/radius/shadows/mono → tokens `--hub-*`, `alert()` éradiqué (MessageBanner + feedback inline), emojis UI → Lucide, styles inline M2MTests/FormDemo → classes.
---
## [0.39.3] - 22 août 2026
### 🔺 Sous-modules
- **HUB_base v3.34.2** — self-healing M2M : sélection du SA *propriétaire* au ré-enregistrement (corrige la rotation du secret d'un SA étranger pour les apps partagées) + recréation automatique du SA disparu (audit `m2m_sa_recreated`).
- **HUBapp_TEMPLATE_base v2.15.1** — client : `_recover_credentials` via register trusted (voie `regenerate-secret` morte post-H9), payload recover complet.
### 📦 Apps
- **exemple-app-7 v1.7.1** (repo dédié) — creds M2M persistés en volume + self-healing via register + fix slug d'accès frontend (`exemple-app` → `exemple-app`). Incident 401 du 20/08 clos : app sur l'identité officielle (9003/4206), données migrées.
- **exemple-app v2.15.4** (repo dédié) — alias réseau `backend` remplaçant le lien Docker legacy (crash-loop frontend à chaque recréation api).
---
## [0.39.2] - 21 août 2026
### 🔺 Sous-modules
- **HUB_base** → v3.34.1 : stabilité SSE — heartbeat serveur 30 s → 15 s (Firefox coupe une connexion SSE ~25-29 s après le dernier octet reçu ; les pings à 30 s arrivaient trop tard → déconnexions toutes les ~55 s en boucle). Frontend : polling de badges en repli uniquement pendant les coupures SSE, suppression de la double reconnexion post-coupure, et fix du TypeError au clic « Nouvelle préférence » (référence à `tagFormM2mEndpoint` disparue du modal). Test de régression sur la cadence du heartbeat ajouté.
---
## [0.39.1] - 20 août 2026
### 🔺 Sous-modules
- **HUBapp_TEMPLATE_base** → v2.15.0 : merge des deux branches en attente — `feat/sync-env-hub-host` (découverte auto de l'IP du Hub via `make sync-env`, cible dédiée `sync-hub-host`, bootstrap du `.env` au premier démarrage) et `feat/devtools-integration` (MSW, TanStack Router/Form, DevTools conditionnés à `import.meta.env.DEV`). Réalignement des fichiers dérivés de version (`package.json`, `APP_VERSION`), correction de variables CSS obsolètes (`--color-*` → alias actuels).
---
## [0.39.0] - 17 août 2026
### 🧪 Skill `vm-lab` — labos VM Debian 12 persistants (nouveau)
- **Ajouté** : `.opencode/skills/vm-lab/` — labos VM nommés et persistants pour reproduire des bugs en environnement propre, tester des branches sur VM vierge, et **simuler des serveurs clients réels** (diagnostic support) en injectant leurs données de restauration. 3 recettes documentées + 7 pièges capitalisés du test fresh-install.
- **Ajouté** : `scripts/lib/vm-lab.sh` — `create/start/ssh/push/inject/restore/list/destroy`, périmètre strict `build/vm-lab/` (l'archive de preuves `build/fresh-install/` est intouchable), image de base hardlinkée (0 Mo), port SSH persisté (`port.txt`), `journal.md` par labo, garde-fous (≤ 2 labos, ≥ 20 Go libres, destroy limité aux enfants directs).
- **Restauration** : kit PRA → `hubctl pra-restore --yes` ; archive `park-*.tar.gz` → `hubctl restore --passphrase-stdin` ; artefact non reconnu → injection + guidance. Passphrase toujours demandée à l'humain, pipée, jamais stockée.
- S'appuie sur `vm-debian12.sh` (FI_ROOT redirigé) — zéro duplication des primitives QEMU.
## [0.38.0] - 17 août 2026
### 🧪 Test fresh-install Debian 12 — validation, correctifs et harness
Première validation complète de l'installation de zéro sur Debian 12 pur (VM QEMU/KVM jetable) : **avant ces correctifs, `install.sh` échouait en Phase 1 sur Debian (exit 100)**. Cycle complet validé (installation → santé Hub → login admin → smoke hubctl → création d'app approuvée) et rejouable via le nouveau harness.
### 🔧 install.sh — installation sur Debian
- **Corrigé** : dépôt Docker ajouté via l'URL **Ubuntu** avec un codename Debian (`does not have a Release file`) → détection de distribution, `download.docker.com/linux/debian` sur Debian.
- **Corrigé** : fallback paquets système installait `docker-compose-v2` (paquet inexistant sur bookworm) → mort du script exit 100 **silencieux** → `docker-compose` sur Debian + message `err()` explicite en cas d'échec de paquet.
- **Corrigé** : non-idempotence de l'ajout du dépôt (`gpg --dearmor` refusait d'écraser un keyring existant → curl erreur 23 → bascule silencieuse docker.io) → `--dearmor --yes`.
### 🧰 Harness fresh-install (nouveau)
- **Ajouté** : `scripts/test-fresh-install.sh` — orchestrateur (VM Debian 12 jetable + 23 assertions A2→A8 : clone sous-modules, install, santé Hub, login admin, smoke hubctl, création d'app bout-en-bout) avec rapport pass/fail, `--keep`, `--branch`.
- **Ajouté** : `scripts/lib/vm-debian12.sh` — primitives VM (création QEMU/cloud-init, SSH agent-forwardé, push de branche par git bundle incluant les sous-modules, destruction).
### 🔺 Sous-modules
- **hubctl_src** → v0.5.2 : whitelist LAN réelle à l'init (fini le `192.0.2.0/24` magique → 403) ; URL API `http` exacte dans le résumé.
- **HUB_base** → v3.32.3 : `POST /api/auth/login` renvoie le vrai `must_change_password` ; GUIDE_INSTALLATION corrigé (`up -d` au lieu de `restart`, troubleshooting 403 whitelist, note HTTPS app).
- **HUBapp_TEMPLATE_base** → v2.14.0 : `INITIALISE.py --yes` (confirmation non-interactive du mode profil).
### 📖 Docs
- README : liste réelle des sous-commandes hubctl (les commandes `work`/`ship`/`deploy`/`logs`/`health`/`db-shell`/`status` n'existaient pas) ; prérequis SSH GitHub + note whitelist réseau au démarrage rapide.
## [0.37.1] - 16 août 2026
### 🔧 hubctl v0.5.1 — durcissements du kit PRA (revue finale)
- **hubctl_src** → v0.5.1 : pointeur de sous-module avancé sur `main`.
  - Badge `⚠ PRA` calculé par le poll worker (plus d'I/O montage dans le thread
    de rendu — un NFS mort ne gèle plus le dashboard).
  - `pra-restore` : preflight Docker (binaire + daemon) avant toute action ;
    `build_stack` s'arrête proprement sur échec `make build`/`make up-prod`.
  - Réplication : garde fraîcheur (mtime < 120 s) + vérif taille post-copie —
    un snapshot partiel ne peut plus être marqué synchronisé sur le kit.
  - Tests : 408 (12 nouveaux).
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
