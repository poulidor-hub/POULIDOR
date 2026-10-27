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
