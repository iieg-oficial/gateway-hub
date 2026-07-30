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
        if ! run_step "$name" make -C "$dir" "$target"; then
            rc=1
            [ "$order" = 'forward' ] && return 1
        fi
    done
    return $rc
}
