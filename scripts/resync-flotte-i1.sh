#!/usr/bin/env bash
# resync-flotte-i1.sh — Passe flotte : access logs nginx sans query string
# (ticket I1 — JWT SSO ?token= ?refresh_token= jamais loggés).
#
# Validé sur exemple-app 0.26.2 (prod, 11/11/2026) : /callback?token= silencieux,
# /chat?token= silencieux (le cas qui fuyait encore après 0.26.1), accès sans
# query toujours loggé au format noquery.
#
# Périmètre : les apps de APPS/ qui (a) sont des repos git, (b) ont nginx.conf,
# (c) consomment le socle (hub-socle/hub_socle), (d) ne portent pas déjà le
# fix, (e) sont propres (pas de WIP non commité).
# Par app : worktree (parc-isolate) → patch log_format noquery → bump patch +
# CHANGELOG → merge sous lock → push → rebuild+up prod si l'app tourne →
# sonde token factice non loggée.
#
# Usage : bash resync-flotte-i1.sh [app1 app2 ...]   (sans argument = toutes)
set -uo pipefail
POULIDOR=/home/kkleskk/MyCOMPANY/HUB_stack/POULIDOR
APPS_DIR="$POULIDOR/APPS"
ISOLATE="$POULIDOR/scripts/parc-isolate"
LOG="/tmp/opencode/resync-flotte-i1-$(date +%H%M%S).log"
BRANCH=fix/log-format-noquery

patch_app() {
  local app="$1"
  local d="$APPS_DIR/$app"
  echo "── $app ──" | tee -a "$LOG"
  [ -f "$d/nginx.conf" ] || { echo "   skip: pas de nginx.conf" | tee -a "$LOG"; return 1; }
  if grep -q "noquery" "$d/nginx.conf" 2>/dev/null \
     && grep -q "^HTTPS_ENABLED=true" "$d/.env.example" 2>/dev/null \
     && grep -q "^IS_SHARED=true" "$d/.env.example" 2>/dev/null; then
    echo "   skip: déjà patché" | tee -a "$LOG"; return 0
  fi
  local dirty; dirty=$(git -C "$d" status --porcelain 2>/dev/null | grep -v "^??" | wc -l)
  [ "$dirty" -gt 0 ] && { echo "   SKIP: $dirty fichier(s) non commité(s) — à traiter manuellement" | tee -a "$LOG"; return 1; }

  ( cd "$d" && bash "$ISOLATE" "$BRANCH" "I1: access logs sans query string (JWT SSO)" >/dev/null 2>&1 ) || { echo "   FAIL: parc-isolate" | tee -a "$LOG"; return 1; }
  local wt="$d/.worktrees/_agents/fix-log-format-noquery"

  python3 - "$wt" <<'PYEOF'
import sys
wt = sys.argv[1]
prelude = """# Ticket I1 : les tokens SSO transitent en query string (?token=…&refresh_token=…)
# sur le chemin d'origine du login — jamais dans les access logs : format sans
# query string pour tout ce serveur.
log_format noquery '$remote_addr - $remote_user [$time_local] '
                   '"$request_method $uri $server_protocol" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent"';

"""
access = "    access_log /var/log/nginx/access.log noquery;\n"
for conf in ("nginx.conf", "nginx-ssl.conf"):
    p = f"{wt}/{conf}"
    c = open(p, encoding="utf-8").read()
    if "noquery" in c:
        continue
    c = prelude + c
    c = c.replace("server {\n", "server {\n" + access)
    open(p, "w", encoding="utf-8").write(c)
    print(f"   patch {conf}")
PYEOF
  [ $? -ne 0 ] && { echo "   FAIL: patch" | tee -a "$LOG"; return 1; }

  # .env.example : HTTPS_ENABLED=true + IS_SHARED=true (défauts parc —
  # n'affecte PAS les .env déployés : update_env préserve les valeurs
  # existantes ; uniquement les premiers boots / nouveaux scaffolds).
  python3 - "$wt" <<'PYENV'
import re, sys
wt = sys.argv[1]
p = f"{wt}/.env.example"
try:
    c = open(p, encoding="utf-8").read()
except FileNotFoundError:
    sys.exit(0)
def setkey(c, key, value):
    new = re.sub(rf"^{key}=.*$", f"{key}={value}", c, flags=re.M)
    if new != c:
        return new
    new = re.sub(rf"^#\s*{key}=.*$", f"{key}={value}", c, flags=re.M)
    if new != c:
        return new
    return c.rstrip("\n") + f"\n{key}={value}\n"
c = setkey(c, "HTTPS_ENABLED", "true")
c = setkey(c, "IS_SHARED", "true")
open(p, "w", encoding="utf-8").write(c)
print("   patch .env.example (HTTPS_ENABLED=true, IS_SHARED=true)")
PYENV

  ( cd "$wt" && python3 scripts/bump_version.py patch >/dev/null 2>&1 )
  local ver; ver=$(cat "$wt/VERSION" 2>/dev/null)
  python3 - "$wt" "$app" "$ver" <<'PYEOF'
import sys
wt, app, ver = sys.argv[1], sys.argv[2], sys.argv[3]
p = f"{wt}/CHANGELOG.md"
c = open(p, encoding="utf-8").read()
entry = f"""## [{ver}] - 11 novembre 2026

### 🔒 Access logs sans query string (I1 — JWT SSO)

- `log_format noquery` sur les serveurs nginx : aucun query string loggé
  (`$request_method $uri $server_protocol`) — les tokens SSO
  (`?token=…&refresh_token=…`, renvoyés par le Hub sur le chemin d'origine
  du login) ne finissent plus dans les logs persistants du conteneur.
- `.env.example` : `HTTPS_ENABLED=true` + `IS_SHARED=true` (défauts parc,
  n'affecte pas les `.env` déployés).
- Trade-off : les routes SPA apparaissent comme `/index.html` (URI interne
  après fallback try_files). Logs backend inchangés (masquage `token=`
  actif côté socle). Motif : ticket I1 — review migration exemple-app 0.26.0,
  fix de référence exemple-app 0.26.2.

"""
open(p, "w", encoding="utf-8").write(entry + c)
PYEOF

  ( cd "$wt" && git add -u && git commit -m "fix(security): log_format noquery — access logs sans query string (I1)" --quiet ) || { echo "   FAIL: commit" | tee -a "$LOG"; return 1; }

  # Merge sous lock
  local lock="$d/.worktrees/_agents/.lock"
  for i in $(seq 1 10); do mkdir "$lock" 2>/dev/null && break; sleep 1; done
  git -C "$d" checkout main -q 2>&1 | head -1
  git -C "$d" pull origin main -q
  git -C "$d" merge "$BRANCH" --no-ff -m "Merge $BRANCH — $ver : access logs sans query string (I1)" >/dev/null || { echo "   FAIL: merge" | tee -a "$LOG"; rmdir "$lock" 2>/dev/null; return 1; }
  git -C "$d" push origin main -q && echo "   push $ver OK" | tee -a "$LOG"
  python3 - "$d" <<'PYEOF'
import json, sys
r = sys.argv[1] + "/.worktrees/_agents/registry.json"
d = json.load(open(r))
for a in d["agents"]:
    if a["branch"] == "fix/log-format-noquery" and a["status"] == "active":
        a["status"] = "merged"
json.dump(d, open(r, "w"), indent=2, ensure_ascii=False)
PYEOF
  rmdir "$lock" 2>/dev/null

  # Rebuild+up prod si l'app tourne
  if docker ps --format '{{.Names}}' | grep -q "^${app}-frontend"; then
    ( cd "$d" && make build >/dev/null 2>&1 && make up >/dev/null 2>&1 ) || { echo "   WARN: rebuild/up a échoué — à refaire" | tee -a "$LOG"; return 1; }
    echo "   prod rebuild OK" | tee -a "$LOG"
  else
    echo "   app down → appliqué au prochain boot" | tee -a "$LOG"
  fi

  # Cleanup + sonde (port réel du .env de l'app, token unique par app,
  # code HTTP exigé — sinon la sonde est non concluable et on le dit)
  bash "$ISOLATE" --cleanup "$BRANCH" >/dev/null 2>&1
  if docker ps --format '{{.Names}}' | grep -q "^${app}-frontend"; then
    sleep 3
    local fport scheme=https
    fport=$(grep -E '^FRONTEND_HTTPS_PORT=' "$d/.env" 2>/dev/null | tail -1 | cut -d= -f2)
    if [ -z "$fport" ]; then
      scheme=http
      fport=$(grep -E '^FRONTEND_PORT=' "$d/.env" 2>/dev/null | tail -1 | cut -d= -f2)
    fi
    local marker="FAKE-I1-${app}"
    local code; code=$(curl -sk${scheme#https} -o /dev/null -w '%{http_code}' --max-time 10 "$scheme://localhost:${fport}/callback?token=${marker}" 2>/dev/null)
    if [ "$code" != "200" ]; then
      echo "   ⚠️ SONDE non concluable (HTTP $code sur $scheme://localhost:${fport})" | tee -a "$LOG"
    elif docker logs "${app}-frontend" 2>&1 | grep -q "${marker}"; then
      echo "   ⚠️ SONDE: token factice ENCORE loggé" | tee -a "$LOG"
    else
      echo "   sonde: token factice non loggé ✔ (HTTP 200)" | tee -a "$LOG"
    fi
  fi
  return 0
}

mkdir -p /tmp/opencode
if [ $# -gt 0 ]; then APPS=("$@"); else
  APPS=()
  for d in "$APPS_DIR"/*/; do
    a=$(basename "$d")
    [ -d "$d/.git" ] && [ -f "$d/nginx.conf" ] || continue
    grep -rq "hub-socle\|hub_socle" "$d/frontend/package.json" "$d/frontend/src" 2>/dev/null || continue
    grep -q "noquery" "$d/nginx.conf" 2>/dev/null && continue
    dirty=$(git -C "$d" status --porcelain 2>/dev/null | grep -v "^??" | wc -l)
    [ "$dirty" -eq 0 ] && APPS+=("$a")
  done
fi

echo "🚀 Resync flotte I1 — ${#APPS[@]} app(s) : ${APPS[*]}" | tee -a "$LOG"
FAILS=()
for a in "${APPS[@]}"; do
  patch_app "$a" || FAILS+=("$a")
done
echo "═══════════" | tee -a "$LOG"
echo "Fini. Échecs: ${#FAILS[@]} ${FAILS[*]:-}" | tee -a "$LOG"
echo "Log complet: $LOG"
