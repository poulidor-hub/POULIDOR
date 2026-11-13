#!/usr/bin/env bash
# parc-docker-maintenance — entretien Docker récurrent du parc POULIDOR
#
# Aucune purge Docker n'existe dans le parc : constat serveur, le build cache,
# les images inutilisées et les volumes orphelins (worktrees/branches mortes,
# app supprimée) s'accumulent (~138 Go de build cache récupérable, ~49 Go
# d'images, ~19 Go de volumes dangling).
# DÉFAUT = dry-run : rapport de ce qui serait purgé, aucune suppression.
#
# ⚠ les volumes DATA (et INCONNUE) supprimés ne sont pas sauvegardés :
#   leur suppression exige --include-vol-data. Les volumes attachés à un
#   container ne sont JAMAIS touchés (dangling=true + garde au rm).
#
# Usage :
#   parc-docker-maintenance.sh                            # dry-run : rapport seul
#   parc-docker-maintenance.sh --apply                    # purge, 20 Go de build cache conservés
#   parc-docker-maintenance.sh --apply --keep-cache 50    # purge, 50 Go conservés
#   parc-docker-maintenance.sh --apply --include-vol-data # purge aussi volumes DATA/INCONNUE ⚠
#   parc-docker-maintenance.sh --help
#
# Journalisation des volumes supprimés (--apply), fichier optionnel :
#   PARC_DOCKER_MAINTENANCE_LOG=/var/log/parc-docker-maintenance.log parc-docker-maintenance.sh --apply
set -euo pipefail

SCRIPT_NAME="parc-docker-maintenance"
KEEP_CACHE_GO=20
APPLY=0
INCLUDE_VOL_DATA=0
LOG_FILE="${PARC_DOCKER_MAINTENANCE_LOG:-}"

declare -A VOL_SIZE=()

die() { echo "❌ $SCRIPT_NAME: $*" >&2; exit 1; }
info() { echo "→ $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }

usage() { awk 'NR>1 && /^set /{exit} NR>1{sub(/^# ?/,""); print}' "$0"; }

command -v docker  >/dev/null || die "docker introuvable"
command -v python3 >/dev/null || die "python3 introuvable"
docker info >/dev/null 2>&1 || die "docker daemon injoignable (docker info a échoué)"

# --- classification des volumes dangling --------------------------------
# Ordre conservateur : DATA testée AVANT CACHE — un nom matchant les deux
# classes (ex. « target-data ») reste en DATA et exige --include-vol-data,
# jamais l'inverse (on ne détruit pas une base sous prétexte d'un « cache »
# dans le nom).
classify_volume() {
    if printf '%s' "$1" | grep -Eqi 'postgres-data|pgdata|uploads-data|logs-data|_data|-data$'; then
        echo "DATA"
    elif printf '%s' "$1" | grep -Eqi 'cargo|registry|target|tmp|cache|npm|pip'; then
        echo "CACHE"
    else
        echo "INCONNUE"
    fi
}

# --- tailles par volume (docker system df -v, section Volumes) ----------
load_volume_sizes() {
    local json
    if json="$(docker system df -v --format '{{json .Volumes}}' 2>/dev/null)" \
       && [ -n "$json" ] && [ "$json" != "null" ]; then
        while IFS=$'\t' read -r name size; do
            [ -n "$name" ] || continue
            VOL_SIZE["$name"]="$size"
        done < <(python3 - "$json" <<'EOF'
import json, sys
try:
    # stdin porte le code (heredoc) : les données arrivent par argv
    volumes = json.loads(sys.argv[1]) or []
except ValueError:
    volumes = []
for v in volumes:
    print(f"{v.get('Name', '')}\t{v.get('Size', '?')}")
EOF
        )
    fi
}

vol_size() { printf '%s' "${VOL_SIZE["$1"]:-?}"; }

count_lines() { awk 'NF{n++} END{print n+0}' <<< "$1"; }

list_dangling() { docker volume ls -qf dangling=true 2>/dev/null || true; }

log_line() {
    [ -n "$LOG_FILE" ] || return 0
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

show_df() {
    local label="$1" root=""
    root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
    info "disque ($label), data-root docker : ${root:-inconnu}"
    if [ -n "$root" ]; then df -h "$root" 2>/dev/null || df -h; else df -h; fi
}

# Supprime les volumes d'une liste, un à un, avec garde : ne JAMAIS toucher
# un volume attaché à un container (défense en profondeur, dangling=true ne
# couvre pas une course entre le listing et le rm).
delete_volumes() {
    local vols="$1" name
    [ -n "$vols" ] || { echo "    (aucun volume à supprimer)"; return 0; }
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ -n "$(docker ps -aq --filter "volume=$name")" ]; then
            warn "volume attaché à un container, ignoré : $name"
            log_line "ignoré (attaché) $name"
            continue
        fi
        if docker volume rm "$name" >/dev/null 2>&1; then
            ok "volume supprimé : $name ($(vol_size "$name"))"
            log_line "supprimé  $name"
        else
            warn "échec de suppression : $name"
            log_line "échec     $name"
        fi
    done <<< "$vols"
}

print_class() {
    local label="$1" vols="$2" n=0
    echo "  $label :"
    if [ -z "$vols" ]; then
        echo "    (aucun)"
        return 0
    fi
    while IFS= read -r v; do
        [ -n "$v" ] || continue
        n=$((n + 1))
        printf '    - %-52s %s\n' "$v" "$(vol_size "$v")"
    done <<< "$vols"
    echo "    → $n volume(s)"
}

# --- rapport (défaut, dry-run) ------------------------------------------
cmd_report() {
    echo "=== Rapport Docker — $(date '+%Y-%m-%d %H:%M:%S') ==="
    info "MODE DRY-RUN : rien ne sera supprimé"
    show_df "avant"
    echo
    info "docker system df :"
    docker system df
    echo
    info "build cache (docker buildx du, résumé) :"
    docker buildx du 2>/dev/null | tail -n 2 || warn "docker buildx du indisponible"
    echo
    info "images reclaimable :"
    # NB : pas de .ReclaimablePercent ici — champ absent de certains contextes
    # du formatter docker system df (crash template sinon)
    docker system df --format '  {{.Type}} : {{.Size}} au total — récupérable {{.Reclaimable}}'
    echo "  images « dangling » (sans tag) : $(docker images -f dangling=true -q | wc -l)"
    echo

    load_volume_sizes
    local all_vols cache_vols="" data_vols="" unknown_vols="" v
    all_vols="$(list_dangling)"
    if [ -z "$all_vols" ]; then
        ok "aucun volume dangling"
    else
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            case "$(classify_volume "$v")" in
                CACHE)    cache_vols+="$v"$'\n' ;;
                DATA)     data_vols+="$v"$'\n' ;;
                *)        unknown_vols+="$v"$'\n' ;;
            esac
        done <<< "$all_vols"
        print_class "CLASSE CACHE (supprimable avec --apply)" "$cache_vols"
        print_class "CLASSE DATA (requiert --include-vol-data)" "$data_vols"
        print_class "CLASSE INCONNUE (requiert --include-vol-data)" "$unknown_vols"
    fi
    if [ -n "$data_vols" ] || [ -n "$unknown_vols" ]; then
        warn "ATTENTION : les volumes DATA supprimés ne sont pas sauvegardés — leur suppression exige --include-vol-data"
    fi
    echo
    info "dry-run terminé : aucune suppression effectuée."
    info "pour purger : $SCRIPT_NAME --apply [--keep-cache GO] (volumes DATA/INCONNUE : ajouter --include-vol-data)"
}

# --- purge (--apply) -----------------------------------------------------
cmd_apply() {
    load_volume_sizes
    local all_vols cache_vols="" data_vols="" v n_cache n_data
    all_vols="$(list_dangling)"
    if [ -n "$all_vols" ]; then
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            if [ "$(classify_volume "$v")" = "DATA" ]; then
                data_vols+="$v"$'\n'
            else
                cache_vols+="$v"$'\n'
            fi
        done <<< "$all_vols"
    fi
    n_cache="$(count_lines "$cache_vols")"
    n_data="$(count_lines "$data_vols")"

    echo "=== Purge Docker — $(date '+%Y-%m-%d %H:%M:%S') ==="
    show_df "AVANT"
    echo
    info "plan :"
    echo "    [1/4] build cache             : docker builder prune -af --keep-storage ${KEEP_CACHE_GO}GB"
    echo "    [2/4] images inutilisées      : docker image prune -af"
    echo "    [3/4] volumes CACHE           : $n_cache volume(s)"
    if [ "$INCLUDE_VOL_DATA" = 1 ]; then
        echo "    [4/4] volumes DATA + INCONNUE : $n_data volume(s) ⚠ non sauvegardés"
    else
        echo "    [4/4] volumes DATA + INCONNUE : ignorés ($n_data volume(s) conservés, --include-vol-data requis)"
    fi
    echo
    info "[1/4] build cache (conservation de ${KEEP_CACHE_GO} GB)…"
    docker builder prune -af --keep-storage "${KEEP_CACHE_GO}GB"
    info "[2/4] images inutilisées…"
    docker image prune -af
    info "[3/4] volumes CACHE ($n_cache)…"
    delete_volumes "$cache_vols"
    if [ "$INCLUDE_VOL_DATA" = 1 ]; then
        warn "ATTENTION : les volumes DATA supprimés ne sont pas sauvegardés"
        info "[4/4] volumes DATA + INCONNUE ($n_data)…"
        delete_volumes "$data_vols"
    else
        info "[4/4] volumes DATA + INCONNUE : conservés (relancez avec --include-vol-data pour les inclure)"
    fi
    echo
    show_df "APRÈS"
    info "docker system df après purge :"
    docker system df
    ok "purge terminée"
}

# --- argument parsing ----------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --keep-cache)
            [ -n "${2:-}" ] || die "--keep-cache nécessite une valeur (Go)"
            KEEP_CACHE_GO="$2"; shift 2 ;;
        --keep-cache=*) KEEP_CACHE_GO="${1#*=}"; shift ;;
        --include-vol-data) INCLUDE_VOL_DATA=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --*) die "option inconnue : $1" ;;
        *) die "argument inattendu : '$1' (voir --help)" ;;
    esac
done
printf '%s' "$KEEP_CACHE_GO" | grep -Eq '^[0-9]+$' \
    || die "--keep-cache doit être un entier positif (Go) : '$KEEP_CACHE_GO'"

if [ "$APPLY" = 1 ]; then cmd_apply; else cmd_report; fi
