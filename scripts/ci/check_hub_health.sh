#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 POULIDOR Audit & Développement (Valérian Poulidor)

# check_hub_health.sh <port> [port...] — CI méta POULIDOR (runner self-hosted)
# Vérifie que chaque hub répond /api/health avec status=healthy.
set -uo pipefail
[ $# -lt 1 ] && { echo "usage: $0 <port> [port...]"; exit 2; }
FAIL=0
for port in "$@"; do
  R=$(curl -sf -m 5 "http://localhost:$port/api/health" 2>/dev/null | grep -o '"status":"[a-z]*"' | head -1)
  if [ "$R" = '"status":"healthy"' ]; then
    echo "✅ hub :$port healthy"
  else
    echo "❌ hub :$port injoignable ou unhealthy (reçu: ${R:-rien})"; FAIL=1
  fi
done
[ "$FAIL" = 0 ] && echo "✅ Tous les hubs sont healthy" || echo "⛔ ÉCHEC health hubs"
exit $FAIL
