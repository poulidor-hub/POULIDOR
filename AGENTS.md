# AGENTS — POULIDOR

## Release sur `main`

Avant **tout** `git push` (ou merge) vers la branche `main` de n'importe quel dépôt
du parc (méta-repo POULIDOR comme composants), tu **dois** invoquer le skill
`release-on-main` et suivre sa procédure :

1. **Toujours** : déduire le niveau de bump (fix→patch / feat→minor / breaking→major),
   incrémenter la version et mettre à jour le CHANGELOG **technique**.
2. **Sur demande** : si l'app est publiée, rédiger le patchnote utilisateur dans le
   même CHANGELOG.

Ne pousse **jamais** sur `main` sans version incrémentée ni entrée CHANGELOG.
