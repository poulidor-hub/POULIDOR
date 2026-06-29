# Changelog - POULIDOR (HUB stack)

> Historique des versions du méta-dépôt agrégeant le HUB et les applications du parc.

---

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
