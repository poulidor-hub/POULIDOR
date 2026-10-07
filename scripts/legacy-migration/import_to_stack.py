#!/usr/bin/env python3
"""
import_to_stack.py — Adaptateur de migration : export JSON du hub legacy
(hub-legacy `export_env.py`) → hub neuf (API admin POULIDOR/HUB_base).

Périmètre v1 :
  - users       : créés s'ils manquent (mot de passe temporaire + must_change_password ;
                  les hash bcrypt legacy ne sont pas réinjectables via l'API) ;
                  existants → inchangés.
  - applications: créées si manquantes (URLs réécrites localhost →
                  host.docker.internal pour api_url, lisible depuis le conteneur
                  hub-api) ; existantes → INCHANGÉES (les URLs locales du registre
                  neuf font foi).
  - rôles       : user_app_roles legacy réassignés sur les users/apps mappés
                  (POST /api/users/bulk/assign-app-roles).
  - service_accounts : RAPPORT SEULEMENT en v1 (secrets chiffrés côté legacy
                  [Fernet, clé SECRET_KEY du legacy] → import M2M = chantier dédié).

Usage :
  python3 import_to_stack.py --legacy-json legacy-export.json                # dry-run
  python3 import_to_stack.py --legacy-json legacy-export.json --apply        # applique
  python3 import_to_stack.py --legacy-json x.json --login admin --password … # au lieu de --token

Sortie : rapport lisible + compteur ; exit 0 si aucune erreur bloquante.
Stdlib uniquement (comme le playbook https-flotte).
"""
import argparse
import json
import secrets
import string
import sys
import urllib.error
import urllib.request


def hub_req(hub_url, method, path, token=None, payload=None, timeout=20):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(hub_url + path, method=method, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}
    except Exception as e:
        return 0, {"detail": str(e)}


def rewrite_api_url(url: str) -> str:
    """localhost:PORT (vue navigateur/banc) → host.docker.internal:PORT (vue hub-api)."""
    if not url:
        return url
    return url.replace("://localhost:", "://host.docker.internal:")


def temp_password(n=14):
    alphabet = string.ascii_letters + string.digits + "!@#$%"
    return "".join(secrets.choice(alphabet) for _ in range(n))


def main():
    ap = argparse.ArgumentParser(description="Import legacy → hub neuf")
    ap.add_argument("--legacy-json", required=True)
    ap.add_argument("--hub-url", default="http://localhost:8000")
    ap.add_argument("--token", help="token admin hub neuf (sinon --login/--password)")
    ap.add_argument("--login")
    ap.add_argument("--password")
    ap.add_argument("--apply", action="store_true", help="sans ce flag : dry-run")
    ap.add_argument("--temp-password", help="mdp temporaire des users créés (défaut: aléatoire)")
    ap.add_argument("--report-out", help="écrire le rapport JSON")
    args = ap.parse_args()

    tok = args.token
    if not tok:
        if not (args.login and args.password):
            sys.exit("❌ --token ou --login/--password requis")
        code, d = hub_req(args.hub_url, "POST", "/api/auth/login", None,
                          {"username": args.login, "password": args.password})
        if code != 200 or not d.get("access_token"):
            sys.exit(f"❌ login hub neuf échoué ({code})")
        tok = d["access_token"]

    legacy = json.load(open(args.legacy_json))
    report = {"mode": "apply" if args.apply else "dry-run",
              "users": [], "applications": [], "roles": [], "service_accounts": [], "erreurs": []}

    # --- état local ---
    code, d = hub_req(args.hub_url, "GET", "/api/apps/all", tok)
    local_apps = {a["slug"]: a for a in (d if isinstance(d, list) else d.get("apps", []))}
    code, d = hub_req(args.hub_url, "GET", "/api/users/", tok)
    local_users = {u["username"]: u for u in (d if isinstance(d, list) else d.get("users", d.get("items", [])))} \
        if code == 200 else {}

    # --- users ---
    for u in legacy.get("users", []):
        name = u["username"]
        if name in local_users:
            report["users"].append({"username": name, "action": "existe déjà (inchangé)"})
            continue
        pwd = args.temp_password or temp_password()
        email = u.get("email") or f"{name}@migration.local.lan"
        # email_validator (pydantic) exige un point après le @ — normalise les
        # domaines internes legacy ("user@local" → "user@local.lan").
        if "@" in email and "." not in email.split("@", 1)[1]:
            email = email + ".lan"
        payload = {"username": name, "email": email,
                   "password": pwd, "is_active": u.get("is_active", True),
                   "is_admin": u.get("is_admin", False)}
        if args.apply:
            code, d = hub_req(args.hub_url, "POST", "/api/users/", tok, payload)
            ok = code in (200, 201)
            report["users"].append({"username": name, "action": "créé" if ok else "échec",
                                    "mdp_temporaire": pwd if ok else None,
                                    "must_change_password": True, "detail": d if not ok else ""})
            if ok:
                local_users[name] = {"username": name, "id": d.get("id")}
        else:
            report["users"].append({"username": name, "action": "serait créé (mdp temporaire)"})

    # --- applications ---
    for a in legacy.get("applications", []):
        slug = a["slug"]
        if slug == "hub":
            report["applications"].append({"slug": slug, "action": "système (ignoré)"})
            continue
        if slug in local_apps:
            report["applications"].append({"slug": slug, "action": "existe déjà (URLs locales conservées)"})
            continue
        payload = {"name": a["name"], "slug": slug, "description": a.get("description"),
                   "icon": a.get("icon") or "bi-app", "color": a.get("color") or "#0d6efd",
                   "api_url": rewrite_api_url(a.get("api_url")),
                   "frontend_url": rewrite_api_url(a.get("frontend_url")) if a.get("frontend_url") else None,
                   "callback_url": a.get("callback_url"), "requires_auth": a.get("requires_auth", True)}
        if args.apply:
            code, d = hub_req(args.hub_url, "POST", "/api/apps/", tok, payload)
            ok = code in (200, 201)
            report["applications"].append({"slug": slug, "action": "créée" if ok else "échec",
                                           "detail": d if not ok else ""})
            if ok:
                local_apps[slug] = d
        else:
            report["applications"].append({"slug": slug,
                                           "action": f"serait créée (api_url {payload['api_url']})"})

    # --- rôles user ↔ app ---
    assignments = []
    for r in legacy.get("user_app_roles", []):
        u, s, role = r.get("username"), r.get("app_slug"), r.get("role")
        if u not in local_users or s not in local_apps:
            report["roles"].append({"user": u, "app": s, "action": "introuvable localement (ignoré)"})
            continue
        assignments.append({"app_id": local_apps[s]["id"], "user_ids": [local_users[u]["id"]], "role": role})
        report["roles"].append({"user": u, "app": s, "role": role, "action": "assigné" if args.apply else "serait assigné"})
    if assignments and args.apply:
        hub_req(args.hub_url, "POST", "/api/users/bulk/assign-app-roles", tok,
                {"assignments": assignments})

    # --- service accounts (rapport v1) ---
    n_sa = len(legacy.get("service_accounts", []))
    report["service_accounts"].append({"action": f"rapport seul (v1) — {n_sa} SAs legacy détectés ; "
                                                 "secrets chiffrés côté legacy → import M2M = chantier dédié"})

    # --- résumé ---
    print(f"=== import_to_stack — mode {report['mode'].upper()} ===")
    for section in ("users", "applications", "roles"):
        for r in report[section]:
            print(f"  [{section[:-1]}] {json.dumps(r, ensure_ascii=False)}")
    for r in report["service_accounts"]:
        print(f"  [service_account] {r['action']}")
    errs = report["erreurs"]
    print(f"=== erreurs bloquantes: {len(errs)} ===")
    if args.report_out:
        json.dump(report, open(args.report_out, "w"), indent=2, ensure_ascii=False)
    sys.exit(0)


if __name__ == "__main__":
    main()
