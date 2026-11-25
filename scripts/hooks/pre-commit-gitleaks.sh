#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Scan gitleaks des fichiers stagés — bloquant si secret détecté, et bloquant
# si gitleaks est absent (contournement explicite : GITLEAKS_SKIP=1).
# Test : scripts/tests/test_pre_commit_gitleaks.sh
if command -v gitleaks >/dev/null 2>&1; then
  # Pas d'option -q dans gitleaks 8.30.1 : silencieux quand rien n'est trouvé,
  # avertissements et erreurs de gitleaks visibles sinon.
  gitleaks git --pre-commit --staged --no-banner --no-color --log-level warn
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "✗ gitleaks : secret détecté dans les fichiers stagés — commit refusé."
    echo "  Inspectez : gitleaks dir <chemin> — exemption justifiée : 'gitleaks:allow' sur la ligne."
    echo "  Rien trouvé à l'inspection ? gitleaks lui-même est en erreur (même code retour) : voir son message ci-dessus."
    exit 1
  elif [ "$rc" -ne 0 ]; then
    echo "⚠ gitleaks a échoué (rc=$rc) — commit autorisé, vérifiez l'installation."
  fi
else
  if [ "${GITLEAKS_SKIP:-}" = "1" ]; then
    echo "⚠ GITLEAKS_SKIP=1 : gitleaks absent, scan de secrets contourné — commit autorisé."
    exit 0
  fi
  echo "✗ gitleaks absent : commit refusé (aucun scan de secrets)."
  echo "  Installation : https://github.com/gitleaks/gitleaks — vérifier avec « gitleaks version »."
  echo "  contournement explicite : GITLEAKS_SKIP=1"
  exit 1
fi
exit 0
