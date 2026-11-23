---
name: vm-lab
description: Labos VM Debian 12 persistants pour POULIDOR — reproduire des bugs en environnement propre, tester une branche sur VM vierge, simuler un serveur client réel en injectant ses données (kit PRA, archive park-export, snapshot) pour diagnostic support. Triggers : "labo", "VM de test", "reproduis ce bug en env propre", "simule le serveur du client X", "restore ce kit PRA / park-export sans toucher la prod", "teste cette branche sur une VM vierge", "machine Debian propre".
argument-hint: 'But du labo (reproduire bug X / tester branche Y / simuler client Z + artefact)'
---

# VM Lab

Labos VM **Debian 12 persistants et nommés** pour reproduire, diagnostiquer et valider des environnements serveurs complets du parc — sans toucher à la prod locale ni aux archives de preuves.

## Où vivrent les choses

| Chemin | Rôle | Statut |
|---|---|---|
| `build/vm-lab/<nom>/` | **Périmètre STRICT du lab** — 1 labo = 1 dossier = 1 VM + `journal.md` | crées/détruis ici |
| `build/vm-lab/base/` | Image Debian 12 (hardlink auto) | partage, ne pas toucher |
| `build/fresh-install/` | **Archive de preuves du test initial** (rapports, runs 23/23) | **INTERDIT d'y toucher** |
| `scripts/lib/vm-lab.sh` | L'outil (`create/start/ssh/push/inject/restore/list/destroy`) | — |
| `scripts/lib/vm-debian12.sh` | Primitives QEMU/cloud-init (sourcée par vm-lab) | — |

## Prérequis (hôte)

- `qemu-kvm`, `qemu-utils`, `cloud-image-utils` installés ; `/dev/kvm` présent
- Image de base : auto-trouvée (hardlink) depuis `build/fresh-install/base/` si elle existe, sinon vm-lab affiche la commande `wget` exacte
- Agent SSH actif (`ssh-add -l` non vide) pour les clones GitHub depuis la VM
- Disque : garde-fous auto (≤ 2 labos, ≥ 20 Go libres) — ne pas contourner

## Recettes

### Recette 1 — Valider une installation de zéro (pre-release)

**Ne PAS utiliser vm-lab** (jetable par nature) → lancer le harness :

```bash
scripts/test-fresh-install.sh [--branch <branche>] [--keep]
# 23 assertions : clone, install.sh, santé Hub, login, hubctl, app bout-en-bout
```

### Recette 2 — Reproduire un bug / tester une branche en env propre

```bash
scripts/lib/vm-lab.sh create repro-<bug>          # VM Debian 12 neuve (~2-3 min)
scripts/lib/vm-lab.sh ssh repro-<bug> 'ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts'
scripts/lib/vm-lab.sh ssh repro-<bug>             # puis : git clone --recurse-submodules … && sudo ./install.sh
scripts/lib/vm-lab.sh push repro-<bug> <branche>  # ou : pousser TA branche (bundles sous-modules inclus)
# … itérer librement (le labo persiste entre tes commandes/sessions) …
scripts/lib/vm-lab.sh destroy repro-<bug>         # quand fini — note le résultat au journal avant
```

Après un reboot de l'hôte : `start <nom>` relance la VM existante.

### Recette 3 — Simuler un serveur client réel (diagnostic support)

```bash
scripts/lib/vm-lab.sh create client-<nom>
scripts/lib/vm-lab.sh ssh client-<nom>            # installer le parc : clone + sudo ./install.sh
scripts/lib/vm-lab.sh restore client-<nom> /chemin/kit-pra-*.tar.gz   # ou park-*.tar.gz
# → passphrase demandée à l'HUMAIN (jamais stockée, pipée une fois)
# snapshot seul / artefact exotique : lab_inject puis restauration ciblée via ssh
```

Puis diagnostic libre : santé (`curl localhost:8000/api/health`), apps du client (`/api/apps/`), logs (`docker compose logs`), configs. **Tout ce qui est observé va au `journal.md` du labo.**

## Règles

1. **Journal obligatoire** : chaque labo a `build/vm-lab/<nom>/journal.md` — note but, événements, conclusions. Archive-le (copie hors du labo) avant `destroy`.
2. **Passphrases** : toujours demandées à l'humain, pipées, jamais écrites (journal, scripts, commit interdits).
3. **Périmètre** : `destroy` ne touche que `build/vm-lab/<nom>` — ne jamais y déroger, jamais toucher `build/fresh-install/`.
4. **Hygiène disque** : `list` avant/après ; détruis les labos obsolètes (⚠ >7j) ; max 2 labos simultanés.
5. **Pas de secrets clients persistés** dans les labos au-delà du nécessaire — destroy après diagnostic.
6. **Petit nombre d'abord** : tout test/benchmark en volume (injection de données, restore, run de perf, génération en masse) commence par un run à échelle réduite — même workflow, petit nombre (ex. 5 items, 1 table, 1 itération) — pour valider la chaîne bout-en-bout. On ne monte au volume cible qu'après un run réduit vert : un run massif qui échoue sur une erreur détectable à n=5, c'est du temps perdu.

## Pièges capitalisés (test fresh-install, 17 août 2026)

| Piège | Parade |
|---|---|
| SSH monte avant la fin de cloud-init (git absent juste après boot) | `vm_create` attend `cloud-init status --wait` — ne pas court-circuiter |
| Host key GitHub absente d'une machine neuve → clone échoue | `ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts` avant le clone |
| `docker compose restart` ne recharge PAS le `.env` | utiliser `docker compose up -d <svc>` (recreate) |
| `allocate-ports` 403 depuis un subnet non whitelisté | `APP_WHITELIST_NETWORKS` dans `HUB_base/.env` + recreate hub-api (init détecte le LAN depuis v0.5.2) |
| `INITIALISE.py --profile` interactif | `--yes` (template ≥ v2.14.0) |
| `install.sh`/`hubctl init` prompts | réponses par défaut pipées (`printf '\n\n\n\n'`) |
| Runs longs tués par le timeout du lanceur | `setsid nohup … < /dev/null &` + polling du rapport |
| Run massif (benchmark/injection/restore) lancé d'emblée → échoue en pleine exécution sur une erreur de workflow | Run réduit d'abord (petit nombre : 5 items / 1 table / 1 itération) pour valider le workflow, puis montée au volume cible (règle 6) |

## Limites actuelles

- VM unique (pas de multi-VM/réseau interne — évolution prévue si besoin réel)
- Pas d'expiration auto (alerte `list` >7j seulement)
- Réseau SLIRP : la VM voit `10.0.2.15`, l'hôte `10.0.2.2` — simule un serveur monoposte
