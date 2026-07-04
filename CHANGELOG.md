# Changelog - POULIDOR (HUB stack)

> Historique des versions du méta-dépôt agrégeant le HUB et les applications du parc.

---

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
