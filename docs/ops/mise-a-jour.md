# Mise à jour du parc — la routine officielle

> Plan « unification des mises à jour » (oct. 2026) — remplace toutes les
> procédures antérieures. Spec : `docs/superpowers/specs/2026-10-27-unification-updates-design.md`.

## La routine par serveur (dans l'ordre)

```bash
cd <racine-du-parc>                # le méta-repo POULIDOR

hubctl doctor                      # 1. diagnostic (rapport seul, exit 1 si problème)
hubctl doctor --fix                #    si besoin : réalignements sûrs (confirmation, ou --yes)
hubctl --prod update hub           # 2. le Hub d'abord — BLOQUANT
hubctl --prod update all           #    ou d'un coup : hub + toutes les apps (hub d'abord)
./hub.sh status                    # 3. état + version déployée
```

Mode dev : `hubctl --dev update hub` (cible `make up-dev`). `--dry-run`
existe partout : `hubctl --dry-run update hub`, `./hub.sh update --dry-run`.

## Rôles (qui fait quoi)

| Outil | Rôle |
|---|---|
| `hubctl update <hub\|app\|all>` | **LA** commande de mise à jour (pré-checks, rollback, `--dev`) |
| `hubctl doctor [--fix] [--yes]` | diagnostic des clones + réalignements sûrs |
| `hub.sh` | exploitation infra : start/stop/restart/logs/status/selftest/rebuild |
| `hub.sh update` | simple délégation → `hubctl update hub` |
| `update-hub.sh` | **déprécié** (warning), suppression prévue |
| `make build` / `make up` | build/exécution locale — ne mettent jamais à jour |

## Sémantique de `update hub`

Le **méta-repo POULIDOR est la source de vérité** : `update hub` tire le méta
(`--ff-only`), aligne les sous-modules (`submodule update`), puis build → up →
health. En cas d'échec build/up/health : rollback du pointeur méta **et** du
sous-module (+ snapshot DB). Le Hub est **bloquant** dans `update all` : s'il
échoue, les apps ne sont pas touchées.

> Couverture des builds : `update hub` rebuild HUB_base (`make build` +
> `up-prod`) ; `hubctl` est un script bash (aucun build). Une release qui avance
> **HUBsocle** (images `poulidor/socle-api|web`) exige un complément :
> `hubctl socle build` puis rebuild des apps consommatrices — hors flux `update hub`.

## Mise à jour via l'interface Hub (hub 0.82+ / hubctl 0.18+ / HUB_base 3.85+)

Pour les administrateurs : un **badge orange** à côté de la version dans la navbar
signale qu'un composant du socle est en avance sur `origin/main`. Le bouton
« Mettre à jour le Hub et le socle » (admin → onglet **Mises à jour**) exécute
strictement `hubctl update hub` (mêmes pré-checks, même rollback) avec suivi live
du log et reconnexion automatique pendant le redémarrage du Hub.

- **Prérequis** : le service hôte `hubctl-update` doit tourner
  (`hubctl init` l'installe ; vérification :
  `curl -H "X-Atelier-Token: $(cat ~/.config/hubctl/atelier_token)" http://172.17.0.1:8778/health`).
- **Périmètre** : Hub + composants socle uniquement (méta + submodules). Les apps
  `APPS/` gardent leurs boutons individuels (page Santé des apps).
- **Arrêt manuel** : `systemctl stop hubctl-update` (le process spawn un enfant —
  ne pas tuer le PID nohup à la main, passer par systemd).
- **Voie de secours** : si l'UI est en échec (service hôte down, badge
  « service indisponible »), revenir à la routine CLI ci-dessus ; l'état du job
  reste lisible dans `~/.config/hubctl/update_state.json` et les logs dans
  `~/.config/hubctl/update_logs/`.

## Transition purge open source (méta 0.80.14+) — MIGRATION UNIQUE

> Les déploiements créés **avant le 4 novembre 2026** ne peuvent plus faire la
> routine ci-dessus directement : l'historique du parc a été réécrit (purge de
> secrets avant open source) et votre clone n'a plus d'ancêtre commun avec le
> remote. `hubctl --prod update hub` échouera (« histories divergentes »,
> sous-modules introuvables). **Le hub en production n'est pas impacté** :
> les conteneurs tournent indépendamment de git, et vos données (`.env*`,
> `APPS/`, `storage/`, `secrets/`, coffre, volumes) sont hors git.

Migration (une seule fois par serveur, ~15 min, données préservées) :

**1. Récupérer le script** — un `git pull` est impossible (historiques sans
ancêtre commun), mais `git fetch` seul fonctionne :

```bash
cd <racine-du-parc>
git fetch origin
mkdir -p scripts
git show origin/main:scripts/migration-oss.sh > scripts/migration-oss.sh
```

**2. Lancer la migration** — l'URL SSH/auth de votre déploiement est réutilisée
(toute erreur restaure automatiquement votre dépôt git d'origine) :

```bash
bash scripts/migration-oss.sh
./hub.sh up-prod                     # recréer si les images ont changé
./hubctl doctor                      # vérification complète
```

Le script renomme l'ancien `.git` (rollback trivial possible) et conserve
tous vos fichiers locaux. Après migration, la routine officielle ci-dessus
redevient la norme. Les apps privées (dépôts sous `APPS/`) ne sont pas
concernées : leurs dépôts n'ont pas été réécrits.


## Les interdits

1. **Jamais de `git push` depuis un clone dont l'historique diverge** —
   cela ressusciterait un ancien historique purgé sur les remotes.
2. **Jamais de `git pull` manuel dans un sous-module** (HUB_base, HUBCSS…) :
   passez par le méta (`hubctl update hub` / `git pull --ff-only` au méta).
3. **Jamais `docker compose down -v`** : détruire les volumes = détruire les données.
4. **Jamais de `doctor --fix` sur une branche non mergée** : le tooling refuse,
   ne forcez pas (`-D` manuel = perte possible de travail).

## Cas « historique réécrit » (ex. purge du 26/10/2026)

Symptôme : `update hub` échoue au pré-check `hub_base.aligned_origin`
(« historique divergent »), ou `git pull` refuse de fusionner.

Remède (par clone concerné) :

```bash
git -C HUB_base fetch origin --prune
git -C HUB_base checkout main
git -C HUB_base reset --hard origin/main
```

Un re-clone dans un dossier neuf fonctionne aussi (recopier alors `.env`,
`secrets/`, `certs/`, `storage/` — les données ne sont pas suivies par Git).

## Lien avec les releases

Toute release d'un composant (HUB_base, hubctl, HUBCSS…) passe par
`release-on-main` : bump VERSION + CHANGELOG, puis bump du **pointeur** dans
le méta-repo. C'est ce pointeur que `hubctl update hub` applique — la règle
« une release composant = une release méta » garantit que la mise à jour du
Hub est toujours reproductible côté serveur.
