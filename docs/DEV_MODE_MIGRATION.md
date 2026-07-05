# Migration DEV Mode — Checklist du parc HUB_app

> **Objet :** Déployer le hot-reload universel (backend `uvicorn --reload` + frontend Vite HMR)
> sur toutes les apps du parc.
> **Référence :** `HUBapp_TEMPLATE_base` v2.4.3+

---

## Checklist universelle (valable pour 6/7 apps React+Vite)

Chaque app doit recevoir ces **5 actions**. Ordre conseillé : 1→2→3→4→5.

### Action 1 — AJOUTER `docker-compose.dev.yml`

Copier depuis le template. Aucune personnalisation nécessaire.

```bash
cp HUBapp_TEMPLATE_base/docker-compose.dev.yml APPS/<app>/
```

- [ ] exemple-app
- [ ] HUBVault
- [ ] exemple-app
- [ ] exemple-apps
- [ ] exemple-app-ws
- [ ] exemple-app
- [ ] exemple-app-2 _(⚠️ voir section dédiée)_

### Action 2 — AJOUTER `Dockerfile.frontend.dev`

Copier depuis le template. Identique pour toutes les apps React+Vite.

```bash
cp HUBapp_TEMPLATE_base/Dockerfile.frontend.dev APPS/<app>/
```

- [ ] exemple-app
- [ ] HUBVault
- [ ] exemple-app
- [ ] exemple-apps
- [ ] exemple-app-ws
- [ ] exemple-app
- [ ] exemple-app-2 _(⚠️ voir section dédiée)_

### Action 3 — MODIFIER `Makefile`

3 sous-actions :

**a) Ajouter les variables `COMPOSE` / `COMPOSE_DEV`** après la garde `ifneq` :

```makefile
COMPOSE      = docker compose -f docker-compose.yml
COMPOSE_DEV  = docker compose -f docker-compose.yml -f docker-compose.dev.yml
```

**b) Remplacer le contenu de la cible `dev` :**

```makefile
dev: sync-env ## Lancer en mode développement (hot-reload backend + HMR frontend)
	$(COMPOSE_DEV) up --build -d
	$(COMPOSE_DEV) logs -f
```

**c) Ajouter les cibles `up-dev` / `down-dev` :**

```makefile
up-dev: sync-env ## Démarrer le mode développement en arrière-plan
	$(COMPOSE_DEV) up --build -d

down-dev: ## Arrêter les services lancés en mode dev
	$(COMPOSE_DEV) down
```

**d) Remplacer `docker compose` par `$(COMPOSE)`** dans toutes les autres cibles (`build`, `up`, `down`, `restart`, `logs`, `clean`, `clean-all`, `db-shell`, `test-docker*`).

**e) Ajouter `up-dev` et `down-dev` à `.PHONY`.**

- [ ] exemple-app
- [ ] HUBVault
- [ ] exemple-app
- [ ] exemple-apps
- [ ] exemple-app-ws
- [ ] exemple-app
- [ ] exemple-app-2 _(⚠️ voir section dédiée)_

### Action 4 — MODIFIER `backend/entrypoint.sh`

**Remplacer** la dernière ligne :

```diff
- exec uvicorn main:app --host 0.0.0.0 --port 8000
+ exec uvicorn main:app --host 0.0.0.0 --port 8000 "$@"
```

- [ ] exemple-app
- [ ] HUBVault
- [ ] exemple-app
- [ ] exemple-apps
- [ ] exemple-app-ws
- [ ] exemple-app
- [ ] exemple-app-2 _(⚠️ voir section dédiée)_

### Action 5 — MODIFIER `frontend/vite.config.js`

Ajouter la config proxy. **Attention :** 5/6 apps utilisent `@tailwindcss/vite` — il faut merger.

**Version SANS TailwindCSS** (exemple-apps — identique au template) :
```js
import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [react()],
    server: {
      host: '0.0.0.0',
      port: 3000,
      proxy: {
        '/api': { target: 'http://api:8000', changeOrigin: true },
        '/hub': {
          target: `http://${env.HUB_HOST || 'localhost'}:${env.HUB_API_PORT || '8000'}`,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/hub/, ''),
        },
      },
    },
    build: { outDir: 'dist', sourcemap: false },
  }
})
```

**Version AVEC TailwindCSS** (exemple-app, HUBVault, exemple-app, exemple-app-ws, exemple-app) :
```js
import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [react(), tailwindcss()],
    server: {
      host: '0.0.0.0',
      port: 3000,
      proxy: {
        '/api': { target: 'http://api:8000', changeOrigin: true },
        '/hub': {
          target: `http://${env.HUB_HOST || 'localhost'}:${env.HUB_API_PORT || '8000'}`,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/hub/, ''),
        },
      },
    },
    build: { outDir: 'dist', sourcemap: false },
  }
})
```

- [ ] exemple-app _(TailwindCSS — version avec)_
- [ ] HUBVault _(TailwindCSS — version avec)_
- [ ] exemple-app _(TailwindCSS — version avec)_
- [ ] exemple-apps _(SANS TailwindCSS — version sans)_
- [ ] exemple-app-ws _(TailwindCSS — version avec)_
- [ ] exemple-app _(TailwindCSS — version avec)_
- [ ] exemple-app-2 _(⚠️ voir section dédiée)_

---

## Cas particulier : exemple-app-2 _(app divergente)_

Structure complètement hors-template. Nécessite une approche manuelle.

| Problème | Action |
|----------|--------|
| Services nommés `backend`/`frontend` (pas `api`) | Laisser en l'état — le proxy Vite devra pointer vers `http://backend:8075` au lieu de `http://api:8000` |
| Backend port 8075 (pas 8000) | Conserver le port custom dans le proxy |
| `Dockerfile` racine + `frontend/Dockerfile` (pas `Dockerfile.backend`/`Dockerfile.frontend`) | Créer un `docker-compose.dev.yml` adapté avec les bons chemins |
| `entrypoint.sh` à la racine | Modifier le chemin dans le dev overlay |
| React 19 + Vite 7 (vs 18/5 du template) | Ajouter proxy + `"$@"` mais garder la stack existante |
| PrimeReact, Chart.js, router-dom | À conserver — ne pas modifier |
| Proxy partiel existant (localhost:8075) | Changer `localhost:8075` → `http://backend:8075`, ajouter `/hub` |
| `docker-compose.test.yml` spécifique | À conserver tel quel |
| HTTPS dev actif dans Vite | Désactiver en dev (le proxy Docker gère) |

**Checklist dédiée exemple-app-2 :**

- [ ] **A1** — Créer `docker-compose.dev.yml` adapté (services `backend`/`frontend`, port 8075)
- [ ] **A2** — Créer `Dockerfile.frontend.dev` (ou adapter le `frontend/Dockerfile`)
- [ ] **A3** — Modifier `entrypoint.sh` → `exec uvicorn app.main:app ... "$@"`
- [ ] **A4** — Modifier `frontend/vite.config.js` → proxy `http://backend:8075` + `/hub`
- [ ] **A5** — Modifier `Makefile` → ajouter `COMPOSE_DEV`, `dev`, `up-dev`, `down-dev`

---

## Tableau d'avancement

| App | A1 dev.yml | A2 FE.dev | A3 Makefile | A4 entrypoint | A5 proxy | Fait le |
|-----|-----------|-----------|-------------|---------------|----------|---------|
| **exemple-app** | | | | | | |
| **HUBVault** | | | | | | |
| **exemple-app** | | | | | | |
| **exemple-apps** | | | | | | |
| **exemple-app-ws** | | | | | | |
| **exemple-app** | | | | | | |
| **exemple-app-2** | | | | | | |

---

## Vérification post-migration (par app)

```bash
# 1. Lancer en mode dev
cd APPS/<app> && make dev

# 2. Vérifier que ça boot sans erreur
make logs

# 3. Modifier un fichier backend → doit reloader
echo "# test" >> backend/main.py && sleep 2
# Le log doit afficher "Reloading..."

# 4. Modifier un fichier frontend → HMR dans le navigateur
# Ouvrir http://<IP>:<FRONTEND_PORT>
# Éditer frontend/src/App.jsx → changement instantané sans F5

# 5. Nettoyer
make down
```

---

## Ordre de migration recommandé

1. **exemple-apps** _(la plus proche du template, la plus simple)_
2. **exemple-app** _(workshop, pas de risque)_
3. **exemple-app-ws** _(workshop, pas de risque)_
4. **exemple-app** _(prod, mais simple)_
5. **exemple-app** _(prod, simple)_
6. **HUBVault** _(prod, simple)_
7. **exemple-app-2** _(refonte majeure, à planifier séparément)_
