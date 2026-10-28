# Notice — Coffre hubctl piloté depuis l'interface HUB

**Date** : 28 octobre 2026
**Versions concernées** : hubctl **0.16.0** · HUB_base **3.77.1** · POULIDOR **0.77.0**
**Public** : administrateurs du parc POULIDOR
**Spec détaillée** : `docs/superpowers/specs/2026-10-28-coffre-web-ui-design.md`

---

## 1 · De quoi parle-t-on ?

Le **coffre** est la sauvegarde chiffrée du parc : il copie vers lui-même (fichier `parc.vault.enc`, chiffré) tous les `.env` (hub + apps), les secrets (`HUB_base/secrets/`), un dump des tables critiques de la base (utilisateurs, apps, service accounts…) et déclenche la réplication PRA sur support externe. Sa règle d'or : **il ne modifie jamais le disque** — c'est une capture, pas une synchronisation.

**Nouveauté (octobre 2026)** : le coffre était jusque-là pilotable uniquement en CLI sur le serveur (`./hubctl vault …`, menu TUI). Il est désormais **consultable et actionnable depuis l'interface web du HUB**, sans ouvrir de terminal :

- voir l'état du coffre (verrouillage, dernière sauvegarde, taille, contenu, PRA) ;
- voir les **divergences** (les `.env` d'apps modifiés depuis la dernière sauvegarde) ;
- **déclencher une sauvegarde** en un clic.

Les opérations destructrices ou sensibles (**restauration, import, export en clair, changement de passphrase**) restent volontairement en CLI — voir §5.

## 2 · Comment ça marche (architecture)

```
Navigateur admin
   │  Admin → Sauvegardes → Coffre          (JWT admin)
   ▼
HUB_base (conteneur hub-api)
   │  GET/POST /api/admin/vault/status|backup
   │  proxy HTTP + header X-Atelier-Token    (timeout 120 s, audit VAULT_BACKUP)
   ▼
hubctl-atelier (mini-serveur hôte, systemd)
   │  172.17.0.1:8777 — invisible du LAN, auth token constant-time
   │  GET /vault/status · POST /vault/backup  (lock, garde 110 s)
   ▼
hubctl (VaultManager)
   │  lecture/check_divergence · backup_all (disque → coffre) + réplication PRA
   ▼
coffre chiffré  hubctl_src/hubctl_cli/vault/parc.vault.enc (+ .bak)
```

Points clés :

- **Le coffre et ses secrets ne quittent jamais le host.** Le conteneur HUB ne voit ni le fichier chiffré, ni la clé, ni aucun contenu déchiffré — l'API ne renvoie que des états et des compteurs.
- **Double barrière d'authentification** : session admin du HUB (JWT) côté web, token partagé (`X-Atelier-Token`) entre le conteneur et le service hôte.
- Le service hôte est **le seul** à écrire dans le coffre, sérialisé (un seul backup à la fois, `409` sinon).

## 3 · Installation / activation du service

Le pont UI ↔ coffre nécessite le service hôte `hubctl-atelier` (systemd). Trois cas :

### 3.1 Nouvelle installation du hub — **automatique, rien à faire**

`install.sh` (Phase 3) lance `./hubctl init` — qui crée le token et prépare le coffre — puis copie l'unit dans `/etc/systemd/system/` et active le service. À la fin de l'installation, le service tourne.

### 3.2 Hub déjà installé (mise à jour vers ≥ 0.77.0) — **une commande**

```bash
./hubctl init
```

L'étape `Service hôte hubctl-atelier` : crée le token s'il n'existe pas, le copie vers `HUB_base/secrets/`, installe l'unit et active le service. Le `sudo` demandera ton mot de passe (une fois). Idempotent : rejouable sans risque.

### 3.3 Sans passer par `init` — **les 3 commandes manuelles**

```bash
mkdir -p ~/.config/hubctl
[ -s ~/.config/hubctl/atelier_token ] || openssl rand -hex 32 > ~/.config/hubctl/atelier_token
chmod 600 ~/.config/hubctl/atelier_token
cp ~/.config/hubctl/atelier_token ~/MyCOMPANY/HUB_stack/POULIDOR/HUB_base/secrets/atelier_token

sudo cp hubctl_src/packaging/hubctl-atelier.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hubctl-atelier
```

### 3.4 Vérifier que tout est en place

```bash
systemctl status hubctl-atelier          # active (running)
curl -s http://172.17.0.1:8777/health    # {"status": "ok"} (sans auth)
```

Puis dans l'UI : **Admin → Sauvegardes → Coffre** — le bandeau doit afficher « Déverrouillé », la dernière sauvegarde et (éventuellement) les divergences.

> **Le token doit être identique des deux côtés** : `~/.config/hubctl/atelier_token` (lu par le service hôte) et `HUB_base/secrets/atelier_token` (monté dans le conteneur, lu par le proxy). `./hubctl init` garantit cette cohérence ; si tu régénères l'un, régénère l'autre puis `make -C HUB_base up-prod` pour recharger le montage.

## 4 · Utilisation au quotidien (interface)

**Où** : page **Admin → onglet Sauvegardes → workspace « Coffre hubctl »** (4ᵉ workspace, à côté de Applications / Snapshots / Environnement).

Ce que tu y vois :

| Élément | Signification |
|---|---|
| Badge verrouillage | « Déverrouillé » (clé locale OK) ou « Verrouillé » (clé `parc.vault.key` absente/invalide) |
| Dernière sauvegarde | Date de modification de `parc.vault.enc` (mtime) |
| Répartition | Nombre d'.env, fichiers secrets, apps, présence du dump DB |
| Divergences | Badges par app : le `.env` disque a changé depuis la dernière capture — cliquer ouvre la vue santé des apps |
| PRA | Emplacement de réplication configuré (ou « non configuré ») |
| Bouton « Sauvegarder maintenant » | Confirmation → sauvegarde (peut prendre jusqu'à ~2 min : dump DB + copie PRA) → toast de résultat |

Comportements à connaître :

- **Divergence = informatif.** Ce n'est pas une erreur : c'est le signal « sauvegarde recommandée ». Un backup à jour n'écrase rien (« ✓ Coffre à jour »).
- **La sauvegarde ne touche jamais le disque** (ni `.env`, ni conteneurs). Elle copie disque → coffre et relance la réplication PRA.
- **Un seul backup à la fois** : un second déclenchement reçoit « backup déjà en cours » (toast jaune).
- **Échec PRA ≠ échec de sauvegarde** : le coffre est à jour ; la copie externe est en échec (toast orange). À traiter rapidement, c'est ta disaster-recovery.
- **Service hôte arrêté** : le bloc affiche une alerte et désactive le bouton — le reste de l'onglet Sauvegardes fonctionne normalement.
- Pas de rechargement automatique : le statut se charge à l'ouverture du workspace et se rafraîchit après chaque action (choix de stabilité/performance).

## 5 · Ce qui reste en CLI (volontairement)

Les opérations destructrices ne sont **pas** exposées à l'interface :

```bash
./hubctl vault restore        # restaure .env + secrets + DB depuis le coffre (PRA / réinstallation)
./hubctl vault import <src>   # remplace le coffre par un autre
./hubctl vault export <dest>  # export du coffre (validation MAGIC + .bak)
./hubctl vault app list       # apps du coffre (git_url + version)
./hubctl vault app set-url …  # corrige le git_url d'une app
./hubctl pra-restore          # pipeline complet de sinistre depuis le kit PRA
```

Rappel du cycle : la **sauvegarde** (disque → coffre) est automatique au démarrage de hubctl et via l'UI ; la **restauration** (coffre → disque) est un chemin explicite de PRA/réinstallation, pas un correctif ordinaire.

## 6 · Sécurité

- Bind du service hôte sur **172.17.0.1** (passerelle docker0) : joignable uniquement des conteneurs du host, **invisible du LAN** ; le token `X-Atelier-Token` (comparaison constant-time) est le second garde-fou.
- **Aucun secret dans l'API web** : le proxy ne renvoie que des états/compteurs ; pas de lecture de contenu déchiffré.
- Unit systemd durcie : `ProtectSystem=strict` avec `ReadWritePaths` limité **au seul répertoire du coffre** (la seule écriture du serveur est le backup), `NoNewPrivileges`, `ProtectHome=read-only`, etc.
- Chaque sauvegarde déclenchée via l'UI laisse une trace dans l'**audit** du HUB (action `VAULT_BACKUP`, avec résultat).
- La clé du coffre (`parc.vault.key`) vit en clair à côté du coffre, **par design assumé** : le coffre est un filet de sauvegarde, pas une frontière de sécurité. Elle est répliquée sur le kit PRA.

## 7 · Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| Alerte « service hôte injoignable » dans l'UI | `hubctl-atelier` arrêté ou jamais installé | `systemctl status hubctl-atelier` ; si absent : §3.2/3.3 ; logs : `journalctl -u hubctl-atelier -n 50` |
| Toast « backup déjà en cours » (409) | Un backup tourne (UI, TUI ou démarrage hubctl) | Attendre la fin — c'est un verrou, pas une erreur |
| Badge « Verrouillé » | Clé locale absente/invalide (`parc.vault.key`) | Restaurer la clé depuis le kit PRA ou `./hubctl vault` (passphrase en repli) |
| 503 « Token atelier absent/illisible côté Hub » | `HUB_base/secrets/atelier_token` absent/divergent | Resynchroniser depuis `~/.config/hubctl/atelier_token` puis `make -C HUB_base up-prod` |
| 502 « Réponse invalide du service atelier hôte » | Version du service hôte trop ancienne (routes vault absentes) | `git -C hubctl_src pull` puis `sudo systemctl restart hubctl-atelier` |
| Toast orange « réplication PRA en échec » | Copie externe KO (support absent, plein…) | Vérifier l'emplacement PRA (`pra_config`), relancer un backup une fois corrigé |
| Coffre « à jour » mais un `.env` vient de changer | Normal : divergence calculée à la consultation | Les divergences réapparaissent au prochain chargement du workspace |

## 8 · Fichiers & références

| Quoi | Où |
|---|---|
| Coffre + clé | `hubctl_src/hubctl_cli/vault/parc.vault.enc` (+ `.bak`, `parc.vault.key`) — gitignés |
| Token de service | `~/.config/hubctl/atelier_token` ↔ `HUB_base/secrets/atelier_token` |
| Serveur hôte (code) | `hubctl_src/hubctl_cli/atelier_serve.py` |
| Unit systemd | `hubctl_src/packaging/hubctl-atelier.service` → `/etc/systemd/system/` |
| Proxy HUB | `HUB_base/hub/app/routes/vault.py` (`/api/admin/vault/*`) |
| UI | `HUB_base/frontend/public/js/modules/admin-vault.js` |
| Install auto | `install.sh` Phase 3c + `hubctl init` (`actions.py::_ensure_atelier_service`) |
| Spec / plan | `docs/superpowers/specs/2026-10-28-coffre-web-ui-design.md` |
