# Changelog - POULIDOR (HUB stack)

> Historique des versions du méta-dépôt agrégeant le HUB et les applications du parc.

---

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
