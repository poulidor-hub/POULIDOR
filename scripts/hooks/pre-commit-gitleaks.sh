#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Scan gitleaks des fichiers stagés — bloquant si secret détecté.
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --pre-commit --staged -q
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "✗ gitleaks : secret détecté dans les fichiers stagés — commit refusé."
    echo "  Inspectez : gitleaks dir <chemin> — exemption justifiée : 'gitleaks:allow' sur la ligne."
    exit 1
  elif [ "$rc" -ne 0 ]; then
    echo "⚠ gitleaks a échoué (rc=$rc) — commit autorisé, vérifiez l'installation."
  fi
else
  echo "⚠ gitleaks absent : pas de scan de secrets (https://github.com/gitleaks/gitleaks)"
fi
exit 0
