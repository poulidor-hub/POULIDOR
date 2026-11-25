---
name: proxy-transparent
description: Utiliser pour concevoir/étendre un proxy transparent avec overlay frontend, cache backend partagé et token utilisateur (piggyback) pour une app web tierce. Document de conception ; l'application de référence (slug `exemple-app`, non publiée) en est l'implémentation type.
---

# proxy-transparent — Proxy transparent + overlay + cache collectif

## Overview

Le pattern **proxy-transparent** permet d'enrichir une application web tierce (SaaS, legacy, Angular…) sans modifier son code source. On interpose un proxy transparent qui :

1. Sert l'app tierce telle quelle au navigateur.
2. Intercepte ses appels API pour les mettre en cache côté backend.
3. Injecte un overlay JS dans les pages de l'app tierce.
4. L'overlay capte le token de l'utilisateur (Bearer piggyback) et appelle des endpoints backend dédiés.
5. Le backend exploite le cache partagé pour répondre instantanément.
6. Pour les données non en cache, le backend les récupère via **connexion SSL directe** (IP réelle + SNI forcé) — PAS via le DNS qui reboucle sur le proxy.

**Objectif :** réduire le trafic WAN, décharger le navigateur, et ajouter des fonctionnalités transverses (recherche, actions, monitoring) sans toucher à l'app cible.

## When to Use

- On veut enrichir une app web tierce sans modifier son code.
- L'app cible fait beaucoup d'appels API répétitifs et/ou lents.
- On veut mutualiser un cache entre utilisateurs et entre sessions.
- On veut ajouter une recherche "cross-données" ou des actions batch qui ne sont pas natives.
- On veut monitorer/intercepter le trafic API de l'app cible.
- **Cas de référence dans le parc :** l'application de référence (slug `exemple-app`, non publiée) intercepte l'app web tierce de référence (`exemple.org`).

## Ne PAS utiliser pour

- Remplacer une API proprement exposée par l'app cible.
- Ajouter une simple iframe ou widget sans interception de trafic.
- Intercepter une app dont les termes d'utilisation interdisent le reverse proxy.
- Mutualiser du cache contenant des données sensibles sans segmentation utilisateur.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Navigateur                               │
│  ┌──────────────┐        ┌─────────────────┐                    │
│  │ App tierce   │───────▶│ Overlay JS      │                    │
│  │ (Angular/...)│        │ (injecté par    │                    │
│  └──────────────┘        │  nginx)         │                    │
│         │                └─────────────────┘                    │
│         │                        │                              │
│   XHR /api/*        /api/overlay/* (Bearer piggyback)           │
│   (Bearer token)                  │                              │
│         ▼                        ▼                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               Nginx proxy transparent                     │   │
│  │   /api/*       ──▶ backend /app-tierce/api/* (cache proxy) │   │
│  │   /api/overlay ──▶ backend /api/overlay/* (overlay API)   │   │
│  │   /* (static)  ──▶ app tierce réelle (WAN)                │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Backend FastAPI                               │   │
│  │                                                            │   │
│  │  Proxy transparent (proxy_transparent.py)                 │   │
│  │    └─ cache L1/L2 → forward WAN → cache → réponse          │   │
│  │                                                            │   │
│  │  Routes overlay (overlay.py)                               │   │
│  │    └─ recherche cache, preload, fiche bénéficiaire         │   │
│  │                                                            │   │
│  │  _fetch_tierce_direct() ← connexion SSL directe            │   │
│  │    └─ asyncio.open_connection(REAL_IP, 443, SNI=hostname)  │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                                                       │
│         ▼                                                       │
│  Cache L1 (mémoire LRU) + Cache L2 (Redis)                      │
└─────────────────────────────────────────────────────────────────┘
```

## ⚠️ Piège fatal : le rebouclage DNS

**Le problème le plus important de ce pattern.** Dans le conteneur backend, `tierce_client.base_url` = `https://exemple.org`. Quand le backend appelle cette URL :

1. DNS résout `exemple.org` → `192.0.2.10` (le serveur local, via `/etc/hosts`)
2. La requête arrive sur **notre propre nginx** → proxy transparent
3. Le proxy transparent essaie de résoudre l'auth → échec (pas de session) → **401**

**Ça ne marche pas.** Et ça ne peut pas marcher : le backend se demande à lui-même.

### ❌ Ce qui ne marche PAS

```python
# NE PAS UTILISER — rebouclage DNS → 401 systématique
response = await tierce_client.forward_request(
    endpoint="/api/clients",
    user_token=token,
)
```

```python
# NE PAS UTILISER — SSL: WRONG_VERSION_NUMBER (SNI = IP au lieu du hostname)
async with httpx.AsyncClient(verify=False) as client:
    response = await client.get(f"https://{real_ip}/api/clients")
```

```bash
# NE PAS FAIRE — casse l'accès proxy pour tous les autres utilisateurs
echo "203.0.113.10 exemple.org" >> /etc/hosts
```

### ✅ Ce qui marche : connexion SSL directe avec SNI forcé

La solution : `asyncio.open_connection` qui connecte à l'IP réelle tout en
présentant le bon hostname SSL (SNI), sans toucher au DNS :

```python
# APPS/exemple-app/backend/routes/overlay.py — _fetch_tierce_direct()

import ssl, asyncio, json

async def _fetch_tierce_direct(endpoint: str, token: str, params=None):
    """Récupère des données depuis l'app tierce en connexion SSL directe."""

    # 1. Vérifier le cache d'abord (L1 + Redis)
    cached = await cache_manager.get(endpoint, params or {})
    if cached and not cached.is_expired:
        return json.loads(cached.get_data())

    # 2. Connexion SSL directe (IP réelle + SNI forcé)
    settings = get_settings()
    real_ip = settings.TIERCE_REAL_IP          # ex: 203.0.113.10
    hostname = settings.TIERCE_API_URL          # ex: https://exemple.org
    hostname = hostname.replace("https://", "").replace("http://", "").split("/")[0]

    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    # TCP → IP réelle, SSL SNI → hostname (pour que le serveur accepte)
    reader, writer = await asyncio.open_connection(
        real_ip, 443,
        ssl=ssl_ctx,
        server_hostname=hostname,   # ← SNI = exemple.org
    )

    # Requête HTTP manuelle
    path = endpoint
    if params:
        qs = "&".join(f"{k}={v}" for k, v in sorted(params.items()))
        path = f"{endpoint}?{qs}"

    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {hostname}\r\n"
        f"Authorization: Bearer {token}\r\n"
        f"Accept-Encoding: identity\r\n"
        f"Connection: close\r\n"
        f"\r\n"
    ).encode()
    writer.write(request)
    await writer.drain()

    raw = await reader.read()
    writer.close()

    # Parser la réponse HTTP
    sep = raw.find(b"\r\n\r\n")
    body = raw[sep + 4:]
    header_block = raw[:sep].decode("iso-8859-1")

    # Déchunker si nécessaire
    if "transfer-encoding: chunked" in header_block.lower():
        body = _dechunk(body)

    data = json.loads(body)

    # 3. Cacher pour les prochaines requêtes
    await cache_manager.set(
        endpoint=endpoint, params=params,
        data=body, status_code=200,
        ttl=get_ttl_for_category(classify_endpoint(endpoint)),
        user_id=None,
    )
    return data
```

> **Pourquoi pas httpx ?** httpx utilise le hostname de l'URL pour le SNI. En
> connectant à `https://203.0.113.10`, le SNI est l'IP → le serveur rejette
> (`SSL: WRONG_VERSION_NUMBER`). `asyncio.open_connection` permet de séparer
> IP de connexion et hostname SNI.

## Core Pattern

### 1. Proxy transparent

Le navigateur accède à l'app tierce via le **même nom de domaine**. Le DNS (ou
`/etc/hosts` côté serveur) pointe vers notre proxy.

- Les assets statiques passent directement à l'app tierce (catch-all nginx).
- Les appels API (`/api/*`) sont redirigés vers le backend via nginx.
- Le backend met en cache, forward vers l'app tierce réelle si miss.

### 2. Piggyback du token

L'overlay JS est injecté dans chaque page HTML de l'app tierce (via `sub_filter`
nginx). Il intercepte les headers `Authorization: Bearer ...` des requêtes
XHR/fetch natives de l'app tierce :

```javascript
// APPS/exemple-app/frontend/public/overlay/overlay.js
var _capturedBearerToken = null;

// Hook XHR (Angular utilise XMLHttpRequest)
var _origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
  if (name === 'Authorization' && typeof value === 'string'
      && value.startsWith('Bearer ')) {
    _capturedBearerToken = value;
  }
  return _origSetHeader.apply(this, arguments);
};

// Hook fetch (au cas où)
var _origFetch = window.fetch;
window.fetch = function(input, init) {
  try {
    var h = init && init.headers;
    if (h) {
      var auth = (h instanceof Headers) ? h.get('Authorization')
        : (typeof h === 'object' ? h['Authorization'] || h['authorization'] : null);
      if (typeof auth === 'string' && auth.startsWith('Bearer '))
        _capturedBearerToken = auth;
    }
  } catch(e) {}
  return _origFetch.apply(this, arguments);
};

// Helper pour envoyer le token sur les appels overlay
function _authHeaders() {
  return _capturedBearerToken ? { Authorization: _capturedBearerToken } : {};
}
```

L'overlay réutilise ensuite ce Bearer dans ses appels à `/api/overlay/*` :

```javascript
fetch('/api/overlay/preload', {
  method: 'POST',
  credentials: 'include',
  headers: _authHeaders(),  // ← Bearer piggybacké
});
```

### 3. Cache collectif L1/L2

Les réponses GET de l'app tierce sont stockées dans un cache à deux niveaux :

| Niveau | Techno | Latence | Persistance |
|---|---|---|---|
| L1 | Mémoire (LRU OrderedDict) | < 0.1 ms | Process-only |
| L2 | Redis | < 1 ms | Partagé entre workers/restarts |

- Segmentation par utilisateur (`user_id` dans la clé de cache).
- TTL par catégorie d'endpoint (référentiel 1h, liste 5min, planning 2min, dossier 1-5min).
- Revalidation stale-while-revalidate en arrière-plan.
- Compression gzip des entrées > 10 Ko.

#### Scanner le cache par endpoint

```python
# Méthode CacheManager.get_entries_by_endpoint()
# Retourne toutes les entrées (L1 + Redis SCAN) pour un endpoint exact.
entries = await cache_manager.get_entries_by_endpoint("/api/clients")
```

### 4. Recherche backend dans le cache (multi-sources)

Au lieu d'appeler l'app tierce pour chaque recherche, le backend scanne les
entrées déjà en cache et filtre côté serveur. On peut fusionner plusieurs
sources (ex: `/api/clients` pour les noms + `/api/clients/addresses` pour les
villes/CP) :

```python
# APPS/exemple-app/backend/routes/overlay.py — overlay_search()

@router.get("/overlay/search")
async def overlay_search(request: Request, q: str = Query(..., min_length=2), ...):
    # 1. Index clientId → nom depuis /api/clients
    client_entries = await cache_manager.get_entries_by_endpoint("/api/clients")
    name_index = {}
    for entry in client_entries:
        data = json.loads(entry.get_data())
        for item in data.get("data", []):
            name_index[item["id"]] = {
                "nom": item.get("nom"),
                "prenom": item.get("prenom"),
                "telephone": item.get("phone"),
            }

    # 2. Scanner /api/clients/addresses (ville, CP, adresse)
    addr_entries = await cache_manager.get_entries_by_endpoint("/api/clients/addresses")
    for entry in addr_entries:
        data = json.loads(entry.get_data())
        for item in data.get("data", []):
            cid = item.get("clientId")
            search_text = f"{item.get('city','')} {item.get('zipcode','')} {item.get('formattedAddress','')}".lower()
            if q.lower() in search_text:
                names = name_index.get(cid, {})
                results.append({
                    "id": cid,
                    "nom": names.get("nom", ""),
                    "ville": item.get("city"),
                    "codePostal": item.get("zipcode"),
                })

    # Zéro appel WAN — tout vient du cache
```

### 5. Préchargement manuel (preload)

Pour remplir le cache avec l'ensemble des données d'un type (ex: tous les
bénéficiaires de toutes les agences), l'utilisateur clique un bouton dans
l'overlay. Le backend utilise `_fetch_tierce_direct` pour récupérer les données
depuis l'app tierce (IP réelle) et les cacher :

```python
# APPS/exemple-app/backend/routes/overlay.py — overlay_preload_beneficiaries()

@router.post("/overlay/preload")
async def overlay_preload_beneficiaries(request: Request, ...):
    # Bearer token envoyé par l'overlay
    token = request.headers["Authorization"][7:]

    # Skip les agences déjà en cache
    missing = [aid for aid in agency_ids
               if not await cache_manager.get("/api/clients", {"agenciesIds": str(aid)})]

    if not missing:
        return {"status": "already_cached"}

    # Fetch parallèle via SSL direct (voir section _fetch_tierce_direct)
    async def _fetch_one(aid):
        # asyncio.open_connection(REAL_IP, 443, server_hostname=HOSTNAME)
        # → GET /api/clients?agenciesIds=X
        # → cache_manager.set(...)
        ...

    await asyncio.gather(*[_fetch_one(aid) for aid in missing])
```

**Important :** ne pas recharger les données déjà en cache. Vérifier chaque
clé avant de fetch.

### 6. Fiche détaillée bénéficiaire

Quand l'utilisateur clique sur un résultat de recherche, la fenêtre de détail
récupère les sous-ressources (`/api/clients/{id}`, `addresses`, `pecs`,
`contacts`, `interventions`...) via `_fetch_tierce_direct` :

```python
# Chaque sous-resource est fetchée en parallèle via _fetch_tierce_direct
for key, ep in _CLIENT_SUB_ENDPOINTS.items():
    results[key] = await _fetch_tierce_direct(ep.format(client_id=cid), token)
```

L'overlay affiche d'abord les données du cache (immédiat), puis enrichit avec
les données fraîches du backend (arrière-plan).

## Référence implémentation — l'application de référence

> ℹ️ **Référence** : les chemins ci-dessous sont ceux de l'implémentation de
> référence (`APPS/exemple-app/`, non publiée) — les chemins qui suivent sont à
> adapter à votre propre implémentation.

| Rôle | Fichier (chemin historique) |
|---|---|
| Config nginx transparent | `APPS/exemple-app/nginx-app-tierce.conf` |
| Proxy transparent backend | `APPS/exemple-app/backend/routes/proxy_transparent.py` |
| Routes overlay | `APPS/exemple-app/backend/routes/overlay.py` |
| Cache manager | `APPS/exemple-app/backend/cache.py` |
| Overlay JS injecté | `APPS/exemple-app/frontend/public/overlay/overlay.js` |
| SNI routing côté HUB | `HUB_base/frontend/nginx-ssl.conf` (bloc `exemple.org`) |

### Flux d'une requête API (du navigateur)

1. Navigateur → `https://exemple.org/api/clients`
2. `HUB_base/frontend/nginx-ssl.conf` route SNI vers `exemple-app-frontend:8443`
3. `nginx-app-tierce.conf` redirige `/api/*` vers `backend_pool` avec réécriture :
   `/api/` → `/app-tierce/api/` (le routeur backend a `prefix="/app-tierce"`)
4. `proxy_transparent.py` :
   - Extrait le Bearer du header `Authorization`
   - Vérifie le cache L1/L2
   - Si HIT → réponse immédiate
   - Si MISS → forward vers l'app tierce réelle (IP upstream), met en cache, retourne
5. Réponse au navigateur avec headers `X-Cache`, `X-Cache-TTL`, etc.

### Flux d'une requête preload (du backend)

1. Overlay → `POST /api/overlay/preload` (Bearer piggybacké)
2. Backend lit les agences depuis le cache Redis (`/api/agencies`)
3. Backend skip les agences déjà en cache
4. Pour chaque agence manquante :
   - `asyncio.open_connection(REAL_IP, 443, ssl=ctx, server_hostname=HOSTNAME)`
   - `GET /api/clients?agenciesIds=X` avec Bearer token
   - `cache_manager.set(endpoint, params, data)`
5. Retour : `{beneficiaries_cached: 15000, agencies_fetched: 9}`

### Headers de diagnostic

| Header | Valeurs | Signification |
|---|---|---|
| `X-Cache` | `HIT`, `MISS`, `BYPASS`, `STALE`, `REVALIDATED` | Origine de la réponse |
| `X-Cache-TTL` | secondes | Temps restant en cache |
| `X-Cache-Category` | `referentiel`, `liste`, `planning`, `dossier` | Catégorie de l'endpoint |

## Cookbook

### Ajouter un endpoint overlay

1. Ajouter la route dans `backend/routes/overlay.py` sous `router = APIRouter(prefix="/api")`.
2. Authentifier via `_get_username_from_app_tierce_session(request, db)` (cookie `app_tierce_session`).
3. Récupérer le Bearer depuis `request.headers["Authorization"]`.
4. Utiliser le cache ou `_fetch_tierce_direct` selon le besoin.
5. Mettre à jour `overlay.js` pour consommer le nouvel endpoint.

### Ajouter une recherche backend dans le cache

1. Identifier les endpoints source déjà cachés (ex: `/api/clients`, `/api/clients/addresses`).
2. Utiliser `cache_manager.get_entries_by_endpoint(endpoint)` pour récupérer les entrées.
3. Construire un index croisé (ex: `clientId → nom`) si on fusionne plusieurs sources.
4. Fusionner, dédupliquer par `id`, filtrer côté backend.
5. Retourner un format compact (15-50 résultats max).
6. Prévoir le cas "cache vide" avec un message explicite pour l'utilisateur.

### Ajouter un preload (pré-cache manuel)

1. Créer un endpoint `POST /api/overlay/preload`.
2. Récupérer le Bearer depuis le header `Authorization`.
3. Vérifier quelles données sont **déjà en cache** (skip si présent + non expiré).
4. Pour les données manquantes : utiliser `_fetch_tierce_direct` (SSL direct, pas de DNS).
5. Cacher chaque résultat avec `cache_manager.set`.
6. Retourner un résumé `{fetched, already_cached, errors}`.
7. Ajouter un bouton dans l'overlay pour déclencher manuellement.

### Récupérer des données depuis l'app tierce (depuis le backend)

**TOUJOURS** utiliser `_fetch_tierce_direct(endpoint, token)` — jamais
`tierce_client.forward_request()` qui reboucle sur notre propre nginx.

```python
# ✅ Correct
data = await _fetch_tierce_direct(f"/api/clients/{client_id}", token)

# ❌ Incorrect — rebouclage DNS → 401
response = await tierce_client.forward_request(endpoint=..., user_token=token)
```

## Common Mistakes

| Erreur | Symptôme | Correctif |
|---|---|---|
| **Rebouclage DNS** | 401 systématique depuis le backend | Utiliser `_fetch_tierce_direct` (SSL direct + SNI), jamais `tierce_client.forward_request` |
| **SNI incorrect** | `SSL: WRONG_VERSION_NUMBER` | `asyncio.open_connection(ip, 443, server_hostname=hostname)` — pas httpx vers l'IP |
| **Modifier /etc/hosts** | Casse le proxy pour les autres utilisateurs | Ne JAMAIS modifier `/etc/hosts` — utiliser `asyncio.open_connection` à la place |
| URL overlay avec préfixe app | 404 (`/app-tierce/api/clients` → catch-all nginx) | Utiliser `/api/...` (sans préfixe) qui est réécrit par nginx vers le backend |
| Token non capturé | "Naviguez sur l'app tierce d'abord" | L'app Angular doit faire au moins 1 appel API pour que le hook XHR capture le Bearer |
| Cache vide | Recherche ne retourne rien | Le cache se remplit par le trafic Angular naturel ou par le bouton preload |
| Cache non segmenté | Fuites de données entre utilisateurs | Toujours inclure `user_id` dans la clé de cache (sauf référentiels partagés) |
| Overlay non injecté | Pas de fenêtre overlay | Vérifier `sub_filter '</body>' '<script src="/overlay/overlay.js"></script></body>'` |

## Debugging rapide

```bash
# Vérifier que le proxy répond
curl -k -s -o /dev/null -w '%{http_code}' \
  --resolve exemple.org:443:192.0.2.10 \
  https://exemple.org/api/user
# Attendu : 401 (pas de token) — pas 502

# Voir les headers de cache
curl -k -s -D - --resolve exemple.org:443:192.0.2.10 \
  https://exemple.org/api/agencies | grep -i x-cache

# Vérifier le contenu du cache Redis
docker exec exemple-app-redis redis-cli --scan --pattern "proxy:cache:*" \
  | while read key; do docker exec exemple-app-redis redis-cli HGET "$key" endpoint; done \
  | sort | uniq -c | sort -rn

# Logs backend
docker logs -f --since 1m exemple-app-api

# Logs preload
docker logs --since 5m exemple-app-api 2>&1 | grep -i "Preload"
```

---

**Référence principale :** le `README.md` de l'implémentation de référence (`APPS/exemple-app/`, non publiée)
