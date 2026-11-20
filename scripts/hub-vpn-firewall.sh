#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# =============================================================================
# POULIDOR — Cloisonnement du VPN WireGuard du HUB (defense-in-depth)
# =============================================================================
# Objectif : les clients VPN (wg0) peuvent atteindre le HUB et les applications
# via leurs ports publiés (DNAT Docker), mais RIEN d'autre : pas le LAN, pas
# les réseaux Docker internes (hub-db :5432, bridges des apps…), pas l'hôte
# lui-même (SSH, services locaux).
#
# Pourquoi : le split tunnel côté client (AllowedIPs = hub/32 dans les .conf
# générés par le HUB) est une simple convention — un client édité peut router
# 0.0.0.0/0 dans le tunnel. Avec net.ipv4.ip_forward=1 et une politique
# FORWARD ACCEPT (constaté sur l'hôte), rien ne l'en empêche côté serveur.
#
# Règles appliquées (tables filter, IPv4 — wg0 n'a pas d'adressage IPv6) :
#   FORWARD / DOCKER-USER :
#     1. -i wg0 --ctstate DNAT  -j ACCEPT   → ports publiés (hub + apps)
#     2. -i wg0                 -j DROP     → tout le reste (LAN, bridges…)
#   INPUT :
#     1. -i wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
#     2. -i wg0 -p icmp --icmp-type echo-request -j ACCEPT  → ping 198.51.100.50 (diag)
#     3. -i wg0 -j DROP                     → protège l'hôte (SSH, services locaux)
#
# Idempotent : purge nos règles (marquées -m comment) puis les réinsère dans
# le bon ordre. Relançable sans risque.
#
# Installation (manuelle — pas de chemin automatisé install.sh) :
#   sudo cp scripts/hub-vpn-firewall.sh /usr/local/sbin/
#   sudo chmod +x /usr/local/sbin/hub-vpn-firewall.sh   # (mode git 100755 :
#     cp ne pose PAS le bit +x — sans lui, systemd échoue en 203/EXEC)
#   sudo cp scripts/systemd/hub-vpn-firewall.service /etc/systemd/system/
#   sudo systemctl daemon-reload && sudo systemctl enable --now hub-vpn-firewall
#
# Usage :
#   sudo hub-vpn-firewall.sh           # applique les règles
#   sudo hub-vpn-firewall.sh status    # affiche les règles en place
# =============================================================================
set -euo pipefail

IPT="$(command -v iptables || true)"
if [ -z "$IPT" ]; then
    echo "✗ iptables introuvable (installer iptables)." >&2
    exit 1
fi

WG_IF="wg0"
COMMENT="poulidor-vpn-gateway"

# Chaîne DOCKER-USER : créée par Docker, mais on la crée au cas où (docker
# arrêté/absent au moment de l'exécution — Docker la recréera sans la vider).
if ! "$IPT" -nL DOCKER-USER &>/dev/null; then
    "$IPT" -N DOCKER-USER
    # Docker place le jump DOCKER-USER en tête de FORWARD ; sinon on le fait.
    if ! "$IPT" -C FORWARD -j DOCKER-USER 2>/dev/null; then
        "$IPT" -I FORWARD 1 -j DOCKER-USER
    fi
fi

# Purge idempotente : retire toutes nos règles (le -D matche le comment).
purge_rule() { # purge_rule <chain> <spec...>
    local chain="$1"; shift
    while "$IPT" -D "$chain" "$@" -m comment --comment "$COMMENT" 2>/dev/null; do :; done
}

purge_rule DOCKER-USER -i "$WG_IF" -j DROP
purge_rule DOCKER-USER -i "$WG_IF" -m conntrack --ctstate DNAT -j ACCEPT
purge_rule INPUT       -i "$WG_IF" -j DROP
purge_rule INPUT       -i "$WG_IF" -p icmp --icmp-type echo-request -j ACCEPT
purge_rule INPUT       -i "$WG_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Insertion dans l'ordre inverse (chaque -I 1 pousse les précédentes vers le bas).
# Ordre final dans DOCKER-USER : [ACCEPT DNAT] puis [DROP].
# Ordre final dans INPUT       : [ESTABLISHED] [ICMP] [DROP].
"$IPT" -I DOCKER-USER 1 -i "$WG_IF" -j DROP \
    -m comment --comment "$COMMENT"
"$IPT" -I DOCKER-USER 1 -i "$WG_IF" -m conntrack --ctstate DNAT -j ACCEPT \
    -m comment --comment "$COMMENT"

"$IPT" -I INPUT 1 -i "$WG_IF" -j DROP \
    -m comment --comment "$COMMENT"
"$IPT" -I INPUT 1 -i "$WG_IF" -p icmp --icmp-type echo-request -j ACCEPT \
    -m comment --comment "$COMMENT"
"$IPT" -I INPUT 1 -i "$WG_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT \
    -m comment --comment "$COMMENT"

if [ "${1:-}" = "status" ]; then
    echo "── DOCKER-USER ──"
    "$IPT" -L DOCKER-USER -n --line-numbers
    echo "── INPUT (règles wg0) ──"
    # -v obligatoire : sans lui, iptables -L -n n'affiche PAS la colonne « in »
    # (interface) — le grep wg0 ne matchait rien et laissait croire que les
    # règles INPUT étaient absentes alors qu'elles étaient appliquées.
    "$IPT" -L INPUT -n -v --line-numbers | grep -E '(^Chain|wg0)' || true
else
    echo "✓ Cloisonnement VPN appliqué ($WG_IF → DNAT uniquement : hub + apps)"
fi
