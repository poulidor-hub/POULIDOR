---
name: proxy-ia
description: Utiliser quand on conçoit ou étend un proxy transparent avec overlay frontend pour une application web tierce, en s'appuyant sur un cache backend partagé et le token utilisateur (piggyback) pour exécuter des requêtes et des actions sans saturer le navigateur. Cas de référence : PhiliaNG / philiang dans exemple-app.
---

# proxy-ia — Proxy transparent + overlay + cache collectif

## Overview

Le pattern **proxy-ia** permet d'enrichir une application web tierce (SaaS, legacy, Angular…) sans modifier son code source. On interpose un proxy transparent qui :

1. Sert l'app tierce telle quelle au navigateur.
2. Intercepte ses appels API pour les mettre en cache côté backend.
3. Injecte un overlay JS dans les pages de l'app tierce.
4. L'overlay capte le token de l'utilisateur et appelle des endpoints backend dédiés.
5. Le backend exploite le cache partagé pour répondre instantanément ou exécuter des actions API au nom de l'utilisateur.

**Objectif :** réduire le trafic WAN, décharger le navigateur, et ajouter des fonctionnalités transverses (recherche, actions, monitoring) sans toucher à l'app cible.

## When to Use

- On veut enrichir une app web tierce sans modifier son code.
- L'app cible fait beaucoup d'appels API répétitifs et/ou lents.
- On veut mutualiser un cache entre utilisateurs et entre sessions.
- On veut ajouter une recherche "cross-données" ou des actions batch qui ne sont pas natives.
- On veut monitorer/intercepter le trafic API de l'app cible.
- **Cas de référence dans le parc :** exemple-app (`APPS/exemple-app`) intercepte PhiliaNG (`service.example.org`).

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
│         │   XHR/fetch            │   /api/overlay/*             │
│         │   (Bearer token)       │   (Bearer piggyback)         │
│         ▼                        ▼                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               Nginx proxy transparent                     │   │
│  │   /api/*      ──▶ backend /philia-ng/api/* (cache proxy)  │   │
│  │   /api/overlay ──▶ backend /api/overlay/* (overlay API)   │   │
│  │   /* (static)  ──▶ app tierce réelle (WAN)                │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Backend FastAPI / API Hub                    │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │ Proxy cache │  │ Overlay     │  │ Client HTTP     │   │   │
│  │  │ (L1/L2)     │  │ routes      │  │ vers app tierce │   │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Cache L1 (mémoire LRU) + Cache L2 (Redis) partagé        │   │
│  │  Segmenté par utilisateur (sauf référentiels partagés)    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Core Pattern

### 1. Proxy transparent

Le navigateur accède à l'app tierce via le **même nom de domaine** que d'habitude. Le DNS (ou le fichier `hosts`) pointe vers le proxy.

- Les assets statiques passent directement à l'app tierce.
- Les appels API (`/api/*`) sont redirigés vers le backend du proxy.
- Le backend transmet le token/cookie de l'utilisateur à l'app tierce.

**Avantage :** l'app tierce ne sait pas qu'elle est proxifiée. Les cookies SSO continuent de fonctionner.

### 2. Piggyback du token

L'overlay JS est injecté dans chaque page HTML de l'app tierce (via `sub_filter` nginx ou équivalent). Il intercepte les headers `Authorization: Bearer ...` des requêtes XHR/fetch natives de l'app :

```javascript
// Extrait simplifié — APPS/exemple-app/frontend/public/overlay/overlay.js
const originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
  if (name === 'Authorization' && value.startsWith('Bearer ')) {
    capturedBearerToken = value;
  }
  return originalSetHeader.apply(this, arguments);
};
```

L'overlay réutilise ensuite ce Bearer dans ses appels à `/api/overlay/*`.

> **Règle d'or :** le backend ne stocke jamais le token en clair. S'il doit être persisté, il est chiffré (ex: `PhiliaToken.access_token_encrypted` avec Fernet).

### 3. Cache collectif L1/L2

Les réponses GET de l'app tierce sont stockées dans un cache à deux niveaux :

| Niveau | Techno | Latence | Persistance |
|---|---|---|---|
| L1 | Mémoire (LRU) | < 0.1 ms | Process-only |
| L2 | Redis | < 1 ms | Partagé entre workers |

- Segmentation par utilisateur (`user_id` dans la clé de cache).
- TTL par catégorie d'endpoint (référentiel, liste, planning, dossier).
- Revalidation stale-while-revalidate en arrière-plan.
- Déduplication des requêtes concurrentes.

### 4. Recherche backend dans le cache

Au lieu d'appeler l'app tierce pour chaque recherche, le backend scanne les entrées déjà en cache. Exemple dans exemple-app :

```python
# APPS/exemple-app/backend/routes/overlay.py
entries = await cache_manager.get_entries_by_endpoint("/api/clients")
# → fusion + filtrage textuel côté proxy, 0 appel WAN
```

**Condition préalable :** le cache doit avoir été préalablement alimenté par la navigation de l'utilisateur dans l'app tierce, ou par un warmup.

### 5. Actions API via le cache

L'overlay peut demander au backend d'exécuter des actions sur l'app tierce en utilisant le token capturé. Le backend peut :

- Appeler l'app tierce directement (POST/PUT/DELETE).
- Invalider chirurgicalement le cache après mutation.
- Pré-charger des données connexes pour mettre à jour le cache.

### 6. Warmup / pré-cache

Pour éviter un cache vide au démarrage, on peut lancer un warmup qui appelle en parallèle les endpoints critiques de l'app tierce pour un utilisateur donné :

```python
# APPS/exemple-app/backend/routes/overlay.py
POST /api/overlay/agencies/warmup
```

Le warmup utilise le token piggybacké ou un token stocké/chiffré en DB.

## Référence PhiliaNG / philiang

| Rôle | Fichier |
|---|---|
| Config nginx transparent | `APPS/exemple-app/nginx-philiang.conf` |
| Proxy transparent backend | `APPS/exemple-app/backend/routes/philia_transparent.py` |
| Routes overlay | `APPS/exemple-app/backend/routes/overlay.py` |
| Cache manager | `APPS/exemple-app/backend/cache.py` |
| Client HTTP vers Philia | `APPS/exemple-app/backend/philia_client.py` |
| Overlay JS injecté | `APPS/exemple-app/frontend/public/overlay/overlay.js` |
| SNI routing côté HUB | `HUB_base/frontend/nginx-ssl.conf` (bloc `service.example.org`) |
| Svc account / secrets | `HUB_base/secrets/service_accounts/sa_philia-proxy.env` |

### Flux d'une requête API PhiliaNG

1. Navigateur → `https://service.example.org/api/clients`
2. `HUB_base/frontend/nginx-ssl.conf` route SNI vers `philia-proxy-frontend:8443`
3. `APPS/exemple-app/nginx-philiang.conf` redirige `/api/*` vers `backend_pool`
4. `philia_transparent.py` :
   - extrait le Bearer de l'utilisateur
   - vérifie le cache L1/L2
   - si HIT → réponse immédiate
   - si MISS → forward vers PhiliaNG réel, met en cache, retourne
5. Réponse au navigateur avec headers `X-Cache`, `X-Cache-TTL`, etc.

### Headers de diagnostic

| Header | Valeurs | Signification |
|---|---|---|
| `X-Cache` | `HIT`, `MISS`, `BYPASS`, `BLOCKED`, `STALE`, `REVALIDATED` | Origine de la réponse |
| `X-Cache-TTL` | secondes | Temps restant en cache |
| `X-Cache-Category` | `referentiel`, `liste`, `planning`, `dossier` | Catégorie de l'endpoint |
| `X-Cache-Hits` | nombre | Nombre de hits sur cette entrée |
| `X-Philia-Auth` | `shared`, `personal` | Mode d'authentification |
| `X-Philia-Latency` | ms | Latence vers l'upstream |

## Cookbook

### Ajouter un endpoint overlay

1. Ajouter la route dans `backend/routes/overlay.py` sous `router = APIRouter(prefix="/api")`.
2. Authentifier via `_get_username_from_ng_session(request, db)` (cookie `philia_ng_session`).
3. Appeler le cache ou l'app tierce selon le besoin.
4. Mettre à jour `overlay.js` pour consommer le nouvel endpoint.

### Ajouter une recherche backend dans le cache

1. Identifier l'endpoint source déjà caché (ex: `/api/clients`).
2. Utiliser `cache_manager.get_entries_by_endpoint(endpoint)` pour récupérer les entrées.
3. Fusionner, dédupliquer par `id`, filtrer côté backend.
4. Retourner un format compact (15-50 résultats max).
5. Prévoir le cas "cache vide" avec un message explicite pour l'utilisateur.

### Ajouter une action API sur l'app tierce

1. Créer un endpoint `POST /api/overlay/<action>`.
2. Récupérer le Bearer depuis le header `Authorization` de la requête overlay.
3. Appeler l'app tierce via `philia_client.forward_request(...)` avec `user_token=token`.
4. Invalider le cache concerné avec `cache_manager.invalidate_surgical(method, endpoint)`.
5. Logger l'audit (`audit.log_audit`).

### Ajouter un warmup

1. Définir la liste des endpoints à pré-charger.
2. Créer un manager asynchrone (`agency_warmup.py` comme modèle).
3. Endpoint `POST /api/overlay/.../warmup` qui lance `asyncio.create_task(...)`.
4. Endpoint `GET /api/overlay/.../warmup/progress` pour le polling.
5. Utiliser le token piggybacké ou le token stocké/chiffré.

## Adapter à une autre app web

| Étape | Question clé | Fichier type |
|---|---|---|
| 1. DNS / SNI | Peut-on faire pointer le domaine de l'app vers notre proxy ? | nginx, DNS, `hosts` |
| 2. Auth | L'app utilise-t-elle un Bearer token ou des cookies de session ? | overlay JS, backend client |
| 3. Interception | Quel est le préfixe API à intercepter ? | nginx location |
| 4. Cache | Quelles sont les catégories de données et leurs TTL ? | `cache.py`, config |
| 5. Segmentation | Le cache doit-il être par utilisateur ou partagé ? | clés de cache |
| 6. Overlay | Où injecter le script overlay ? | nginx `sub_filter` |
| 7. Warmup | Quels endpoints critiques pré-charger ? | manager dédié |

## Common Mistakes

| Erreur | Symptôme | Correctif |
|---|---|---|
| Token non transmis à l'upstream | 401 sur les appels proxy | Vérifier `proxy_set_header Authorization $http_authorization` |
| Boucle de proxy | Connexion refusée / 502 | Configurer `PHILIA_REAL_IP` et forwarder vers l'IP réelle, pas le hostname |
| Cache non segmenté | Fuites de données entre utilisateurs | Toujours inclure `user_id` dans la clé de cache |
| Clés de cache instables | Taux de hit faible | Normaliser les params (ordre, valeurs par défaut) avant de hasher |
| Invalider tout le cache sur mutation | Performance dégradée | Utiliser `invalidate_surgical` avec mapping endpoint → patterns |
| Overlay non injecté | Pas de fenêtre overlay | Vérifier `sub_filter '</body>' '<script src="/overlay/overlay.js"></script></body>'` |
| Token stocké en clair | Fuite de credentials | Chiffrer avec Fernet dans la DB |

## Debugging rapide

```bash
# Vérifier que le proxy répond
curl -k -s -o /dev/null -w '%{http_code}' \
  --resolve service.example.org:443:192.0.2.10 \
  https://service.example.org/api/user
# Attendu : 401 (pas de token) — pas 502

# Voir les headers de cache
curl -k -s -D - --resolve service.example.org:443:192.0.2.10 \
  https://service.example.org/api/agencies | grep -i x-cache

# Logs backend
docker logs -f --since 1m philia-proxy-api
```

---

**Référence principale :** `APPS/exemple-app/README.md`
