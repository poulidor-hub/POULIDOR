#!/usr/bin/env bash
# =============================================================================
# POULIDOR — Réactivation du VPN WireGuard au boot (boot hook hôte)
# =============================================================================
# Rôle : après un reboot de l'hôte, le conteneur hub-wireguard ne redémarre
# PAS tout seul (restart: "no" voulu côté HUB_base — cycle de vie géré par
# `hubctl vpn`). Cette unité comble le chaînon manquant : elle attend que
# hub-db soit prêt puis lance `hubctl vpn sync`, qui réconcilie l'état réel
# du conteneur avec vpn_enabled en DB :
#   vpn_enabled=true  → conteneur démarré (tunnel wg0 actif)
#   vpn_enabled=false → conteneur arrêté (no-op s'il l'est déjà)
#
# Installé avec l'unité scripts/systemd/hub-vpn-sync.service :
#   sudo cp scripts/hub-vpn-boot-sync.sh /usr/local/sbin/
#   sudo cp scripts/systemd/hub-vpn-sync.service /etc/systemd/system/
#   sudo systemctl daemon-reload && sudo systemctl enable --now hub-vpn-sync
#
# Idempotent ; silencieux (exit 0) si le Hub n'est pas installé (pas de
# conteneur hub-db). Relançable sans risque (hubctl vpn sync est idempotent).
# =============================================================================
set -uo pipefail

# Répertoire du dépôt POULIDOR — adapter à l'installation si différent
# (ou surcharger via Environment=POULIDOR_DIR=... dans l'unité).
POULIDOR_DIR="${POULIDOR_DIR:-/home/kkleskk/MyCOMPANY/HUB_stack/POULIDOR}"

log() { echo "[hub-vpn-sync] $*"; }

# 1. Hub installé ? Sans conteneur hub-db, rien à faire — exit 0 pour ne pas
#    polluer systemd d'échecs sur les machines sans Hub.
if ! docker inspect hub-db >/dev/null 2>&1; then
    log "hub-db absent — Hub non installé, rien à faire."
    exit 0
fi

# 2. Attendre que hub-db soit prêt : au boot, Docker vient tout juste de
#    redémarrer les conteneurs et `hubctl vpn sync` abandonne si la DB est
#    injoignable. 30 essais × 10 s = 5 min max.
for i in $(seq 1 30); do
    if docker exec hub-db pg_isready -U hubadmin -d hub_auth >/dev/null 2>&1; then
        log "hub-db prêt (essai ${i}/30)."
        break
    fi
    if [ "$i" -eq 30 ]; then
        log "hub-db injoignable après 5 min — abandon."
        exit 1
    fi
    sleep 10
done

# 3. Réconcilier l'état du conteneur VPN avec vpn_enabled (DB).
if [ ! -x "$POULIDOR_DIR/hubctl" ]; then
    log "hubctl introuvable dans $POULIDOR_DIR — vérifier POULIDOR_DIR."
    exit 1
fi
log "lancement : hubctl vpn sync (dans $POULIDOR_DIR)"
cd "$POULIDOR_DIR" || { log "impossible d'entrer dans $POULIDOR_DIR"; exit 1; }
exec ./hubctl vpn sync
