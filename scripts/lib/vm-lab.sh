#!/usr/bin/env bash
# vm-lab.sh — Labos VM Debian 12 PERSISTANTS pour POULIDOR.
#
# S'appuie sur vm-debian12.sh (primitives QEMU/cloud-init éprouvées) avec
# FI_ROOT redirigé vers build/vm-lab/ — périmètre STRICT : rien d'autre que
# ce dossier n'est créé/modifié/supprimé. build/fresh-install/ = archive de
# preuves du test initial, jamais touchée (l'image de base y est seulement
# hardlinkée).
#
# CLI   : vm-lab.sh {create|start|ssh|restore|inject|push|list|destroy} ...
# Sourcé: source vm-lab.sh; lab_create <nom> ...
#
# Env   : LAB_ROOT (défaut build/vm-lab), VM_LAB_BASE_IMAGE (image qcow2),
#         VM_LAB_MAX_LABS (défaut 2), VM_LAB_MIN_DISK_GB (défaut 20)
set -euo pipefail

LAB_ROOT="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/build/vm-lab}"
VM_LAB_MAX_LABS="${VM_LAB_MAX_LABS:-2}"
VM_LAB_MIN_DISK_GB="${VM_LAB_MIN_DISK_GB:-20}"
VM_LAB_BASE_NAME="debian-12-generic-amd64.qcow2"

# Primitives VM (vm_create/vm_ssh/vm_scp/vm_wait_ssh/vm_destroy/vm_push_branch)
# avec FI_ROOT redirigé — les chemins dérivés (VM_DIR…) seront recâblés par
# _lab_bind après choix du labo.
export FI_ROOT="$LAB_ROOT"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/vm-debian12.sh"

# ── Helpers ──────────────────────────────────────────────────────────────────

_lab_check_name() { # valide le nom : enfant direct sûr de build/vm-lab/
  local name="$1"
  if ! [[ "$name" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    echo "✗ Nom de labo invalide : '$name' (^[a-z][a-z0-9-]{0,30}$)" >&2
    return 1
  fi
  [ "$name" != "base" ] || { echo "✗ 'base' est réservé (image de base)." >&2; return 1; }
}

_lab_bind() { # positionne VM_* depuis le dossier du labo (port persisté)
  local name="$1"
  _lab_check_name "$name"
  local dir="$LAB_ROOT/$name"
  [ -d "$dir" ] || { echo "✗ Labo inconnu : $name (voir : vm-lab.sh list)" >&2; return 1; }
  [ -f "$dir/port.txt" ] || { echo "✗ port.txt manquant pour $name — labo cassé ?" >&2; return 1; }
  VM_NAME="$name"
  VM_DIR="$dir"
  VM_KEY="$dir/vm_key"
  VM_PORT="$(cat "$dir/port.txt")"
  VM_PIDFILE="$dir/qemu.pid"
  VM_CONSOLE="$dir/console.log"
  VM_SEED="$dir/seed.iso"
  VM_DISK="$dir/overlay.qcow2"
}

_lab_bind_new() { # comme _lab_bind mais pour un labo en cours de création
  local name="$1" port="$2"
  _lab_check_name "$name"
  # exportés : consommés par les fonctions de vm-debian12.sh (vm_create…)
  export VM_NAME="$name"
  VM_DIR="$LAB_ROOT/$name"
  export VM_KEY="$VM_DIR/vm_key"
  export VM_PORT="$port"
  export VM_PIDFILE="$VM_DIR/qemu.pid"
  export VM_CONSOLE="$VM_DIR/console.log"
  export VM_SEED="$VM_DIR/seed.iso"
  export VM_DISK="$VM_DIR/overlay.qcow2"
}

_lab_free_port() { # port TCP aléatoire libre
  python3 - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
}

_lab_find_base_image() { # image de base : lab → repo courant → repo principal
  local self_root
  self_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local candidates=("${VM_LAB_BASE_IMAGE:-}" "$LAB_ROOT/base/$VM_LAB_BASE_NAME" "$self_root/build/fresh-install/base/$VM_LAB_BASE_NAME")
  local common_dir
  common_dir="$(git -C "$self_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common_dir" ] && [ -d "$common_dir" ] && candidates+=("$(dirname "$common_dir")/build/fresh-install/base/$VM_LAB_BASE_NAME")
  local c
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

_lab_ensure_base_image() { # copie l'image dans build/vm-lab/base/ (hardlink si possible)
  local src
  src="$(_lab_find_base_image)" || {
    echo "✗ Image de base introuvable. Télécharge-la :" >&2
    echo "    mkdir -p $LAB_ROOT/base && cd $LAB_ROOT/base" >&2
    echo "    wget https://cloud.debian.org/images/cloud/bookworm/latest/$VM_LAB_BASE_NAME \\" >&2
    echo "        https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS" >&2
    echo "    grep generic-amd64 SHA512SUMS | sha512sum -c -" >&2
    return 1
  }
  mkdir -p "$LAB_ROOT/base"
  local dst="$LAB_ROOT/base/$VM_LAB_BASE_NAME"
  [ -f "$dst" ] && return 0
  if ln "$src" "$dst" 2>/dev/null; then
    echo "  Image de base : hardlink (0 octet consommé)"
  elif cp --reflink=auto "$src" "$dst" 2>/dev/null; then
    echo "  Image de base : copie reflink/copy"
  else
    cp "$src" "$dst"
  fi
}

_lab_count() { # nb de labos existants (hors base/)
  local n=0 d
  for d in "$LAB_ROOT"/*/; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" != "base" ] && [ -f "$d/port.txt" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

_lab_disk_free_gb() { df -BG --output=avail "$(dirname "$LAB_ROOT")" | tail -1 | tr -dc '0-9'; }

# ── Commandes ────────────────────────────────────────────────────────────────

lab_create() { # lab_create <nom> : VM neuve persistante + journal
  local name="${1:?usage: lab_create <nom>}"
  _lab_check_name "$name"
  [ ! -d "$LAB_ROOT/$name" ] || { echo "✗ Le labo '$name' existe déjà (vm-lab.sh ssh $name / destroy $name)." >&2; return 1; }
  [ "$(_lab_count)" -lt "$VM_LAB_MAX_LABS" ] || { echo "✗ Déjà $VM_LAB_MAX_LABS labos actifs (garde-fou disque) — détruis-en un : vm-lab.sh list" >&2; return 1; }
  local free_gb; free_gb="$(_lab_disk_free_gb)"
  [ "$free_gb" -ge "$VM_LAB_MIN_DISK_GB" ] || { echo "✗ Disque hôte insuffisant : ${free_gb} Go libres (min ${VM_LAB_MIN_DISK_GB} Go)." >&2; return 1; }

  _lab_ensure_base_image
  _lab_bind_new "$name" "$(_lab_free_port)"
  vm_create # clé + overlay + seed + boot + attente cloud-init (git présent)
  echo "$VM_PORT" > "$VM_DIR/port.txt"
  cat > "$VM_DIR/journal.md" <<EOF
# Labo $name — $(date +%Y-%m-%d\ %H:%M)

**But :** (à compléter — bug reproduit ? branche testée ? serveur client simulé ?)

## Événements
- $(date +%F\ %T) créé (port $VM_PORT, périmètre build/vm-lab/$name)
EOF
  echo "✓ Labo '$name' prêt : vm-lab.sh ssh $name  (journal : $VM_DIR/journal.md)"
}

lab_start() { # lab_start <nom> : relance une VM existante (ex: après reboot hôte)
  local name="${1:?usage: lab_start <nom>}"
  _lab_bind "$name"
  if [ -f "$VM_PIDFILE" ] && kill -0 "$(cat "$VM_PIDFILE")" 2>/dev/null; then
    echo "✓ Labo '$name' déjà actif (port $VM_PORT)"
    return 0
  fi
  if ss -ltn "( sport = :$VM_PORT )" | grep -q LISTEN; then
    echo "✗ Port $VM_PORT occupé sur l'hôte — recrée le labo ou libère le port." >&2
    return 1
  fi
  [ -f "$VM_DISK" ] || { echo "✗ Overlay absent ($VM_DISK) — labo cassé." >&2; return 1; }
  rm -f "$VM_PIDFILE"
  qemu-system-x86_64 \
    -enable-kvm -cpu host -m 4096 -smp 2 \
    -drive file="$VM_DISK",format=qcow2,if=virtio \
    -drive file="$VM_SEED",format=raw,if=virtio,readonly=on \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$VM_PORT"-:22 \
    -device virtio-net-pci,netdev=net0 \
    -display none -monitor none \
    -serial "file:$VM_CONSOLE" \
    -pidfile "$VM_PIDFILE" -daemonize
  vm_wait_ssh 180
  echo "✓ Labo '$name' relancé (port $VM_PORT)"
}

lab_ssh() { # lab_ssh <nom> [cmd...]
  local name="${1:?usage: lab_ssh <nom> [cmd...]}"
  shift
  _lab_bind "$name"
  vm_ssh "$@"
}

lab_push() { # lab_push <nom> <branche> : branche locale + sous-modules → VM
  local name="${1:?usage: lab_push <nom> <branche>}" branch="${2:?usage: lab_push <nom> <branche>}"
  _lab_bind "$name"
  vm_push_branch "$branch"
}

lab_inject() { # lab_inject <nom> <src> <dst-dans-la-VM>
  local name="${1:?usage: lab_inject <nom> <src> <dst>}" src="${2:?}" dst="${3:?}"
  _lab_bind "$name"
  vm_scp "$src" "$VM_USER@$VM_SSHHOST:$dst"
  echo "✓ Injecté : $src → labo:$dst"
}

lab_restore() { # lab_restore <nom> <artefact> [args hubctl...]
  # Artefacts reconnus : *kit-pra* → hubctl pra-restore --yes
  #                      park-*.tar.gz → hubctl restore --passphrase-stdin
  # La passphrase est demandée LOCALEMENT (jamais stockée) puis pipée.
  local name="${1:?usage: lab_restore <nom> <artefact> [args...]}" file="${2:?}"
  shift 2
  _lab_bind "$name"
  [ -f "$file" ] || { echo "✗ Artefact introuvable : $file" >&2; return 1; }
  vm_ssh "test -x ~/POULIDOR/hubctl" 2>/dev/null || {
    echo "✗ ~/POULIDOR/hubctl absent dans la VM — installe d'abord le parc :" >&2
    echo "    vm-lab.sh ssh $name  # puis clone --recurse-submodules + sudo ./install.sh" >&2
    return 1
  }
  local base_cmd
  case "$(basename "$file")" in
    *kit-pra*) base_cmd="./hubctl pra-restore /tmp/$(basename "$file") --yes" ;;
    park-*.tar.gz) base_cmd="./hubctl restore /tmp/$(basename "$file") --passphrase-stdin" ;;
    *)
      echo "⚠ Artefact non reconnu automatiquement ($(basename "$file"))." >&2
      echo "  Injecté dans /tmp — lance la restauration adaptée via : vm-lab.sh ssh $name" >&2
      vm_scp "$file" "$VM_USER@$VM_SSHHOST:/tmp/$(basename "$file")"
      return 0
      ;;
  esac
  vm_scp "$file" "$VM_USER@$VM_SSHHOST:/tmp/$(basename "$file")"
  local pp rc
  printf "Passphrase (ne sera ni affichée ni stockée) : " >&2
  IFS= read -rs pp </dev/tty 2>/dev/null || IFS= read -rs pp # fallback sans TTY
  printf '\n' >&2
  set +e
  printf '%s\n' "$pp" | vm_ssh "cd ~/POULIDOR && $base_cmd $*"
  rc=$?
  set -e
  unset pp
  [ $rc -eq 0 ] && echo "✓ Restauration lancée/terminée — vérifie la santé (journal : $VM_DIR/journal.md)"
  return $rc
}

lab_list() { # labos : nom, état, port, âge, taille + alertes
  local total=0 found=0 d name age_days size state port
  echo "Labos VM ($LAB_ROOT) :"
  for d in "$LAB_ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ "$name" != "base" ] || continue
    [ -f "$d/port.txt" ] || continue
    found=$((found + 1))
    port="$(cat "$d/port.txt")"
    if [ -f "$d/qemu.pid" ] && kill -0 "$(cat "$d/qemu.pid")" 2>/dev/null; then state="up"; else state="down"; fi
    age_days=$(( ( $(date +%s) - $(stat -c %Y "$d") ) / 86400 ))
    size="$(du -sh "$d" 2>/dev/null | cut -f1)"
    local warn=""
    [ "$age_days" -gt 7 ] && warn=" ⚠ >7j (détruis-le s'il est obsolète)"
    printf "  %-20s %-4s port %-6s %3dj  %-6s%s\n" "$name" "$state" "$port" "$age_days" "$size" "$warn"
    total=$((total + 1))
  done
  [ "$found" -eq 0 ] && echo "  (aucun labo — vm-lab.sh create <nom>)"
  local pct; pct="$(df --output=pcent "$(dirname "$LAB_ROOT")" | tail -1 | tr -dc '0-9')"
  local droot; droot="$(_lab_disk_free_gb)"
  echo "Disque hôte : ${pct}% utilisé, ${droot} Go libres$([ "$pct" -ge 95 ] && echo ' ⚠')"
  return 0
}

lab_destroy() { # lab_destroy <nom> : kill QEMU + suppression du dossier
  local name="${1:?usage: lab_destroy <nom>}"
  _lab_check_name "$name"
  local dir="$LAB_ROOT/$name"
  [ -d "$dir" ] || { echo "✗ Labo inconnu : $name" >&2; return 1; }
  # Double garde : la cible doit être un enfant DIRECT de build/vm-lab/
  [ "$(dirname "$dir")" = "$LAB_ROOT" ] || { echo "✗ Cible hors périmètre." >&2; return 1; }
  # exportés : consommés par vm_destroy (lib sourcée)
  export VM_NAME="$name"; VM_DIR="$dir"; export VM_PIDFILE="$dir/qemu.pid"
  vm_destroy
  echo "  (journal perdu avec le dossier — archive-le avant si besoin)"
}

usage() {
  cat <<'EOS'
vm-lab.sh — Labos VM Debian 12 persistants pour POULIDOR (périmètre build/vm-lab/)

  create  <nom>              VM neuve + journal.md + port persisté
  start   <nom>              Relancer une VM existante (après reboot hôte)
  ssh     <nom> [cmd...]     Session / commande dans la VM
  push    <nom> <branche>    Branche locale + sous-modules → VM (git bundle)
  inject  <nom> <src> <dst>  Copier un fichier dans la VM
  restore <nom> <artefact>   Kit PRA / park-export → hubctl adapté (passphrase prompt)
  list                        Labos actifs + alertes (âge, disque)
  destroy <nom>              Détruire le labo (VM + fichiers)

Env : LAB_ROOT, VM_LAB_BASE_IMAGE, VM_LAB_MAX_LABS (2), VM_LAB_MIN_DISK_GB (20)
EOS
}

# ── CLI ──────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-usage}" in
    create)  shift; lab_create "$@" ;;
    start)   shift; lab_start "$@" ;;
    ssh)     shift; lab_ssh "$@" ;;
    push)    shift; lab_push "$@" ;;
    inject)  shift; lab_inject "$@" ;;
    restore) shift; lab_restore "$@" ;;
    list)    lab_list ;;
    destroy) shift; lab_destroy "$@" ;;
    usage|*) usage; [ "${1:-}" = "usage" ] || exit 1 ;;
  esac
fi
