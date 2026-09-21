# Cheatsheet dev — banc de test local (Hub complet sur ton poste)

> Audience : développeurs qui font tourner **un parc complet en local** (Hub +
> apps + ateliers) pour tester, casser et réinstaller. Les commandes du guide
> général restent la référence ([guide-parc-poulidor.md](guide-parc-poulidor.md)) ;
> cette feuille est l'outil de travail du banc. Liée aux scripts
> [`scripts/banc/`](../scripts/banc/) (`reset-hub.sh`, `reset-app.sh`).

---

## 1. Installer / réinstaller le banc

```bash
sudo ./install.sh                 # tout-en-un (Docker + Hub + firewall VPN)
./hubctl init                     # variante : Hub seul (prérequis déjà là)
./hubctl start                    # tout démarrer + health
./hubctl seed apps-banc.yaml      # repeupler le banc depuis un YAML
./hubctl seed export -o banc.yaml # …et l'exporter pour la prochaine fois
```

**VM vierge jetable ou persistante** (reproduire un bug en environnement
propre, tester une branche) : skill parc **`vm-lab`** — ne salis pas ton poste
pour un test à froid.

---

## 2. Itérer sur le code du Hub

```bash
make -C HUB_base up-dev           # dev : uvicorn --reload (hot-reload API)
make -C HUB_base logs             # suivre
make -C HUB_base down && make -C HUB_base up-prod   # retour en mode prod

# tester une branche du Hub :
git -C HUB_base fetch origin
git -C HUB_base checkout fix/ma-branche
make -C HUB_base build && make -C HUB_base up-prod
# …puis retour à main : git -C HUB_base checkout main && make -C HUB_base build && make -C HUB_base up-prod

# tests backend :
docker compose -f HUB_base/docker-compose.yml exec hub-api pytest tests/ -v
docker compose -f HUB_base/docker-compose.yml exec hub-api pytest tests/test_auth.py -v
# stack de test totalement isolée (conteneurs hub-test-*) :
docker compose -p pouly-test -f HUB_base/docker-compose.yml -f HUB_base/docker-compose.test.yml \
  --env-file HUB_base/.env.test up -d
```

⚠️ En `up-dev`, le code est **monté** (pas besoin de rebuild). En `up-prod`,
le code est baké : **toute modif = `make build`** avant `up-prod`.

---

## 3. Réinitialisations — les scripts `scripts/banc/`

### Reset du Hub

```bash
scripts/banc/reset-hub.sh --dry-run        # voir avant de casser
scripts/banc/reset-hub.sh                  # DB seule (secrets/certs/.env conservés)
scripts/banc/reset-hub.sh --full           # + secrets/ (JWT, SA) + certs/ (PKI)
scripts/banc/reset-hub.sh --env            # + .env + hubctl init --force (neuf)
```

**Version manuelle** (comprendre ce que le script fait) :

```bash
docker compose -f HUB_base/docker-compose.yml down
docker volume rm hub_base_postgres_data
make -C HUB_base up-prod
curl -sk http://localhost:8000/health      # attendre {"status":"healthy"}
```

### Reset d'une app

```bash
scripts/banc/reset-app.sh <slug> --dry-run # audit : dé-enregistrement, volumes…
scripts/banc/reset-app.sh <slug>           # dé-enregistre + down -v + credentials
cd APPS/<slug> && make up                  # re-boot : re-registration auto
scripts/banc/reset-app.sh <slug> --full    # + backup tar.gz + rm du dossier
```

### Ré-enregistrement manuel (sans reset)

Après un reset de la base Hub, une app peut se ré-enregistrer par-dessus son
ancienne fiche :

1. `FORCE_REPLACE_APP=true` dans `HUB_base/.env` (le recharger :
   `docker compose -f HUB_base/docker-compose.yml up -d hub-api` — ⚠️ pas
   `restart`)
2. Purger les credentials locaux : `rm APPS/<slug>/backend/storage/.hub_credentials`
3. Relancer l'app : `cd APPS/<slug> && make up`
4. Approuver la fiche pending (UI admin, ou curl ci-dessous), puis retirer
   `FORCE_REPLACE_APP`.

---

## 4. Comptes & tokens de test

```bash
# mot de passe admin : HUB_base/.env → ADMIN_PASSWORD
source .secrets                       # HUB_ADMIN_USERNAME / HUB_ADMIN_PASSWORD / HUB_BASE_URL

# login + JWT admin :
curl -s -X POST "$HUB_BASE_URL/api/auth/token" \
  -d "username=$HUB_ADMIN_USERNAME" -d "password=$HUB_ADMIN_PASSWORD" | python3 -m json.tool

TOKEN=$(curl -s -X POST "$HUB_BASE_URL/api/auth/token" \
  -d "username=$HUB_ADMIN_USERNAME" -d "password=$HUB_ADMIN_PASSWORD" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

# créer un utilisateur de test (rôles par app : modale droits ou /api/users/{id}/apps) :
curl -s -X POST "$HUB_BASE_URL/api/users/" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"test_dev","email":"test@banc.local","password":"MotDePasse123!"}'

# approver toutes les apps pending :
for slug in $(curl -s -H "Authorization: Bearer $TOKEN" "$HUB_BASE_URL/api/apps/pending" \
    | python3 -c 'import json,sys;print(" ".join(a["slug"] for a in json.load(sys.stdin)))'); do
  curl -s -X POST -H "Authorization: Bearer $TOKEN" "$HUB_BASE_URL/api/apps/$slug/approve"
done
```

Agents IA : `opencode` + `/hub-on` active le serveur MCP (`hub_*`, 63 outils) —
créer/approver/supprimer des apps, users, inspecter l'audit sans curl.

---

## 5. M2M & intégration

```bash
# catalogue des services partagés (discovery) :
curl -s -H "Authorization: Bearer $TOKEN" "$HUB_BASE_URL/api/apps/discover" | python3 -m json.tool | head -40

# clé publique du Hub (ce que valident les apps) :
curl -s "$HUB_BASE_URL/api/auth/.well-known/jwks.json" | python3 -m json.tool

# socle-check d'une app (7 contrôles, score /7) — aussi le bouton 🩺 de la vue Santé :
curl -s -X POST -H "Authorization: Bearer $TOKEN" "$HUB_BASE_URL/api/apps/<slug>/socle-check"

# self-service OIDC d'une app (elle crée son client elle-même, M2M) :
# → côté app : POST /api/oidc/self-client avec son token SA (cf. INTEGRATION.md)
```

Tests d'une **app** pendant le dev : `make test` (hôte, SQLite, rapide),
`make test-docker` (conteneur réel), `make verify-ui` (smoke UI Chromium),
`make lint-classes` (classes JSX vs HUBCSS).

---

## 6. Debug rapide

```bash
docker exec -it hub-db psql -U hubadmin -d hub_auth   # SQL direct dans le Hub
make -C APPS/<slug> db-shell                          # psql dans une app
docker logs hub-api --tail 100 -f                     # logs bruts
make -C APPS/<slug> logs-api                          # logs api d'une app
./hubctl debug <slug>                                 # agent IA local branché dessus
```

Requêtes utiles dans `psql` :

```sql
SELECT slug, status, is_active FROM applications ORDER BY slug;      -- fiches apps
SELECT id, username, role FROM users ORDER BY id;                    -- comptes
SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 5;       -- migrations
-- ateliers : SELECT * FROM workshop_operations ORDER BY id DESC LIMIT 5;
```

---

## 7. Pièges du banc

| Piège | Détail |
|---|---|
| `APP_ENV` | `production` (défaut du `.env.example`) = validation stricte au boot (ALLOWED_ORIGINS, secrets…). En banc, `development` est permissif — mais garde `production` si tu testes la config réelle. |
| `.env` vs `restart` | `docker compose restart` **ne recharge pas** le `.env` — utiliser `up -d <service>`. |
| Enregistrement bloqué | L'IP du banc doit être dans `APP_WHITELIST_NETWORKS` (CORS + CIDR). Un 403 à l'enregistrement = d'abord ça. |
| Snapshots forward-only | Un snapshot créé par un Hub ≥ 3.59.0 ne se restaure que sur un Hub ≥ 3.59.0. |
| Reset DB Hub | Casse les SA des apps → re-registration (§3). Le coffre (`vault status`) signalera des divergences — normal sur un banc. |
| Dossier ≠ slug | Quelques apps ont un dossier `APPS/` différent de leur slug (résolu côté Hub, cf. 3.52.1) — `reset-app.sh` travaille sur `APPS/<slug>`, vérifie le nom réel. |
| `update` vs banc | `./hubctl update` fait un `git pull` — sur un banc où tu bricoles des branches, préfère les commandes manuelles (§2). |
