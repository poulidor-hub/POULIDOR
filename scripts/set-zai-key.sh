#!/usr/bin/env bash
# set-zai-key.sh — Persiste la clé API Z.ai pour le MCP `zai-mcp-server` d'opencode.
#
# Le MCP est déclaré dans opencode.json avec "Z_AI_API_KEY": "{env:Z_AI_API_KEY}" :
# opencode interpole la variable d'environnement au démarrage (substitution {env:VAR}
# appliquée au texte de la config). La clé ne transit donc JAMAIS dans le dépôt git.
#
# Ce script écrit la clé dans ~/.bashrc (bloc marqué, idempotent) pour que chaque
# nouveau shell — dont celui qui lance opencode — l'exporte.
#
# Usage:
#   scripts/set-zai-key.sh <CLE_API>        # définit la clé
#   scripts/set-zai-key.sh --mode ZAI|GLM   # change le mode (Z_AI_MODE dans opencode.json)
#   scripts/set-zai-key.sh --show           # affiche l'état actuel (clé masquée)
#
# Après modification : redémarrer opencode (la config n'est pas hot-reloadée).

set -euo pipefail

MARK_BEGIN="# >>> opencode zai api key >>>"
MARK_END="# <<< opencode zai api key <<<"
BASHRC="${HOME}/.bashrc"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; die "Arguments invalides."; }

die() { echo "ERREUR: $*" >&2; exit 1; }

current_state() {
  if grep -qF "$MARK_BEGIN" "$BASHRC" 2>/dev/null; then
    local key
    key=$(sed -n "/^${MARK_BEGIN}$/,/^${MARK_END}$/p" "$BASHRC" | grep -oP '(?<=export Z_AI_API_KEY=")[^"]*' || true)
    if [[ -n "$key" ]]; then
      echo "Clé définie dans $BASHRC : ${key:0:6}…${key: -4} (${#key} caractères)"
    else
      echo "Bloc présent dans $BASHRC mais clé vide/absente."
    fi
  else
    echo "Aucune clé persistée dans $BASHRC."
  fi
  if [[ -n "${Z_AI_API_KEY:-}" ]]; then
    echo "Variable d'environnement courante : ${Z_AI_API_KEY:0:6}…${Z_AI_API_KEY: -4} (${#Z_AI_API_KEY} caractères)"
  else
    echo "Variable d'environnement courante : non définie."
  fi
}

write_key() {
  local key="$1"
  [[ ${#key} -ge 16 ]] || die "La clé semble trop courte (${#key} caractères) — vérifiez la valeur."
  [[ ${#key} -le 256 ]] || die "La clé semble trop longue (${#key} caractères) — vérifiez la valeur."

  touch "$BASHRC"
  # Retire tout bloc existant puis ajoute le nouveau (idempotent).
  sed -i "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$BASHRC"
  {
    echo "$MARK_BEGIN"
    echo "export Z_AI_API_KEY=\"$key\""
    echo "$MARK_END"
  } >> "$BASHRC"
  chmod 600 <( : ) 2>/dev/null || true # no-op, .bashrc garde ses perms

  echo "OK — clé persistée dans $BASHRC (bloc marqué, idempotent)."
  echo "Prenez-en compte immédiatement :"
  echo "  source ~/.bashrc"
  echo "Puis redémarrez opencode (la config MCP n'est pas hot-reloadée)."
}

write_mode() {
  local mode="$1"
  [[ "$mode" == "ZAI" || "$mode" == "GLM" ]] || die "Mode invalide '$mode' (attendu : ZAI ou GLM)."
  local cfg
  cfg="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/opencode.json"
  python3 - "$cfg" "$mode" <<'PY'
import json, sys
path, mode = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["mcp"]["zai-mcp-server"]["environment"]["Z_AI_MODE"] = mode
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"OK — Z_AI_MODE={mode} écrit dans {path}")
PY
  echo "Redémarrez opencode pour prendre en compte le changement."
}

[[ $# -ge 1 ]] || { current_state; exit 0; }

case "$1" in
  --show)  current_state ;;
  --mode)  [[ $# -ge 2 ]] || usage; write_mode "$2" ;;
  -h|--help) usage ;;
  *)       write_key "$1" ;;
esac
