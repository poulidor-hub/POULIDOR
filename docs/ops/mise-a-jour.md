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

## Réécriture d'historique : migration du déploiement (méta 0.80.14+)

> Chaque réécriture de l'historique du parc — la purge open source du
> **4 novembre 2026**, puis la réécriture qui précède son passage en public —
> met dans ce cas tout déploiement créé **avant** elle : la routine ci-dessus
> ne marche plus directement. Votre clone n'a plus d'ancêtre commun avec le
> remote ; `hubctl --prod update hub` échouera (« histories divergentes »,
> sous-modules introuvables). **Le hub en production n'est pas impacté** : les
> conteneurs tournent indépendamment de git, et vos données (`.env*`, `APPS/`,
> `storage/`, `secrets/`, coffre, volumes) sont hors git.

Migration (une fois par serveur et par réécriture, ~15 min, données préservées) :

**1. Récupérer le script** — un `git pull` est impossible (historiques sans
ancêtre commun), mais `git fetch` seul fonctionne :

```bash
cd <racine-du-parc>
git fetch origin
mkdir -p scripts
git show origin/main:scripts/migration-oss.sh > scripts/migration-oss.sh
```

**2. Lancer la migration** — l'URL SSH/auth de votre déploiement est réutilisée
(toute erreur restaure automatiquement votre dépôt git d'origine). Les
sous-modules étant en HTTPS dans le `.gitmodules`, un déploiement par clé de
déploiement (origin en SSH) les fait passer par la même clé :

```bash
bash scripts/migration-oss.sh
```

**3. Avant de relancer le Hub** — la valeur par défaut de `PHILIA_NG_DOMAIN`
(hôte du proxy) change avec cette version : si votre `.env` ne la définit pas,
ajoutez-y explicitement le domaine que votre proxy sert aujourd'hui, sinon
`server_name` et le certificat émis ne correspondront plus.

```bash
./hub.sh up-prod                     # recréer si les images ont changé
./hubctl doctor                      # vérification complète
```

Le script renomme l'ancien `.git` (rollback trivial possible) et conserve
tous vos fichiers locaux. Après migration, la routine officielle ci-dessus
redevient la norme. Les apps de `APPS/` ne sont pas concernées : leurs dépôts
ne sont pas réécrits.


## Forks de déploiement : tirer SES propres mises à jour

> Le tooling (`hubctl update`, `update-submodules.sh`, `hubctl doctor`) tire tout
> du remote `origin` du méta et des sous-modules. Un fork de déploiement doit donc
> avoir **origin = son propre fork** (c'est lui qui porte ses updates) et
> **upstream = l'org officielle `POULIDOR-Audit-Developpement`** (rapatriement
> volontaire contrôlé). Modèle déjà en place sur `HUB_base`.

### Bascule d'un serveur (une fois par déploiement)

```bash
cd <racine-du-parc>                                  # branche main, arbre propre
scripts/fork-remotes.sh --fork-url git@github.com:<org>/POULIDOR.git --check
scripts/fork-remotes.sh --fork-url git@github.com:<org>/POULIDOR.git --dry-run
scripts/fork-remotes.sh --fork-url git@github.com:<org>/POULIDOR.git --yes
```

Le script :

- bascule `origin` du méta vers le fork et met l'**ancienne** origin en `upstream` ;
- bascule chaque sous-module forké (détection d'existence par `git ls-remote` ;
  un fork absent est **conservé sur l'officiel** avec un warning) ; l'URL du fork
  reprend le schéma de `--fork-url` (SSH ou HTTPS) — le `.gitmodules` officiel
  est en HTTPS, un fork privé reste donc accessible par clé ;
- pose une **surcharge locale** `submodule.<nom>.url` dans `.git/config` du méta :
  le `.gitmodules` versionné reste identique à l'officiel → **zéro conflit** au
  rapatriement amont ;
- affiche le récap des apps `APPS/*` (info : chaque app est un cas par déploiement,
  gérée par `app install` / le coffre).

Si un sous-module forké porte un **autre nom de repo** (ex. `HUB_base` forké en
`<org>/HUB`), passe le mapping explicite (répétable) :

```bash
scripts/fork-remotes.sh --fork-url git@github.com:<org>/POULIDOR.git \
  --sub HUB_base=git@github.com:<org>/HUB.git --yes
```

La routine de mise à jour reste **strictement identique** ensuite : `hubctl update
hub` tire désormais de ton origin, c'est-à-dire ton fork.

### Suivre l'amont officiel (rapatriement volontaire)

```bash
scripts/fork-remotes.sh --fork-url git@github.com:<org>/POULIDOR.git --pull-upstream
./hubctl update hub            # appliquer (build + health)
```

`--pull-upstream` fait, dans cet ordre imposé : fast-forward de chaque sous-module
forké depuis `upstream/main` **puis** fast-forward du méta — les pointeurs du méta
doivent exister dans les forks avant d'être avancés. Pushes **vers le fork
uniquement** ; toute divergence (WIP, historique divergent) est sautée avec un
warning, jamais fusionnée automatiquement.

### Garde-fous des forks

1. **Jamais de `git push` vers `upstream`** (l'org officielle) depuis un fork —
   `--pull-upstream` ne pousse que vers origin.
2. **Jamais de `git submodule sync`** après la bascule : il réécrirait les URLs
   officielles du `.gitmodules` par-dessus les surcharges du fork.
3. **`.git/config` n'est pas versionné** : après un re-clone du méta (PRA,
   migration OSS), **relancer le script** de bascule.
4. Après bascule, resynchroniser le coffre (`hubctl vault sync`) pour que les
   `git_url` des apps récapitulent les bons remotes.

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
