#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[0;97m'
RESET='\033[0m'

REPOS_DIR="${1:-..}"
GATEWAY_DIR="${2:-.}"

declare -A REPO_NAMES=(
  ["$GATEWAY_DIR"]="gateway-hub"
  ["$REPOS_DIR/acervo"]="acervo"
  ["$REPOS_DIR/huachicol"]="huachicol"
  ["$REPOS_DIR/dataengine"]="dataengine"
  ["$REPOS_DIR/geoserver"]="geoserver"
  ["$REPOS_DIR/mariachi"]="mariachi"
  ["$REPOS_DIR/mapalab"]="mapalab"
  ["$REPOS_DIR/sieej"]="sieej"
)

REPO_ORDER=(
  "$GATEWAY_DIR"
  "$REPOS_DIR/acervo"
  "$REPOS_DIR/huachicol"
  "$REPOS_DIR/dataengine"
  "$REPOS_DIR/geoserver"
  "$REPOS_DIR/mariachi"
  "$REPOS_DIR/mapalab"
  "$REPOS_DIR/sieej"
)

total_repos=0
total_clean=0
total_dirty=0
total_ahead=0
total_behind=0
total_not_repo=0

W_REPO=14
W_BRANCH=14
W_CHANGES=14
W_REMOTE=14
W_DOCKER=10
WIDTH=$((W_REPO + W_BRANCH + W_CHANGES + W_REMOTE + W_DOCKER + 12))

center() {
  local visible="$1"
  local width="$2"
  local colored="$3"
  local len=${#visible}
  if [ "$len" -ge "$width" ]; then
    printf "%b" "$colored"
    return
  fi
  local pad=$(( (width - len) / 2 ))
  local rpad=$(( width - len - pad ))
  printf "%*s%b%*s" "$pad" "" "$colored" "$rpad" ""
}

dashes() {
  printf "  ${DIM}"
  printf '%*s\n' "$WIDTH" '' | tr ' ' '-'
  printf "${RESET}"
}

get_docker_str() {
  local dir="$1"
  local compose_args=""
  [ -f "$dir/docker-compose.yml" ] && compose_args="-f $dir/docker-compose.yml"
  [ -f "$dir/docker-compose.yaml" ] && compose_args="-f $dir/docker-compose.yaml"
  [ -f "$dir/compose.yml" ] && compose_args="-f $dir/compose.yml"
  [ -f "$dir/compose.yaml" ] && compose_args="-f $dir/compose.yaml"
  [ -f "$dir/compose.yaml" ] && [ -f "$dir/compose.prod.yaml" ] \
    && compose_args="-f $dir/compose.yaml -f $dir/compose.prod.yaml"
  local env_file=""
  [ -f "$dir/.env" ] && env_file="--env-file $dir/.env"
  [ -f "$dir/.env.production" ] && env_file="--env-file $dir/.env.production"
  compose_args="--project-directory $dir $env_file $compose_args"

  if [ -z "$compose_args" ]; then
    printf "${DIM}n/a${RESET}"
    return
  fi

  local running=0 stopped=0 total=0
  if command -v docker &>/dev/null; then
    local containers
    containers=$(docker compose $compose_args ps --format '{{.State}}' 2>/dev/null || true)
    if [ -n "$containers" ]; then
      while IFS= read -r state; do
        total=$((total + 1))
        [ "$state" = "running" ] && running=$((running + 1)) || stopped=$((stopped + 1))
      done <<< "$containers"
    fi
  fi

  if [ "$total" -eq 0 ]; then
    printf "${DIM}off${RESET}"
  elif [ "$stopped" -gt 0 ]; then
    printf "${GREEN}%d${RESET}/${DIM}%d${RESET} ${RED}%d down${RESET}" "$running" "$total" "$stopped"
  else
    printf "${GREEN}%d/%d${RESET}" "$running" "$total"
  fi
}

echo ""
printf "  ${BOLD}${WHITE}ECOSISTEMA IIEG — ESTATUS${RESET}  ${DIM}%s${RESET}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
dashes
printf "  "
printf "${BOLD}${DIM}%-${W_REPO}s${RESET} " "REPO"
center "RAMA" "$W_BRANCH" "${BOLD}${DIM}RAMA${RESET}"
printf " "
center "CAMBIOS" "$W_CHANGES" "${BOLD}${DIM}CAMBIOS${RESET}"
printf " "
center "REMOTE" "$W_REMOTE" "${BOLD}${DIM}REMOTE${RESET}"
printf " "
center "DOCKER" "$W_DOCKER" "${BOLD}${DIM}DOCKER${RESET}"
echo ""
dashes

for dir in "${REPO_ORDER[@]}"; do
  name="${REPO_NAMES[$dir]:-$(basename "$dir")}"
  total_repos=$((total_repos + 1))

  if [ ! -d "$dir/.git" ]; then
    printf "  %-${W_REPO}s " "$name"
    center "no es repo" "$W_BRANCH" "${YELLOW}no es repo${RESET}"
    echo ""
    total_not_repo=$((total_not_repo + 1))
    continue
  fi

  branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "DETACHED")
  if [ "$branch" = "DETACHED" ]; then
    branch_vis="DETACHED"
    branch_col="${RED}DETACHED${RESET}"
  else
    branch_vis="$branch"
    branch_col="${CYAN}${branch}${RESET}"
  fi

  dirty_files=$(git -C "$dir" status --porcelain 2>/dev/null)
  dirty_count=0
  [ -n "$dirty_files" ] && dirty_count=$(echo "$dirty_files" | wc -l)

  upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
  ahead=0; behind=0
  if [ -n "$upstream" ]; then
    ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
    behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
  fi

  docker_str=$(get_docker_str "$dir")

  if [ "$dirty_count" -gt 0 ]; then
    changes_vis="${dirty_count} archivo(s)"
    changes_col="${RED}${dirty_count} archivo(s)${RESET}"
    total_dirty=$((total_dirty + 1))
  else
    changes_vis="limpio"
    changes_col="${GREEN}limpio${RESET}"
    total_clean=$((total_clean + 1))
  fi

  if [ -n "$upstream" ]; then
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      remote_vis="${ahead} push ${behind} pull"
      remote_col="${YELLOW}${ahead} push${RESET} ${MAGENTA}${behind} pull${RESET}"
      total_ahead=$((total_ahead + 1))
      total_behind=$((total_behind + 1))
    elif [ "$ahead" -gt 0 ]; then
      remote_vis="${ahead} sin push"
      remote_col="${YELLOW}${ahead} sin push${RESET}"
      total_ahead=$((total_ahead + 1))
    elif [ "$behind" -gt 0 ]; then
      remote_vis="${behind} sin pull"
      remote_col="${MAGENTA}${behind} sin pull${RESET}"
      total_behind=$((total_behind + 1))
    else
      remote_vis="al dia"
      remote_col="${GREEN}al dia${RESET}"
    fi
  else
    remote_vis="sin upstream"
    remote_col="${DIM}sin upstream${RESET}"
  fi

  printf "  %-${W_REPO}s " "$name"
  center "$branch_vis" "$W_BRANCH" "$branch_col"
  printf " "
  center "$changes_vis" "$W_CHANGES" "$changes_col"
  printf " "
  center "$remote_vis" "$W_REMOTE" "$remote_col"
  printf " "
  docker_vis=$(echo -e "$docker_str" | sed 's/\x1b\[[0-9;]*m//g')
  center "$docker_vis" "$W_DOCKER" "$docker_str"
  echo ""
done

dashes

echo ""
printf "  ${BOLD}RESUMEN${RESET}  "
printf "${GREEN}%d limpios${RESET}" "$total_clean"
[ "$total_dirty" -gt 0 ] && printf "  ${RED}%d con cambios${RESET}" "$total_dirty"
[ "$total_ahead" -gt 0 ] && printf "  ${YELLOW}%d sin push${RESET}" "$total_ahead"
[ "$total_behind" -gt 0 ] && printf "  ${MAGENTA}%d sin pull${RESET}" "$total_behind"
echo ""

if [ "$total_dirty" -eq 0 ] && [ "$total_ahead" -eq 0 ] && [ "$total_behind" -eq 0 ]; then
  echo ""
  printf "  ${GREEN}${BOLD}TODO AL DIA${RESET} — el ecosistema esta limpio.\n"
fi

echo ""
printf "  ${BOLD}${WHITE}ERRORES RECIENTES${RESET}  ${DIM}(ultimas 15 lineas por contenedor)${RESET}\n"
dashes
has_errors=false

for dir in "${REPO_ORDER[@]}"; do
    compose_args=""
    [ -f "$dir/docker-compose.yml" ] && compose_args="-f $dir/docker-compose.yml"
    [ -f "$dir/docker-compose.yaml" ] && compose_args="-f $dir/docker-compose.yaml"
    [ -f "$dir/compose.yml" ] && compose_args="-f $dir/compose.yml"
    [ -f "$dir/compose.yaml" ] && compose_args="-f $dir/compose.yaml"
    [ -f "$dir/compose.yaml" ] && [ -f "$dir/compose.prod.yaml" ] \
      && compose_args="-f $dir/compose.yaml -f $dir/compose.prod.yaml"
    env_file=""
    [ -f "$dir/.env" ] && env_file="--env-file $dir/.env"
    [ -f "$dir/.env.production" ] && env_file="--env-file $dir/.env.production"
    compose_args="--project-directory $dir $env_file $compose_args"

    [ -z "$compose_args" ] && continue
    command -v docker &>/dev/null || continue

    containers=$(docker compose $compose_args ps -q 2>/dev/null || true)
    [ -z "$containers" ] && continue

    for container_id in $containers; do
        errors=$(docker logs --tail 15 "$container_id" 2>&1 | grep -iE '\b(error|fatal|critical|panic)\b' | tail -3 || true)
        if [ -n "$errors" ]; then
            has_errors=true
            cname=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's|^/||')
            printf "  ${RED}%s${RESET}\n" "$cname"
            echo "$errors" | while IFS= read -r line; do
                printf "    ${DIM}%s${RESET}\n" "$(echo "$line" | head -c 140)"
            done
        fi
    done
done

if [ "$has_errors" = false ]; then
    printf "  ${GREEN}Sin errores detectados.${RESET}\n"
fi

echo ""
