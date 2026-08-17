#!/usr/bin/env bash
# test-fresh-install.sh — Harness : installation POULIDOR de zéro sur Debian 12.
#
# Monte une VM Debian 12 jetable (QEMU/KVM + cloud-init), exécute l'installation
# complète (clone + install.sh + santé Hub + smoke hubctl + création d'app),
# et produit un rapport pass/fail. Exit non-zéro si échec.
#
# Usage : scripts/test-fresh-install.sh [--keep] [--branch <branche>]
#   --keep        Conserver la VM en fin de run (debug)
#   --branch <b>  Tester la branche <b> (propagée par git bundle ; les
#                 sous-modules sont bundlés aussi). Défaut : origin/main.
#
# PRÉREQUIS (hôte) :
#   - qemu-kvm, qemu-utils, cloud-image-utils installés
#   - image de base présente : build/fresh-install/base/debian-12-generic-amd64.qcow2
#   - agent SSH actif avec accès à l'org GitHub (ssh-add -l non vide)
#     → le forward d'agent sert au clone depuis la VM.
#
# Découvertes intégrées (phase A, voir build/fresh-install/RAPPORT-FINAL.md) :
#   - host key GitHub absente d'une machine neuve → ssh-keyscan préalable
#   - install.sh / hubctl init interactifs → réponses par défaut pipées
#   - INITIALISE.py --profile demande une confirmation finale → printf 'O\n'
#   - allocate-ports refuse les IP hors whitelist → whitelist du subnet VM
#     + docker compose up -d (recreate, pas restart) pour recharger le .env
#   - must_change_password fiable via /api/auth/me (pas /api/auth/login)
#   - approve : POST {"approve": true} ; liste apps : /api/apps/ (slash final)
#
# shellcheck disable=SC2016  # les commandes en single quotes s'exécutent DANS la VM
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
# Rapport et logs dans runs/<ts> — HORS du dossier VM (détruit par vm_destroy)
RUN_DIR="$ROOT/build/fresh-install/runs/$TS"
KEEP=false
BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP=true; shift ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    *) echo "Usage: $0 [--keep] [--branch <branche>]" >&2; exit 2 ;;
  esac
done

mkdir -p "$RUN_DIR"
# shellcheck disable=SC1091  # lib sourcée : fournit vm_* et consomme les globals ci-dessous
source "$ROOT/scripts/lib/vm-debian12.sh"
export VM_NAME="harness-$TS"
VM_DIR="$FI_ROOT/$VM_NAME"
# Port aléatoire libre (évite les collisions avec une VM de debug sur 2222)
# shellcheck disable=SC2155
export VM_PORT="$(python3 - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
)"
# Recâbler les chemins dérivés après le changement de VM_PORT/VM_NAME
# (exportés : consommés par les fonctions de la lib, ex. vm_destroy)
export VM_KEY="$VM_DIR/vm_key"
export VM_PIDFILE="$VM_DIR/qemu.pid"
export VM_CONSOLE="$VM_DIR/console.log"
export VM_SEED="$VM_DIR/seed.iso"
export VM_DISK="$VM_DIR/overlay.qcow2"

PASS=0; FAIL=0
check() { # check <nom> <cmd...> : exécute, log, compte
  local name="$1"; shift
  echo "── [$name]" | tee -a "$RUN_DIR/report.txt"
  if "$@" >"$RUN_DIR/$name.log" 2>&1; then
    echo "PASS  $name" | tee -a "$RUN_DIR/report.txt"; PASS=$((PASS+1))
  else
    echo "FAIL  $name (log: $RUN_DIR/$name.log)" | tee -a "$RUN_DIR/report.txt"; FAIL=$((FAIL+1))
  fi
}

in_vm() { vm_ssh "$@"; }

# Script d'approbation de l'app (réutilisé pour approve + vérif finale)
approve_app() {
  vm_ssh 'cd ~/POULIDOR; PW=$(grep -E "^ADMIN_PASSWORD=" HUB_base/.env | cut -d= -f2); \
    TOKEN=$(curl -sf -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" \
      -d "{\"username\": \"admin\", \"password\": \"$PW\"}" \
      | python3 -c "import sys,json;print(json.load(sys.stdin)[\"access_token\"])"); \
    curl -sf -X POST http://localhost:8000/api/apps/testapp/approve \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"approve\": true}" | grep -q "approuvée"'
}

cleanup() {
  if $KEEP; then
    echo "VM conservée : $VM_DIR (SSH : ssh -i $VM_KEY -p $VM_PORT poulidor@localhost)"
  else
    vm_destroy >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Run : $RUN_DIR (VM port $VM_PORT)" | tee -a "$RUN_DIR/report.txt"

# ── A2 : VM neuve ──
check "vm-create" vm_create

# ── A3 : clone + sous-modules (agent forwardé par vm_ssh) ──
check "agent-forward" in_vm 'test -n "$SSH_AUTH_SOCK" && ssh-add -l >/dev/null'
check "github-hostkey" in_vm 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null'
check "clone" in_vm "git clone --recurse-submodules git@github.com:POULIDOR-Audit-Developpement/POULIDOR.git ~/POULIDOR"
if [ -n "$BRANCH" ]; then
  check "checkout-branch" vm_push_branch "$BRANCH"
fi
check "submodules" in_vm 'cd ~/POULIDOR && [ "$(git submodule status | wc -l)" -eq 5 ] && ls HUB_base/docker-compose.yml hubctl_src/hubctl HUBapp_TEMPLATE_base/Makefile >/dev/null'

# ── A4 : install (réponses par défaut pipées) ──
check "install" in_vm "cd ~/POULIDOR && printf '\n\n\n\n\n\n\n\n' | sudo ./install.sh"

# ── A5 : santé Hub ──
check "hub-health" in_vm 'API_PORT=$(grep -E "^HUB_API_PORT=" ~/POULIDOR/HUB_base/.env | cut -d= -f2); curl -sf "http://localhost:${API_PORT}/api/health" | grep -q "\"status\": \"healthy\"\|\"status\":\"healthy\""'
check "hub-frontend" in_vm 'curl -sk -o /dev/null -w "%{http_code}" https://localhost | grep -q 200'
check "hub-containers" in_vm 'sudo docker ps --format "{{.Names}} {{.Status}}" | grep -E "^hub-api .*\(healthy\)"'

# ── A6 : login admin + changement de mdp forcé (via /me, cf. découverte #4) ──
check "admin-login" in_vm 'cd ~/POULIDOR; PW=$(grep -E "^ADMIN_PASSWORD=" HUB_base/.env | cut -d= -f2); TOKEN=$(curl -sf -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" -d "{\"username\": \"admin\", \"password\": \"$PW\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"access_token\"])"); curl -sf http://localhost:8000/api/auth/me -H "Authorization: Bearer $TOKEN" | grep -q "\"must_change_password\": true\|\"must_change_password\":true"'

# ── A7 : smoke hubctl (commandes réelles, non destructrices) ──
check "hubctl-vpn-status" in_vm "cd ~/POULIDOR && ./hubctl vpn status"
check "hubctl-start-prod" in_vm "cd ~/POULIDOR && ./hubctl start prod"

# ── A8 : app de test bout-en-bout ──
check "app-create" in_vm 'cd ~/POULIDOR && bash scripts/create_app.sh testapp'
check "app-init" in_vm 'cd ~/POULIDOR/APPS/testapp && printf "{\"format_version\": \"1.0\", \"app\": {\"slug\": \"testapp\", \"name\": \"Test App\", \"description\": \"App de test fresh-install\"}, \"client\": {\"name\": \"POULIDOR Test\", \"contact_name\": \"Jellycode\", \"contact_email\": \"test@local.lan\"}, \"license\": {\"quote_number\": \"TEST-2026-0001\", \"quote_date\": \"2026-08-17\", \"notice_year\": \"2026\"}, \"hub\": {\"host\": \"10.0.2.15\", \"api_port\": 8000, \"frontend_port\": 80}, \"ports\": {\"api\": 9045, \"frontend\": 4250}, \"options\": {\"clean_demo\": true, \"tailwind\": false}}" > profile.json && printf "O\n" | python3 INITIALISE.py --profile profile.json && [ ! -f INITIALISE.py ]'
# Whitelist du subnet VM + recreate hub-api (docker compose restart ne recharge
# pas le .env — découverte #8) + attente du retour de santé (le recreate
# interrompt le service quelques secondes)
check "hub-whitelist" in_vm 'cd ~/POULIDOR/HUB_base && (grep -q "10.0.2.0/24" .env || sed -i "s/^APP_WHITELIST_NETWORKS=\(.*\)/APP_WHITELIST_NETWORKS=10.0.2.0\/24,\1/" .env); sudo docker compose up -d hub-api >/dev/null 2>&1; for i in $(seq 1 30); do curl -sf http://localhost:8000/api/health >/dev/null && exit 0; sleep 2; done; exit 1'
check "app-sync-env" in_vm 'cd ~/POULIDOR/APPS/testapp && make sync-env && grep -q "^API_PORT=[0-9]" .env'
check "app-up" in_vm 'cd ~/POULIDOR/APPS/testapp && make up'
check "app-health" in_vm 'cd ~/POULIDOR/APPS/testapp && API_PORT=$(grep -E "^API_PORT=" .env | cut -d= -f2); curl -sf "http://localhost:${API_PORT}/api/health" | grep -q "\"status\": \"healthy\"\|\"status\":\"healthy\""'
check "app-frontend" in_vm 'cd ~/POULIDOR/APPS/testapp && FRONT=$(grep -E "^FRONTEND_PORT=" .env | cut -d= -f2); curl -s -o /dev/null -w "%{http_code}" "http://localhost:${FRONT}" | grep -q 200'
check "app-register-pending" in_vm 'cd ~/POULIDOR; PW=$(grep -E "^ADMIN_PASSWORD=" HUB_base/.env | cut -d= -f2); TOKEN=$(curl -sf -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" -d "{\"username\": \"admin\", \"password\": \"$PW\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"access_token\"])"); curl -sL http://localhost:8000/api/apps/ -H "Authorization: Bearer $TOKEN" | grep -q "testapp"'
check "app-approve" approve_app
check "app-active" in_vm 'cd ~/POULIDOR; PW=$(grep -E "^ADMIN_PASSWORD=" HUB_base/.env | cut -d= -f2); TOKEN=$(curl -sf -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" -d "{\"username\": \"admin\", \"password\": \"$PW\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"access_token\"])"); curl -sL http://localhost:8000/api/apps/ -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); apps=d if isinstance(d,list) else d.get(\"items\") or d.get(\"apps\"); a=[x for x in apps if x.get(\"slug\")==\"testapp\"][0]; exit(0 if a.get(\"approval_status\")==\"approved\" and a.get(\"is_active\") else 1)"'

# ── Bilan ──
echo "" | tee -a "$RUN_DIR/report.txt"
echo "═══ RÉSULTAT : $PASS PASS / $FAIL FAIL ═══" | tee -a "$RUN_DIR/report.txt"
[ "$FAIL" -eq 0 ]
