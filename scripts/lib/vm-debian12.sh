#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

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
  # Attendre la fin de cloud-init : sshd démarre AVANT l'installation des
  # packages (git, curl) — sans ça, git peut manquer juste après le boot.
  vm_ssh "sudo cloud-init status --wait >/dev/null 2>&1" || true
  vm_ssh "command -v git >/dev/null" || { echo "✗ git absent après cloud-init — voir $VM_CONSOLE" >&2; return 1; }
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

# ── vm_push_branch : le méta et TOUS ses sous-modules partent en bundles ──────
# Les nouveaux SHA des sous-modules n'existent pas sur GitHub : chaque dépôt
# part donc par bundle, celui du méta compris. Les sous-modules sont lus dans
# .gitmodules (aucune liste en dur) et chaque étape rend non-zéro au premier
# échec — rien n'est envoyé tant que tous les bundles ne sont pas prêts.

_VM_PUSH_TRAP=""   # trap EXIT de l'appelant : chaîné le temps de l'appel, rendu en fin
_VM_PUSH_WD=""     # bundles côté hôte (dossier jetable)
_VM_PUSH_RDIR=""   # bundles côté VM (dossier jetable)

_vm_push_q() { # _vm_push_q <mot> : entre quotes single, pour la ligne de commande distante
  # ssh colle les arguments avec des espaces : c'est le shell distant qui découpe.
  local s="${1//\'/\'\\\'\'}"
  printf "'%s'" "$s"
}

_vm_push_fail() { # _vm_push_fail <message> : signale l'étape en échec, rend 1
  echo "✗ vm_push_branch : $*" >&2
  return 1
}

_vm_push_cleanup() { # retire les bundles des deux côtés ; répétable, n'échoue jamais
  local wd="${_VM_PUSH_WD:-}" rdir="${_VM_PUSH_RDIR:-}"
  _VM_PUSH_WD="" _VM_PUSH_RDIR=""
  [ -z "$wd" ] || rm -rf "$wd" || true
  [ -z "$rdir" ] || vm_ssh "rm -rf -- $(_vm_push_q "$rdir")" >/dev/null 2>&1 || true
}

_vm_push_on_exit() { # trap EXIT : bundles retirés, puis trap EXIT de l'appelant s'il en avait un
  _vm_push_cleanup
  [ -n "${_VM_PUSH_TRAP:-}" ] || return 0
  local line="$_VM_PUSH_TRAP"
  eval "set -- ${line#trap -- }"   # $1 = commande du trap de l'appelant, $2… = ses signaux
  eval "$1"
}

vm_push_branch() { # vm_push_branch <branche> : bundle du méta + de tous ses sous-modules → VM
  local branch="${1:?usage: vm_push_branch <branche>}" root rc=0
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  _VM_PUSH_WD="$(mktemp -d "${TMPDIR:-/tmp}/fi-push.XXXXXX")" || {
    _VM_PUSH_WD=""
    _vm_push_fail "impossible de créer un dossier temporaire"
    return 1
  }
  _VM_PUSH_RDIR=""
  # Bundles retirés même en cas d'erreur (signal compris) : trap EXIT, chaîné à
  # celui de l'appelant — ex. destruction de la VM par le harnais — et rendu à
  # l'appelant avant de rendre la main.
  _VM_PUSH_TRAP="$(trap -p EXIT)"
  trap _vm_push_on_exit EXIT
  _vm_push_run "$branch" "$root" || rc=$?
  _vm_push_cleanup
  if [ -n "$_VM_PUSH_TRAP" ]; then eval "$_VM_PUSH_TRAP"; else trap - EXIT; fi
  return "$rc"
}

_vm_push_run() { # _vm_push_run <branche> <racine> : les étapes ; s'arrête et rend 1 au premier échec
  local branch="$1" root="$2"
  local wd="$_VM_PUSH_WD" rdir listing out sub name bundle rb sha i rc=0
  local -a subs=() shas=() skipped=()

  # 1. Bundles côté hôte : méta, puis chaque sous-module dont le HEAD local existe
  bundle="$wd/fi-meta.bundle"
  out="$(git -C "$root" bundle create "$bundle" "$branch" 2>&1 >/dev/null)" \
    || { _vm_push_fail "bundle du méta (branche « $branch ») — $out"; return 1; }
  if [ -f "$root/.gitmodules" ]; then
    listing="$(git -C "$root" config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>&1)" || rc=$?
    [ "$rc" -le 1 ] || { _vm_push_fail "lecture de .gitmodules — $listing"; return 1; }
    while IFS= read -r sub; do
      [ -n "$sub" ] || continue
      sub="${sub#* }"
      if [ ! -e "$root/$sub/.git" ]; then skipped+=("$sub"); continue; fi   # pas initialisé localement
      sha="$(git -C "$root/$sub" rev-parse --verify HEAD 2>&1)" \
        || { _vm_push_fail "sous-module « $sub » : HEAD local illisible — $sha"; return 1; }
      out="$(git -C "$root/$sub" bundle create "$wd/fi-sub-${sub//\//-}.bundle" HEAD 2>&1 >/dev/null)" \
        || { _vm_push_fail "bundle du sous-module « $sub » — $out"; return 1; }
      subs+=("$sub")
      shas+=("$sha")
    done <<< "$listing"
  fi

  # 2. Dossier jetable dans la VM, puis bundle du méta
  rdir="$(vm_ssh mktemp -d)" || { _vm_push_fail "création du dossier de bundles dans la VM — $rdir"; return 1; }
  rdir="${rdir##*$'\n'}"
  [ -n "$rdir" ] || { _vm_push_fail "création du dossier de bundles dans la VM"; return 1; }
  _VM_PUSH_RDIR="$rdir"
  rb="$rdir/fi-meta.bundle"
  vm_scp "$bundle" "$VM_USER@$VM_SSHHOST:$rb" \
    || { _vm_push_fail "copie du bundle du méta vers la VM"; return 1; }

  # 3. Méta, une seule fois : ~/POULIDOR doit exister pour y cloner les sous-modules.
  #    Scripts distants par l'entrée standard (heredoc quoté) : rien à échapper.
  vm_ssh "bash -s -- $(_vm_push_q "$branch") $(_vm_push_q "$rb")" <<'EOS' || { _vm_push_fail "bootstrap du méta dans ~/POULIDOR"; return 1; }
set -eu
export GIT_TERMINAL_PROMPT=0   # identifiant manquant : échec immédiat, pas d'attente
if [ ! -e "$HOME/POULIDOR/.git" ]; then
  git clone -q -b "$1" "$2" "$HOME/POULIDOR"
fi
EOS

  # 4. Sous-modules : clonés dans ~/POULIDOR (VM neuve) ou avancés au commit bundlé
  for i in "${!subs[@]}"; do
    sub="${subs[$i]}"
    name="${sub//\//-}"
    rb="$rdir/fi-sub-$name.bundle"
    vm_scp "$wd/fi-sub-$name.bundle" "$VM_USER@$VM_SSHHOST:$rb" \
      || { _vm_push_fail "copie du bundle de « $sub » vers la VM"; return 1; }
    vm_ssh "bash -s -- $(_vm_push_q "$sub") $(_vm_push_q "$rb") $(_vm_push_q "${shas[$i]}")" <<'EOS' \
      || { _vm_push_fail "sous-module « $sub » dans la VM (clone ou fetch du bundle)"; return 1; }
set -eu
export GIT_TERMINAL_PROMPT=0
d="$HOME/POULIDOR/$1"
if [ -e "$d/.git" ]; then
  git -C "$d" fetch -q "$2" HEAD
  git -C "$d" checkout -q --detach FETCH_HEAD
else
  # Le bundle ne porte que HEAD : selon la version de git, le clone en laisse
  # HEAD indéterminé → checkout explicite du commit bundlé.
  git -c advice.detachedHead=false clone -q "$2" "$d"
  git -C "$d" checkout -q --detach "$3"
fi
EOS
  done

  # 5. Méta sur la branche bundlée, puis ses sous-modules : leurs commits y sont
  #    déjà, git ne va pas les chercher sur GitHub
  vm_ssh "bash -s -- $(_vm_push_q "$branch") $(_vm_push_q "$rdir/fi-meta.bundle")" <<'EOS' \
    || { _vm_push_fail "méta dans la VM (branche « $branch » puis sous-modules)"; return 1; }
set -eu
export GIT_TERMINAL_PROMPT=0
m="$HOME/POULIDOR"
git -C "$m" fetch -q "$2" "$1"
git -C "$m" checkout -B "$1" FETCH_HEAD
git -C "$m" submodule init
git -C "$m" submodule update --init --recursive
EOS

  if [ "${#skipped[@]}" -gt 0 ]; then
    echo "⚠ vm_push_branch : sans HEAD local, donc non bundlés (la VM les prend à leur URL) : ${skipped[*]}" >&2
  fi
  echo "✓ vm_push_branch : « $branch » + ${#subs[@]} sous-module(s) → VM"
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
