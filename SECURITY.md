# Politique de sécurité

## Signaler une vulnérabilité

**Ne pas ouvrir d'issue publique.** Utilisez le signalement privé de
vulnérabilités GitHub (onglet *Security* → *Report a vulnerability*) ou le
contact privé des mainteneurs, en incluant :

1. Une description claire du problème.
2. Les versions concernées (champ `VERSION` des dépôts) ou les plages de commits.
3. Les étapes de reproduction ou une preuve de concept.
4. Une atténuation suggérée, le cas échéant.

- Accusé de réception visé : **72 h** ; évaluation : **7 jours**.
- Divulgation coordonnée : le rapporteur est crédité après correction, sauf
  demande contraire.

## Périmètre

Sont concernés l'ensemble des composants du stack : le Hub
([HUB_base](https://github.com/POULIDOR-Audit-Developpement/HUB_base)) —
backend FastAPI, frontend React, PKI interne, routage DNS/SNI, flux
d'authentification (JWT RS256, M2M) —, le socle
([HUBsocle](https://github.com/POULIDOR-Audit-Developpement/HUBsocle)), le
template d'applications
([HUBapp_TEMPLATE_base](https://github.com/POULIDOR-Audit-Developpement/HUBapp_TEMPLATE_base)),
le design system ([HUBCSS](https://github.com/POULIDOR-Audit-Developpement/HUBCSS)),
la CLI ([Hubctl](https://github.com/POULIDOR-Audit-Developpement/Hubctl)) et le
serveur MCP ([hub-mcp](https://github.com/POULIDOR-Audit-Developpement/hub-mcp)),
ainsi que les images Docker publiées.

## Versions supportées

La dernière version publiée de chaque composant est supportée. Les versions
antérieures ne reçoivent de correctifs que pour des vulnérabilités critiques.
