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

# minerva no es repo nuestro y no trae los Makefiles del ecosistema, asi que su paso
# se resuelve con docker compose directo (equivale a su `just up`, sin depender de just).
#
# MINERVA_COMPOSE elige con cual: hoy `docker-compose.yml`, que construye desde fuente,
# porque su Justfile no expone ninguna receta para `docker-compose.deploy.yml` y ese es
# el unico camino documentado por su equipo. Cuando publiquen un entorno de produccion
# soportado, esto pasa a `docker-compose.deploy.yml` y se consume su imagen de ghcr.io.
# Ver ecosistema/planes/orquestacion-minerva-portalito.md.
MINERVA_COMPOSE="${MINERVA_COMPOSE:-docker-compose.yml}"

step_cmd() {
    local name=$1 target=$2 dir=$3
    STEP_CMD=()
    if [ "$name" != 'minerva' ]; then
        STEP_CMD=(make -C "$dir" "$target")
        return 0
    fi
    local -a compose=(docker compose --project-directory "$dir" -f "$dir/$MINERVA_COMPOSE")
    local -a extra=()
    [ "$MINERVA_COMPOSE" = 'docker-compose.yml' ] && extra=(--build) || extra=(--pull always)
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
