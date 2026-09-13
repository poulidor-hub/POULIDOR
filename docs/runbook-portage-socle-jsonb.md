# RUNBOOK — Portage du fix socle v2.23.4 (jsonb/asyncpg) dans exemple-app et exemple-app

> **Destinataire** : IA ou développeur devant publier la correction sur les apps
> `exemple-app` et `exemple-app`. Procédure complète, testée en
> conditions réelles sur les bancs POULIDOR-lab (13-14/09/2026).
>
> **Priorité** : normale-forte. En prod, le restore de ces deux apps échoue
> silencieusement sur les lignes portant des valeurs jsonb (rapporté « succès »
> avec `importés: 0`).

---

## 1. Le bug (pourquoi ce portage)

`routes/backup.py` (copie historique du socle embarquée dans l'app) restaure les
données du backup ligne par ligne. Les dict/list reconstruits par
`_deserialize_value` (contenu JSON des colonnes jsonb) sont passés **tels quels**
au driver asyncpg, qui exige une **chaîne JSON** pour ces types :

```
DataError: invalid input for query argument $N: {} (descriptor 'encode'
for 'str' objects doesn't apply to a 'dict' object)
```

Conséquence : la ligne est rejetée (savepoint), le restore se termine en
« avec des erreurs » ou — pire — rapporte un succès partiel ; les données jsonb
ne sont jamais restaurées.

**Référence upstream** : HUBsocle **v2.23.4** (commit `ef8317a`, test
`backend/tests/test_backup_jsonb_values.py`, suite socle 203 passed). Mergé sur
`main` HUBsocle (`209f1cb`), pointeur méta v0.55.7.

## 2. Apps concernées

| App | VERSION source | Repo | Fichier à patcher |
|---|---|---|---|
| `exemple-app` | 0.4.0 | `git@github.com:Federation-exemple-50/exemple-app.git` | `backend/routes/backup.py` |
| `exemple-app` | 0.15.0 | `git@github.com:Federation-exemple-50/exemple-app.git` | `backend/routes/backup.py` |

Vérification préalable (les deux apps ont le même code, une seule occurrence du
pattern, ligne ~248) :

```bash
git clone git@github.com:Federation-exemple-50/<APP>.git && cd <APP>
grep -c 'deserialized = {k: _deserialize_value(v) for k, v in row_data.items()}' backend/routes/backup.py
# attendu : 1   (sinon, stop — le code local diverge, adaptation requise)
grep -c '_normalize_db_value' backend/routes/backup.py
# attendu : 0   (sinon : déjà patché, stop)
grep -n '^import json' backend/routes/backup.py
# attendu : présent (le patch l'utilise)
```

## 3. Portage — TDD (test d'abord, RED vérifié)

### Étape 1 — Porter le test (backend/tests/test_backup_jsonb_values.py)

Créer le fichier (adaptation directe du test du socle : l'import vise
`routes.backup` au lieu de `hub_socle.routes.backup`) :

```python
"""FIX banc 2026-09-13 : restore — les colonnes jsonb/json cassent l'import
asyncpg. `_deserialize_value` reconstruit les dict/list du backup ; asyncpg
exige une chaîne JSON pour ces types → DataError → ligne rejetée.

Contrat : les valeurs composites (dict/list) destinées au driver sont
sérialisées en JSON (json.dumps) ; les scalaires natifs passent inchangés.
"""
import json
from datetime import datetime, date
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from routes.backup import _import_table_data, _normalize_db_value


class TestNormalizeDbValue:
    def test_dict_serialized_to_json_string(self):
        v = {"theme": "dark", "nested": {"a": 1}}
        out = _normalize_db_value(v)
        assert isinstance(out, str)
        assert json.loads(out) == v

    def test_list_serialized_to_json_string(self):
        out = _normalize_db_value([1, "a", {"b": 2}])
        assert isinstance(out, str)
        assert json.loads(out) == [1, "a", {"b": 2}]

    def test_empty_dict_becomes_json_object_string(self):
        assert _normalize_db_value({}) == "{}"

    def test_scalars_unchanged(self):
        for v in [None, "texte", "", 42, 3.14, True]:
            assert _normalize_db_value(v) == v

    def test_datetime_unchanged(self):
        dt = datetime(2026, 9, 13, 12, 0, 0)
        assert _normalize_db_value(dt) is dt

    def test_date_decimal_bytes_unchanged(self):
        d, dec, b = date(2026, 9, 13), Decimal("1.5"), b"bytes"
        assert _normalize_db_value(d) is d
        assert _normalize_db_value(dec) is dec
        assert _normalize_db_value(b) is b


class TestImportTableDataSerializesJsonb:
    @pytest.mark.asyncio
    async def test_rows_pass_json_strings_to_driver(self):
        captured = {}

        async def fake_execute(query, params=None):
            captured["query"] = str(query)
            captured["params"] = params
            return MagicMock()

        db = MagicMock()
        db.execute = fake_execute
        db.get_bind.return_value.dialect.name = "postgresql"
        sp = MagicMock()
        sp.commit = AsyncMock()
        sp.rollback = AsyncMock()
        db.begin_nested = AsyncMock(return_value=sp)

        with patch("routes.backup._get_primary_key_columns",
                   AsyncMock(return_value=["id"])), \
             patch("routes.backup._get_table_columns",
                   AsyncMock(return_value=[{"name": "id"}, {"name": "title"},
                                           {"name": "payload"}])):
            stats = await _import_table_data(
                db, "items",
                [{"id": 1, "title": "x", "payload": {"theme": "dark"}}],
                clear_existing=True,
            )

        assert stats["imported"] == 1, stats
        params = captured["params"]
        assert isinstance(params["payload"], str)
        assert json.loads(params["payload"]) == {"theme": "dark"}
        assert params["id"] == 1
        assert params["title"] == "x"
```

> Adapter le `sys.path` si nécessaire : les apps exécutent le code sous
> `backend/` (module `routes.backup`). Un `conftest.py` minimal existe déjà
> dans `backend/tests/`.

### Étape 2 — Vérifier le RED

```bash
cd <APP>/backend && python3 -m pytest tests/test_backup_jsonb_values.py -q
# attendu : ImportError — cannot import name '_normalize_db_value'
```

### Étape 3 — Le fix (code exact, aligné socle v2.23.4)

Dans `backend/routes/backup.py` :

1. Insérer la fonction **juste avant** `async def _import_table_data(` :

```python
def _normalize_db_value(value):
    """
    Sérialise les valeurs composites pour le driver asyncpg.

    asyncpg exige une chaîne JSON pour les colonnes jsonb/json : lui passer
    un dict/list reconstruit par `_deserialize_value` déclenche DataError
    (« invalid input for query argument $N: {} »). Les scalaires natifs
    (str, int, float, bool, None, datetime, date, Decimal, bytes) passent
    tels quels.
    """
    if isinstance(value, (dict, list)):
        return json.dumps(value)
    return value
```

2. Remplacer la ligne (une seule occurrence) :

```python
        deserialized = {k: _deserialize_value(v) for k, v in row_data.items()}
```

par :

```python
        deserialized = {k: _normalize_db_value(_deserialize_value(v)) for k, v in row_data.items()}
```

### Étape 4 — Vérifier le GREEN + suite complète

```bash
python3 -m pytest tests/test_backup_jsonb_values.py -q     # 7 passed
python3 -m pytest tests/ -q                                # suite complète : 0 régression
```

Référence banc : exemple-app 7/7 + suite verte ; exemple-app idem.

## 4. release-on-main de l'app

- **Bump PATCH** de `VERSION` (correction uniquement) :
  - exemple-app : 0.4.0 → **0.4.1**
  - exemple-app : 0.15.0 → **0.15.1**
- **CHANGELOG** : prépender l'entrée (format du dépôt), section
  `### ⚡ Corrigé : restore — colonnes jsonb rejetées par asyncpg` avec la
  référence HUBsocle v2.23.4.
- Commit (`fix(restore): …`), merge vers `main`, `git push origin main`.

## 5. Déploiement prod

Sur le serveur client (après pull des sources de l'app) :

```bash
cd <APP> && docker compose build api && docker compose up -d --force-recreate api
curl -sf "http://localhost:$(grep '^API_PORT=' .env | cut -d= -f2)/api/health"
# attendu : {"status":"healthy", "hub_connected":true, ...}
```

⚠️ Mémo incidents banc (à ne pas reproduire) : lors de la mise à jour du
`.env`/compose, ne jamais laisser un conteneur banc pointer un volume partagé
avec prod (la séquence exacte a vidé le datadir prod de `exemple-app`, réparé
depuis le banc hubv2 — cf. journal du banc du 13-14/09).

## 6. Vérification fonctionnelle post-déploiement

1. Sur un banc à jour : déclencher `backup` de l'app mise à jour → `export`
   chiffré → `import` vers l'autre banc (`clear_existing=true`) → la ligne
   `TEST-` avec valeur jsonb doit être **retrouvée** côté cible.
   (Sur les bancs POULIDOR-lab, ce flux est déjà vert pour les 3 apps avec le
   patch porté — cf. `journal-transferts-2026-09-13.md`.)
2. En prod : déclencher un `backup` (le dump embarque désormais les valeurs
   jsonb sérialisées) et vérifier `last_backup_status = success`.

## 7. Rollback

Le patch est purement additif (une fonction + un wrapping). Rollback :
`git revert <commit du fix>` dans le repo de l'app, rebuild, recreate.

## 8. Suivi

| App | Fix socle | Test porté | Release app | Déployé prod |
|---|---|---|---|---|
| exemple-app | v2.23.4 | ✓ (banc) | à faire (0.4.1) | à faire |
| exemple-app | v2.23.4 | ✓ (banc) | à faire (0.15.1) | à faire |

Source de vérité du fix : HUBsocle `main` @ `209f1cb` (v2.23.4) ;
journaux : `POULIDOR-lab/journal-transferts-2026-09-13.md` et
`journal-isolation-volumes-2026-09-13.md`.
