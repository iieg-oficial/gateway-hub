SIEEJ_DIR='../sieej'

sieej_dist_path() {
    local path
    path=$(grep -E '^SIEEJ_DIST_PATH=' .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"')
    printf '%s' "${path:-../sieej/frontend/dist}"
}

check_sieej_dist() {
    local path
    path=$(sieej_dist_path)
    if [ -d "$path" ]; then
        row 'SIEEJ dist' 'ok' "$C_GREEN" "$path"
    else
        fail "SIEEJ dist:$path no existe" \
             "Construye el dist primero: make -C $SIEEJ_DIR deploy"
    fi
}

step_dir() {
    if [ "$1" = 'gateway' ]; then printf '.'; else printf '../%s' "$1"; fi
}

selected_steps() {
    local filter=${STACKS:-} name
    for name in $ECOSYSTEM_STEPS; do
        if [ -z "$filter" ] || printf ',%s,' "$filter" | grep -q ",$name,"; then
            printf '%s\n' "$name"
        fi
    done
}

minerva_env() {
    sed -n "s/^$2=//p" "$1/.env" 2>/dev/null | tail -n1 | tr -d '"'"'"
}

minerva_compose() {
    if [ -n "${MINERVA_COMPOSE:-}" ]; then
        printf '%s' "$MINERVA_COMPOSE"
        return 0
    fi
    case "$(minerva_env "$1" APP_ENV)" in
        dev|development|local) printf 'docker-compose.yml' ;;
        *)                     printf 'docker-compose.deploy.yml' ;;
    esac
}

minerva_sin_version() {
    printf 'minerva: MINERVA_VERSION vacia o latest en %s/.env; fija la version de la imagen de ghcr.io\n' "$1" >&2
    return 1
}

step_cmd() {
    local name=$1 target=$2 dir=$3
    STEP_CMD=()
    if [ "$name" != 'minerva' ]; then
        STEP_CMD=(make -C "$dir" "$target")
        return 0
    fi
    local file version
    file=$(minerva_compose "$dir")
    local -a compose=(docker compose --project-directory "$dir" -f "$dir/$file")
    local -a extra=(--build)
    if [ "$file" = 'docker-compose.deploy.yml' ]; then
        version=$(minerva_env "$dir" MINERVA_VERSION)
        if [ "$target" != 'down' ] && { [ -z "$version" ] || [ "$version" = 'latest' ]; }; then
            STEP_CMD=(minerva_sin_version "$dir")
            return 0
        fi
        extra=(--pull always)
    fi
    case "$target" in
        deploy)   STEP_CMD=("${compose[@]}" up -d "${extra[@]}") ;;
        _up-prod) STEP_CMD=("${compose[@]}" up -d) ;;
        down)     STEP_CMD=("${compose[@]}" down --remove-orphans) ;;
        *)        return 1 ;;
    esac
}

ecosystem_run() {
    local target=$1 order=${2:-forward}
    local -a steps
    mapfile -t steps < <(selected_steps)
    [ "$order" = 'reverse' ] && mapfile -t steps < <(printf '%s\n' "${steps[@]}" | tac)

    local name dir rc=0
    for name in "${steps[@]}"; do
        dir=$(step_dir "$name")
        if [ ! -d "$dir" ]; then
            row "$name" 'skip' "$C_DIM"
            continue
        fi
        if ! step_cmd "$name" "$target" "$dir"; then
            row "$name" 'n/a' "$C_DIM" "sin equivalente para $target"
            continue
        fi
        if ! run_step "$name" "${STEP_CMD[@]}"; then
            rc=1
            [ "$order" = 'forward' ] && return 1
        fi
    done
    return $rc
}

MANTENIMIENTO_DIR='mantenimiento'
MANTENIMIENTO_SERVICIOS='mapalab'

ensure_mantenimiento() {
    mkdir -p "$MANTENIMIENTO_DIR"
    row 'Mantenimiento' 'listo' "$C_GREEN" "$MANTENIMIENTO_DIR"
}

estado_mantenimiento() {
    if [ -f "$MANTENIMIENTO_DIR/$1" ]; then printf 'encendido'; else printf 'apagado'; fi
}
