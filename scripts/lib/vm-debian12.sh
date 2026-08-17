#!/usr/bin/env bash
# vm-debian12.sh — Primitives VM Debian 12 (QEMU direct + cloud-init NoCloud).
# Usage CLI : scripts/lib/vm-debian12.sh {usage|create|ssh|destroy|console} ...
# Ou sourcé : source scripts/lib/vm-debian12.sh && vm_create && vm_ssh "cmd"
set -euo pipefail

FI_ROOT="${FI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/build/fresh-install}"
FI_BASE_IMAGE="${FI_BASE_IMAGE:-$FI_ROOT/base/debian-12-generic-amd64.qcow2}"
VM_NAME="${VM_NAME:-current}"
VM_DIR="$FI_ROOT/$VM_NAME"
VM_KEY="$VM_DIR/vm_key"
VM_PORT="${VM_PORT:-2222}"
VM_SSHHOST="${VM_SSHHOST:-localhost}"
VM_USER="poulidor"
VM_PIDFILE="$VM_DIR/qemu.pid"
VM_CONSOLE="$VM_DIR/console.log"
VM_SEED="$VM_DIR/seed.iso"
VM_DISK="$VM_DIR/overlay.qcow2"

vm_ssh() {
  # ForwardAgent : requis pour les opérations GitHub (clone, submodule update)
  # depuis la VM — le lanceur doit avoir un agent actif (ssh-add).
  ssh -i "$VM_KEY" -p "$VM_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ForwardAgent=yes \
    -o ConnectTimeout=10 -o LogLevel=ERROR \
    "$VM_USER@$VM_SSHHOST" "$@"
}

vm_scp() { # vm_scp <src> <dst>
  scp -i "$VM_KEY" -P "$VM_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR "$1" "$2"
}

vm_wait_ssh() { # vm_wait_ssh [timeout_s]
  local timeout="${1:-300}" start=$(( $(date +%s) ))
  until vm_ssh true 2>/dev/null; do
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      echo "✗ SSH non disponible après ${timeout}s. Console :" >&2
      tail -30 "$VM_CONSOLE" >&2 || true
      return 1
    fi
    sleep 5
  done
}

vm_console_tail() { tail -n "${1:-50}" "$VM_CONSOLE"; }

vm_create() { # vm_create : clé + overlay + seed + boot + wait SSH
  [ -f "$FI_BASE_IMAGE" ] || { echo "✗ Image de base absente : $FI_BASE_IMAGE (voir Task 1)" >&2; return 1; }
  if ss -ltn "( sport = :$VM_PORT )" | grep -q LISTEN; then
    echo "✗ Port $VM_PORT déjà occupé sur l'hôte." >&2; return 1
  fi
  mkdir -p "$VM_DIR"

  # 1. Clé SSH jetable hôte→VM
  [ -f "$VM_KEY" ] || ssh-keygen -q -t ed25519 -N "" -f "$VM_KEY" -C "fi-vm"

  # 2. Overlay thin 20 Go sur l'image de base (jamais modifiée)
  qemu-img create -f qcow2 -F qcow2 -b "$FI_BASE_IMAGE" "$VM_DISK" 20G

  # 3. Seed cloud-init NoCloud
  cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: poulidor-fi
users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$VM_KEY.pub")
packages: [git, curl]
package_update: true
ssh_pwauth: false
EOF
  printf 'instance-id: poulidor-fi-%s\nlocal-hostname: poulidor-fi\n' \
    "$(date +%s)" > "$VM_DIR/meta-data"
  cloud-localds "$VM_SEED" "$VM_DIR/user-data" "$VM_DIR/meta-data"

  # 4. Boot daemonized, console série loggée
  qemu-system-x86_64 \
    -enable-kvm -cpu host -m 4096 -smp 2 \
    -drive file="$VM_DISK",format=qcow2,if=virtio \
    -drive file="$VM_SEED",format=raw,if=virtio,readonly=on \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$VM_PORT"-:22 \
    -device virtio-net-pci,netdev=net0 \
    -display none -monitor none \
    -serial "file:$VM_CONSOLE" \
    -pidfile "$VM_PIDFILE" -daemonize

  vm_wait_ssh 300
  echo "✓ VM prête : ssh -p $VM_PORT $VM_USER@$VM_SSHHOST (clé $VM_KEY)"
}

vm_destroy() {
  if [ -f "$VM_PIDFILE" ]; then
    kill "$(cat "$VM_PIDFILE")" 2>/dev/null || true
    rm -f "$VM_PIDFILE"
  fi
  rm -rf "$VM_DIR"
  echo "✓ VM $VM_NAME détruite."
}

vm_push_branch() { # vm_push_branch <branche> : bundle meta + sous-modules → VM
  # Les nouveaux SHAs de sous-modules n'existent pas sur GitHub → on bundle
  # chaque sous-module AVANT le checkout méta-repo (sinon submodule update
  # essaie de les fetcher depuis GitHub et échoue).
  local branch="$1"
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local sub sub_bundle bundle="/tmp/fi-${branch//\//-}.bundle"

  # 1. Bundles des sous-modules (HEAD courant de chacun)
  for sub in HUB_base HUBCSS hub-mcp HUBapp_TEMPLATE_base hubctl_src; do
    if [ -d "$root/$sub/.git" ] || git -C "$root" config --get "submodule.$sub.url" >/dev/null 2>&1; then
      sub_bundle="/tmp/fi-sub-${sub//\//-}.bundle"
      if git -C "$root/$sub" rev-parse HEAD >/dev/null 2>&1; then
        git -C "$root/$sub" bundle create "$sub_bundle" HEAD >/dev/null 2>&1 || true
        vm_scp "$sub_bundle" "$VM_USER@$VM_SSHHOST:/tmp/$(basename "$sub_bundle")"
        vm_ssh "cd ~/POULIDOR/$sub && git fetch /tmp/$(basename "$sub_bundle") HEAD && git checkout -q -B fi-sub FETCH_HEAD && rm -f /tmp/$(basename "$sub_bundle")" || true
        rm -f "$sub_bundle"
      fi
    fi
  done

  # 2. Bundle méta-repo + checkout + submodule update (SHAs déjà locaux)
  git -C "$root" bundle create "$bundle" "$branch" >/dev/null
  vm_scp "$bundle" "$VM_USER@$VM_SSHHOST:/tmp/$(basename "$bundle")"
  rm -f "$bundle"
  vm_ssh "cd ~/POULIDOR && git fetch /tmp/$(basename "$bundle") '$branch' \
    && git checkout -B '$branch' FETCH_HEAD \
    && git submodule update --init --recursive \
    && rm -f /tmp/$(basename "$bundle")"
}

usage() {
  cat <<'EOS'
vm-debian12.sh — Primitives VM Debian 12 pour test fresh-install POULIDOR

CLI   : vm-debian12.sh {usage|create <nom>|ssh "<cmd>"|console <nom>|destroy <nom>}
Sourcé: source vm-debian12.sh; puis vm_create / vm_ssh / vm_scp / vm_wait_ssh /
        vm_console_tail / vm_destroy / vm_push_branch <branche>

Env   : FI_ROOT (défaut build/fresh-install), FI_BASE_IMAGE,
        VM_NAME (défaut current), VM_PORT (défaut 2222)
EOS
}

# ── CLI ──────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-usage}" in
    usage) usage ;;
    create) VM_NAME="${2:-current}"; VM_DIR="$FI_ROOT/$VM_NAME"; VM_KEY="$VM_DIR/vm_key"; VM_PIDFILE="$VM_DIR/qemu.pid"; VM_CONSOLE="$VM_DIR/console.log"; VM_SEED="$VM_DIR/seed.iso"; VM_DISK="$VM_DIR/overlay.qcow2"; vm_create ;;
    ssh)    shift; vm_ssh "$@" ;;
    console) VM_NAME="${2:-current}"; VM_CONSOLE="$FI_ROOT/$VM_NAME/console.log"; vm_console_tail 80 ;;
    destroy) VM_NAME="${2:-current}"; VM_DIR="$FI_ROOT/$VM_NAME"; VM_PIDFILE="$VM_DIR/qemu.pid"; vm_destroy ;;
    *) usage; exit 1 ;;
  esac
fi
