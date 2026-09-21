---
name: hub-oidc-manager
description: >
  Utiliser pour gérer le bridge OIDC du HUB : clients OIDC (CRUD), SSO d'apps externes
  (Vikunja, Nextcloud, Grafana…), test/debug du flow OIDC (authorize, token, userinfo,
  redirect_uri, JWKS), back-channel logout, refresh tokens. Triggers : OIDC, SSO, openid,
  oauth, id_token, discovery OIDC, auto-register/JIT, Vikunja/Grafana/Nextcloud auth.
---

# Hub OIDC Manager

Gérer le bridge OIDC du HUB POULIDOR : un fournisseur d'identité OIDC 1.0 implémenté
directement dans `hub-api` (from-scratch, `pyjwt[crypto]`, zéro dépendance externe).
Le HUB émet des `id_token` RS256 signés avec sa clé JWT existante, expose les endpoints
standard (discovery, authorize, token, userinfo), et gère le cycle de vie des clients OIDC.

> **Règle d'or** : le `client_secret` est affiché **une seule fois** à la création.
> Le stocker immédiatement (config app + coffre Fernet). Jamais en clair dans git.

---

## When to Use

| Situation | Action |
|---|---|
| « Activer OIDC » / « Le bridge OIDC ne marche pas » | [→] §1 Vérifier `OIDC_ISSUER` dans `.env` |
| « Créer un client OIDC pour X » / « Connecter Vikunja/Grafana/Nextcloud au HUB » | [→] §2 Créer un client + §3 Configurer l'app |
| « Tester le flow OIDC » / « Valider que le SSO marche » | [→] §4 Test end-to-end (curl) |
| « redirect_uri non autorisé » / « Could not authenticate against third party » | [→] §5 Debug — redirect_uri mismatch |
| « client_secret invalide » | [→] §5 Debug — secret non substitué / incorrect |
| « Déconnecter un user de toutes les apps OIDC » | [→] §6 Back-channel logout |
| « L'user n'est pas connecté automatiquement » | [→] §5 Debug — cookie `hub_oidc_session` |
| « Ajouter une icône OIDC dans le dashboard HUB » | [→] §3 Déclarer l'app HUB |

## Ne PAS utiliser pour

- **SSO JWT maison** des apps template (Vaultwarden, exemple-app…) → ce sont des apps
  avec `hub_client.py` M2M, pas de l'OIDC. Voir `INTEGRATION.md`.
- **Auto-login iframe Vaultwarden** → Vaultwarden ne supporte PAS OIDC nativement.
  Son auto-register est un hack frontend (provisioning + iframe), pas géré par ce skill.
- **Keycloak / Authentik / Authelia** → le HUB POULIDOR est son propre IdP. Aucun
  fournisseur externe dans le parc.

---

## Prérequis (NON-négociables)

| # | Prérequis | Vérification |
|---|---|---|
| P1 | HUB_base sur branche ≥ `feat/oidc-bridge-v3.13` (v3.13.0+) | `cat HUB_base/VERSION` → `3.13.x` |
| P2 | `hub-api` démarré et sain | `docker ps --filter name=hub-api` → `healthy` |
| P3 | `OIDC_ISSUER` défini dans `HUB_base/.env` (non vide) | `grep OIDC_ISSUER HUB_base/.env` |
| P4 | Document de discovery OIDC accessible | `curl http://$HUB_HOST:$HUB_API_PORT/.well-known/openid-configuration` |
| P5 | Token admin HUB disponible pour les opérations CRUD | `POST /api/auth/token` avec `grant_type=password` |

> Violer un prérequis = tout arrêter. L'OIDC ne peut pas fonctionner sans `OIDC_ISSUER`.

---

## Architecture — Le HUB est l'IdP

```
┌──────────────────────────────────────────────────────────┐
│  HUB POULIDOR (hub-api, FastAPI)                         │
│                                                          │
│  SSO JWT maison (inchangé)    │   Bridge OIDC (v3.13+)   │
│  Apps template (M2M)          │   Apps externes (OIDC)    │
│                               │                          │
│  • JWT en localStorage        │   • /.well-known/...      │
│  • hub_token Bearer           │   • /oidc/authorize       │
│  • Pas de cookie navigateur   │   • /api/oidc/token       │
│                               │   • /api/oidc/userinfo    │
│                               │   • /api/oidc/launch/{id} │
│                               │   • /api/oidc/clients CRUD│
│                               │   • Cookie hub_oidc_session│
│                               │   • JWKS RS256 (clé existante)│
│                                                          │
│  Postgres : oauth_clients, oauth_authorization_codes,    │
│             oauth_refresh_tokens                         │
└──────────────────────────────────────────────────────────┘
```

**Deux mécanismes SSO coexistent** sans interférence :
1. **SSO JWT maison** — apps template (`hub_client.py`, M2M, `grant_type=client_credentials`)
2. **Bridge OIDC** — apps externes (Authorization Code Flow + PKCE, `hub_oidc_session` cookie)

---

## §1 — Activer / vérifier le bridge OIDC

### Activation (1 ligne dans `.env`)

```bash
# HUB_base/.env — seule ligne obligatoire
# (les 7 autres vars OIDC ont des defaults corrects dans docker-compose.yml)
OIDC_ISSUER=http://<HUB_HOST>:<HUB_API_PORT>
```

> En prod HTTPS : `OIDC_ISSUER=https://hub.tondomaine.tld`

### Validation

```bash
# 1. Discovery document
curl -s http://$HUB_HOST:$HUB_API_PORT/.well-known/openid-configuration | python3 -m json.tool
# Expected : issuer, authorization_endpoint, token_endpoint, userinfo_endpoint, jwks_uri

# 2. Redémarrer hub-api si .env modifié
cd HUB_base && docker compose restart hub-api
```

### Variables OIDC (toutes ont des defaults docker-compose)

| Variable | Default | Rôle |
|---|---|---|
| `OIDC_ENABLED` | `true` | Kill-switch global |
| `OIDC_ISSUER` | `""` ⚠️ | **Obligatoire** — URL publique du HUB |
| `OIDC_EMAIL_TEMPLATE` | `{username}@hub.internal` | Claim email synthétique |
| `OIDC_CODE_TTL_SECONDS` | `30` | TTL des codes OIDC |
| `OIDC_ID_TOKEN_TTL_MINUTES` | `10` | TTL des id_tokens |
| `OIDC_ACCESS_TOKEN_TTL_MINUTES` | `15` | TTL des access_tokens |
| `OIDC_REFRESH_TOKEN_DAYS` | `30` | TTL des refresh_tokens |
| `OIDC_BACKCHANNEL_LOGOUT_ENABLED` | `true` | Back-channel logout OIDC |

---

## §2 — Créer un client OIDC

### Obtenir un token admin

```bash
HUB_TOKEN=$(curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=admin&password=$HUB_ADMIN_PWD" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))")
```

### Créer le client

```bash
curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients \
  -H "Authorization: Bearer $HUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Nom de l'\''app",
    "redirect_uris": ["http://<app_url>/auth/openid/<provider_key>"],
    "scopes": ["openid", "profile", "email"],
    "auto_approve": true
  }' | python3 -m json.tool | tee /tmp/oidc_client.json
```

**Récupérer immédiatement** : `client_id` (auto-généré, format `oc_<hex32>`) et
`client_secret` (affiché **une seule fois**).

> ⚠️ Le `client_id` est **auto-généré** par le HUB (`oc_<hex32>`), pas le `name` que tu passes.
> C'est ce `client_id` qu'il faut mettre dans la config de l'app externe.

### Lister / modifier / supprimer

```bash
# Lister
curl -s http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients \
  -H "Authorization: Bearer $HUB_TOKEN" | python3 -m json.tool

# Modifier (redirect_uris, app_id, etc.)
curl -s -X PUT http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients/<id> \
  -H "Authorization: Bearer $HUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"redirect_uris": ["http://nouvelle-url/callback"]}'

# Régénérer le secret (l'ancien est immédiatement invalide)
curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients/<id>/regenerate-secret \
  -H "Authorization: Bearer $HUB_TOKEN"

# Activer/désactiver (kill-switch)
curl -s -X PATCH http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients/<id>/toggle-active \
  -H "Authorization: Bearer $HUB_TOKEN"

# Supprimer
curl -s -X DELETE http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients/<id> \
  -H "Authorization: Bearer $HUB_TOKEN"
```

---

## §3 — Configurer une app externe pour OIDC

### Workflow type (5 étapes)

1. **Créer le client OIDC** (§2) → récupérer `client_id` + `client_secret`
2. **Configurer l'app externe** — pointer vers le HUB :
   - `authurl` / `issuer` = `http://$HUB_HOST:$HUB_API_PORT` (ou discovery URL)
   - `clientid` = le `oc_<hex32>` généré
   - `clientsecret` = le secret (voir §5 Common Mistakes pour la substitution `${VAR}`)
   - `scope` = `openid profile email`
3. **Déclarer l'app HUB** — pour qu'elle apparaisse dans le dashboard :
   ```bash
   curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/apps/ \
     -H "Authorization: Bearer $HUB_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "Nom App",
       "slug": "slug-app",
       "api_port": <port_app>,
       "icon": "bi-list-task",
       "requires_auth": true
     }'
   ```
4. **Configurer `frontend_url` et `callback_url`** (PATCH) :
   ```bash
   curl -s -X PATCH http://$HUB_HOST:$HUB_API_PORT/api/apps/<app_id> \
     -H "Authorization: Bearer $HUB_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{
       \"frontend_url\": \"http://$APP_URL\",
       \"callback_url\": \"http://$HUB_HOST:$HUB_API_PORT/api/oidc/launch/$CLIENT_ID\"
     }"
   ```
5. **Lier le client OIDC à l'app** (FK optionnelle) :
   ```bash
   curl -s -X PUT http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients/<oidc_client_id> \
     -H "Authorization: Bearer $HUB_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"app_id\": $APP_ID}"
   ```
6. **Attribuer le rôle** à l'utilisateur :
   ```bash
   curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/users/<user_id>/apps \
     -H "Authorization: Bearer $HUB_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"assignments\": [{\"app_id\": $APP_ID, \"role\": \"admin\"}]}"
   ```

### Claims OIDC fournis par le HUB

| Claim | Scope | Source HUB |
|---|---|---|
| `sub` | openid | `User.username` |
| `preferred_username` | profile | `User.username` |
| `name` | profile | `User.username` |
| `email` | email | `{username}@hub.internal` (synthétique) |
| `email_verified` | email | `true` |
| `iss` | — | `OIDC_ISSUER` |
| `aud` | — | `client_id` du client OIDC |
| `nonce` | — | Rejoué depuis authorize |

---

## §4 — Tester le flow OIDC end-to-end (curl)

> **Toujours tester en curl avant le navigateur.** Ça isole le bridge HUB des
> particularités de l'app externe (substitution de variables, format du callback, etc.).

```bash
HUB_HOST=192.0.2.10
HUB_API_PORT=8000
HUB_ADMIN_PWD="Mot2passe"
CLIENT_ID="oc_xxx"        # remplacer
CLIENT_SECRET="xxx"       # remplacer
REDIRECT_URI="http://app-url/auth/openid/provider"  # exactement ce que l'app envoie

# 1. Login → JWT + cookie hub_oidc_session
COOKIE_JAR=/tmp/oidc_test.txt
curl -s -c "$COOKIE_JAR" -X POST http://$HUB_HOST:$HUB_API_PORT/api/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=admin&password=$HUB_ADMIN_PWD" > /dev/null

# 2. Authorize → code
CODE=$(curl -s -b "$COOKIE_JAR" -D - -o /dev/null \
  "http://$HUB_HOST:$HUB_API_PORT/oidc/authorize?\
client_id=$CLIENT_ID&\
redirect_uri=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$REDIRECT_URI',safe=''))")&\
response_type=code&scope=openid+profile+email&state=test&nonce=test" \
  2>&1 | grep -oP 'code=\K[^&]+')
echo "Code: ${CODE:0:20}..."

# 3. Token exchange
curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/oidc/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=$CODE&\
redirect_uri=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$REDIRECT_URI',safe=''))")&\
client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" | python3 -m json.tool

# Expected : access_token, id_token, refresh_token, token_type=Bearer, expires_in=900
```

### Vérifier les claims de l'id_token

```bash
# Décoder le payload du id_token (sans vérif de signature — juste inspection)
echo "$ID_TOKEN" | python3 -c "
import sys, json, base64
payload = sys.stdin.read().strip().split('.')[1]
payload += '=' * (4 - len(payload) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
"
```

### Vérifier userinfo

```bash
curl -s http://$HUB_HOST:$HUB_API_PORT/api/oidc/userinfo \
  -H "Authorization: Bearer $ACCESS_TOKEN" | python3 -m json.tool
```

---

## §5 — Debug : erreurs courantes

### Erreur : `redirect_uri non autorisé pour ce client`

**Cause** : le `redirect_uri` envoyé par l'app externe ne correspond pas exactement
à celui enregistré dans `oauth_clients.redirect_uris`.

**Debug** :
1. Capturer l'URL exacte que l'app envoie (logs de l'app ou URL dans le navigateur)
2. Comparer avec ce qui est enregistré :
   ```bash
   curl -s http://$HUB_HOST:$HUB_API_PORT/api/oidc/clients \
     -H "Authorization: Bearer $HUB_TOKEN" | python3 -m json.tool
   ```
3. **Égalité stricte** — pas de prefix matching, pas de trailing slash diffèrent.

**Exemple concret (Vikunja)** : Vikunja envoie `http://host:port/auth/openid/hub`
(sans `/callback`), pas `http://host:port/auth/openid/hub/callback`.

### Erreur : `client_secret invalide`

**Causes possibles** :

| Cause | Diagnostic | Fix |
|---|---|---|
| `${VAR}` non substitué dans config app | `docker inspect <ctn> --format '{{.Config.Env}}'` → la var est-elle présente ? | Hardcoder le secret dans le config file, OU passer la var via `environment:` dans docker-compose |
| App envoie le littéral `${CLIENT_SECRET}` | Logs de l'app : `client_secret invalide` | Vérifier que l'app supporte la substitution `${VAR}` dans son config file |
| Secret régénéré mais app pas redémarrée | Le vieux secret ne marche plus | Redémarrer l'app après mise à jour du secret |
| Secret copié avec erreur (tronqué, escape) | Comparer caractère par caractère | Re-copier depuis la sortie JSON de création/régénération |

**Test rapide** : si le curl test (§4) marche mais pas l'app → le problème est
la substitution de variable côté app, pas le HUB.

### Erreur : L'user n'est pas connecté automatiquement (boucle de redirect)

**Cause** : le cookie `hub_oidc_session` n'est pas envoyé à `/oidc/authorize`.

| Scénario | Cause | Fix |
|---|---|---|
| Dashboard en HTTPS, OIDC_ISSUER en HTTP | Cookie `Secure=true` → non envoyé en HTTP | Homogénéiser : `OIDC_ISSUER` en HTTPS si dashboard HTTPS |
| User n'est jamais passé par `/api/auth/token` | Cookie jamais posé | Le user doit se connecter au dashboard HUB d'abord |
| Domaine différent entre dashboard et API | Cookie non partagé cross-domain | Utiliser le même host pour le dashboard et l'OIDC |

**Vérifier la présence du cookie** :
```bash
curl -s -D - -X POST http://$HUB_HOST:$HUB_API_PORT/api/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=admin&password=$PWD" -o /dev/null | grep -i set-cookie
# Expected : set-cookie: hub_oidc_session=eyJ...; HttpOnly; SameSite=lax
```

### Erreur : `code déjà utilisé (one-shot)` ou `code expiré`

**Cause** : les codes OIDC sont one-shot (TTL 30s). Si le token exchange échoue
et l'app réessaie avec le même code, il est déjà marqué `used_at`.

**Fix** : relancer le flow depuis le dashboard (nouveau clic → nouveau code).

---

## §6 — Back-channel logout

Déconnecter immédiatement un user d'une app OIDC spécifique :

```bash
curl -s -X POST http://$HUB_HOST:$HUB_API_PORT/api/oidc/backchannel-logout/<client_id> \
  -H "Authorization: Bearer $HUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sub": "<username>"}' | python3 -m json.tool
```

**Effet** :
- Révoque tous les refresh_tokens OIDC de cet user pour ce client (DC passif : l'user
  ne peut plus renouveler son access_token, expire en ≤15 min)
- Envoie un `logout_token` JWT signé au `backchannel_logout_uri` du client (DC actif
  si l'app le supporte)

> L'app externe doit supporter OIDC Back-Channel Logout 1.0 pour le DC actif.
> Le DC passif (refresh token révoqué) fonctionne dans tous les cas.

---

## Quick Reference — Endpoints OIDC

| Endpoint | Méthode | Auth | Rôle |
|---|---|---|---|
| `/.well-known/openid-configuration` | GET | Public | Discovery document |
| `/oidc/authorize` | GET | Cookie `hub_oidc_session` | Authorization endpoint |
| `/api/oidc/token` | POST | client_secret (basic ou post) | Token endpoint (code→tokens, refresh→tokens) |
| `/api/oidc/userinfo` | GET/POST | Bearer access_token | UserInfo endpoint |
| `/api/oidc/launch/{client_id}` | GET | access_token query | **Spécifique HUB** : shortcut JWT→code OIDC |
| `/api/auth/.well-known/jwks.json` | GET | Public | JWKS (clés publiques RS256) |
| `/api/oidc/clients` | GET/POST | Admin JWT | CRUD clients OIDC |
| `/api/oidc/clients/{id}` | PUT/DELETE | Admin JWT | Modifier / supprimer un client |
| `/api/oidc/clients/{id}/toggle-active` | PATCH | Admin JWT | Kill-switch client |
| `/api/oidc/clients/{id}/regenerate-secret` | POST | Admin JWT | Régénérer le secret |
| `/api/oidc/backchannel-logout/{client_id}` | POST | Admin JWT | DC user d'une app |

## Quick Reference — Tables DB

| Table | Rôle |
|---|---|
| `oauth_clients` | Clients OIDC (client_id, secret hashé bcrypt, redirect_uris, scopes) |
| `oauth_authorization_codes` | Codes one-shot (hash SHA256, TTL 30s, PKCE) |
| `oauth_refresh_tokens` | Refresh tokens (hash SHA256, révocables, rotation) |

> Pas de table pour access_tokens/id_tokens : ils sont **stateless** (signés JWKS RS256).

---

## Common Mistakes

| Erreur | Conséquence | Correction |
|---|---|---|
| Oublier `OIDC_ISSUER` dans `.env` | Discovery retourne `issuer: ""`, apps rejettent les tokens | Ajouter 1 ligne : `OIDC_ISSUER=http://host:port` |
| Mettre le `name` au lieu du `client_id` dans la config app | Auth échoue — `client_id` attendu est `oc_<hex32>` | Utiliser le `client_id` auto-généré, pas le `name` |
| `redirect_uri` avec/sans `/callback` | `redirect_uri non autorisé` | Capturer l'URL exacte envoyée par l'app (logs navigateur) |
| `${VAR}` dans config.yml de l'app externe | Secret littéral envoyé → `client_secret invalide` | Hardcoder le secret OU passer via `environment:` docker-compose |
| Env vars docker-compose surchargent config.yml | `auth.local.enabled: false` dans env écrase `enabled: true` du config.yml | Cohérence entre env vars et config file |
| Dashboard HTTPS + OIDC_ISSUER HTTP | Cookie `Secure` non envoyé en HTTP → boucle redirect | Homogénéiser HTTPS/HTTP entre dashboard et OIDC_ISSUER |
| Ne pas stocker le `client_secret` à la création | Secret perdu définitivement (hashé bcrypt en DB) | Régénérer via `/regenerate-secret` |
| Attribuer le rôle HUB après l'app | L'user voit l'icône mais `403` au lancement | Rôle via `POST /api/users/{id}/apps` avec `assignments` |

---

## Garde-fous

- **Jamais** pousser un `client_secret` en clair dans git → dossier `APPS/` est git-ignoré, utiliser le coffre Fernet (`hubctl`).
- **Toujours** tester le flow OIDC en curl (§4) avant le test navigateur.
- **Toujours** vérifier que le `redirect_uri` correspond exactement (égalité stricte).
- **Toujours** stocker le `client_secret` immédiatement après création (visible 1 fois).
- Si 3+ échecs de debug sur une intégration OIDC : vérifier que l'app externe supporte bien OIDC 1.0 (Authorization Code Flow + PKCE S256).

---

## Références

| Ressource | Chemin |
|---|---|
| Routes OIDC (HUB_base) | `HUB_base/hub/app/routes/oidc.py` |
| Helpers OIDC | `HUB_base/hub/app/oidc_helpers.py` |
| Modèles SQLAlchemy (OAuthClient, etc.) | `HUB_base/hub/app/models.py` (lignes 755+) |
| Config OIDC (Settings) | `HUB_base/hub/app/config.py` (lignes 211-219) |
| Migrations SQL (039-041) | `HUB_base/hub/migrations/039_add_oauth_clients.sql` etc. |
| Cookie session OIDC | `HUB_base/hub/app/routes/auth.py:316-325` |
| JWKS endpoint | `HUB_base/hub/app/routes/auth.py:768-813` |
| docker-compose OIDC vars | `HUB_base/docker-compose.yml:86-94` |
| Tests OIDC (47 tests) | `HUB_base/hub/tests/test_oidc_*.py` |
| Design Vikunja (référence intégration) | `docs/superpowers/specs/2026-07-22-vikunja-hub-integration-design.md` |
| Plan 2 déploiement Vikunja | `docs/superpowers/plans/2026-07-22-plan-2-vikunja-deploy.md` |
| App Vikunja déployée (référence) | `APPS/vikunja-service/` |
| Spécifications OIDC | https://openid.net/specs/openid-connect-core-1_0.html |
