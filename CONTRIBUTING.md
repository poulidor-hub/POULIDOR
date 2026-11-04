# Guide de contribution — Le HUB

Merci de votre intérêt pour contribuer au **HUB**, édité par **POULIDOR Audit & Développement**.
Ce document décrit les règles que toute contribution (code, documentation, tests) doit respecter.

## 1. Cartographie des licences (à respecter absolument)

Le projet adopte une architecture à double périmètre de licence :

| Périmètre | Contenu | Licence |
|---|---|---|
| **Cœur du HUB** | API FastAPI, front SPA, orchestration, MCP, scripts d'infrastructure, CLI (`hubctl`) | **GNU AGPLv3** (voir [LICENSE](./LICENSE)) |
| **Gabarit d'application** (`HUBapp_TEMPLATE_base`) | Template des apps métiers | **MIT** (voir [LICENSE-TEMPLATE](./LICENSE-TEMPLATE)) |
| **Design System** (`HUBCSS`) | Composants et tokens partagés | **MIT** (voir [LICENSE-TEMPLATE](./LICENSE-TEMPLATE)) |

**Règle d'or :** toute nouvelle ligne de code ajoutée dans le Cœur du HUB est couverte par l'AGPLv3 ; toute contribution au gabarit ou au design system est couverte par la licence MIT. Ne déplacez jamais du code du gabarit/HUBCSS vers le Cœur (ou l'inverse) sans en discuter dans un ticket au préalable : cela changerait le régime de licence du code concerné.

## 2. Respect de l'architecture et du périmètre assumé

Le HUB suit une philosophie **local-first, léger et auditable** :

- **Pas de dépendances lourdes** : toute nouvelle dépendance (backend Python, frontend npm, binaire système) doit être justifiée dans la description de la Pull Request. Les dépendances additionnées au socle doivent être maintenues activement, sous licence compatible (pas de licence non libre dans le Cœur), et ne pas alourdir significativement le déploiement hors-ligne.
- **Pas de télémétrie ni d'appel réseau sortant non documenté** : le HUB fonctionne offline ; toute communication inter-apps passe par les mécanismes officiels (M2M discovery, notifications Hub).
- **Maintien des tests** : toute Pull Request doit garder la suite de tests verte (`pytest` backend, build front sans erreur). Un changement de comportement doit être couvert par un test ; un correctif de bug doit d'abord reproduire le bug en test.
- **Style des commits** : messages conventionnels et atomiques (`feat:`, `fix:`, `docs:`, `chore:`), une intention par commit.

## 3. Contribution sous CLA (obligatoire)

Le projet est distribué sous double licence (AGPLv3 open source / licence commerciale). Pour que le Mainteneur conserve la capacité de distribuer le projet selon ce modèle, **toute contribution est soumise au [CLA](./CLA.md)**.

Lors de votre première Pull Request (et à chaque PR si le CLA évolue), ajoutez **à la fin de la description de la PR** la mention exacte :

> `J'ai lu et j'accepte les termes du CLA (CLA.md) de ce dépôt.`

Une PR sans cette mention ne peut pas être fusionnée.

## 4. Marque et identité visuelle

La licence AGPLv3 couvre le **code source** uniquement. Les noms (« Le HUB », « POULIDOR Hub »), logos et éléments graphiques sont **exclus** de la licence : voir la [Politique de Marque (TRADEMARK.md)](./TRADEMARK.md). En particulier, tout fork redistribué publiquement doit changer de nom et retirer les logos officiels.

## 5. Processus de soumission

1. Ouvrez un ticket (issue) pour discuter tout changement notable **avant** de coder.
2. Créez une branche dédiée, isolée du travail des autres contributeurs.
3. Développez avec des commits atomiques, tests inclus.
4. Ouvrez la Pull Request avec : description du changement, justification des dépendances éventuelles, résultat des tests, et la mention d'acceptation du CLA.
5. Un mainteneur relit la PR ; les retours doivent être traités avant fusion.
