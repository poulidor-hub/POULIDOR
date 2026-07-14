# Changelog - POULIDOR (HUB stack)

> Historique des versions du méta-dépôt agrégeant le HUB et les applications du parc.

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
