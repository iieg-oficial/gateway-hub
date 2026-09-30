#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

REPOS_DIR="${1:-..}"
GATEWAY_DIR="${2:-.}"
STACKS="${3:-}"

REPO_ORDER=(
  "$GATEWAY_DIR"
  "$REPOS_DIR/acervo"
  "$REPOS_DIR/huachicol"
  "$REPOS_DIR/dataengine"
  "$REPOS_DIR/sextante"
  "$REPOS_DIR/mariachi"
  "$REPOS_DIR/mapalab"
  "$REPOS_DIR/mapalab-qgis"
  "$REPOS_DIR/sieej"
  "$REPOS_DIR/sitio2026"
  "$REPOS_DIR/vine"
  "$REPOS_DIR/frames"
  "$REPOS_DIR/intranet"
  "$REPOS_DIR/minerva"
)

declare -A REPO_NAMES=(
  ["$GATEWAY_DIR"]="gateway-hub"
  ["$REPOS_DIR/acervo"]="acervo"
  ["$REPOS_DIR/huachicol"]="huachicol"
  ["$REPOS_DIR/dataengine"]="dataengine"
  ["$REPOS_DIR/sextante"]="sextante"
  ["$REPOS_DIR/mariachi"]="mariachi"
  ["$REPOS_DIR/mapalab"]="mapalab"
  ["$REPOS_DIR/mapalab-qgis"]="mapalab-qgis"
  ["$REPOS_DIR/sieej"]="sieej"
  ["$REPOS_DIR/sitio2026"]="sitio2026"
  ["$REPOS_DIR/vine"]="vine"
  ["$REPOS_DIR/frames"]="frames"
  ["$REPOS_DIR/intranet"]="intranet"
  ["$REPOS_DIR/minerva"]="minerva"
)

W_REPO=14
W_BRANCH=13
W_STATE=16
WIDTH=$((W_REPO + W_BRANCH + W_STATE + 26))

dashes() {
  printf "  ${DIM}"
  printf '%*s\n' "$WIDTH" '' | tr ' ' '-'
  printf "${RESET}"
}

selected() {
  local name="$1"
  [ -z "$STACKS" ] && return 0
  printf ',%s,' "$STACKS" | grep -q ",$name," && return 0
  return 1
}

actualizados=0
al_dia=0
omitidos=0
fallidos=0

printf "\n  ${BOLD}ECOSISTEMA${RESET} ${DIM}— pull${RESET}\n"
dashes
printf "  ${DIM}%-${W_REPO}s %-${W_BRANCH}s %-${W_STATE}s %s${RESET}\n" "REPO" "RAMA" "ESTADO" "RESULTADO"
dashes

for dir in "${REPO_ORDER[@]}"; do
  name="${REPO_NAMES[$dir]}"
  selected "$name" || continue

  if [ ! -d "$dir/.git" ]; then
    printf "  %-${W_REPO}s ${DIM}%-${W_BRANCH}s %-${W_STATE}s %s${RESET}\n" "$name" "-" "sin repo" "omitido"
    omitidos=$((omitidos + 1))
    continue
  fi

  branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "?")
  sucios=$(git -C "$dir" status --porcelain 2>/dev/null | grep -vc '^??' || true)

  if [ "${sucios:-0}" -gt 0 ]; then
    printf "  %-${W_REPO}s %-${W_BRANCH}s ${YELLOW}%-${W_STATE}s${RESET} ${YELLOW}%s${RESET}\n" \
      "$name" "$branch" "$sucios sin commitear" "omitido, no se pisa"
    omitidos=$((omitidos + 1))
    continue
  fi

  if ! git -C "$dir" fetch -q origin "$branch" 2>/dev/null; then
    printf "  %-${W_REPO}s %-${W_BRANCH}s ${RED}%-${W_STATE}s${RESET} ${RED}%s${RESET}\n" \
      "$name" "$branch" "sin remoto" "fallo el fetch"
    fallidos=$((fallidos + 1))
    continue
  fi

  detras=$(git -C "$dir" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)
  adelante=$(git -C "$dir" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)

  if [ "$detras" -eq 0 ]; then
    extra="al dia"
    [ "$adelante" -gt 0 ] && extra="al dia, $adelante sin subir"
    printf "  %-${W_REPO}s %-${W_BRANCH}s ${DIM}%-${W_STATE}s${RESET} ${DIM}%s${RESET}\n" \
      "$name" "$branch" "limpio" "$extra"
    al_dia=$((al_dia + 1))
    continue
  fi

  if [ "$adelante" -gt 0 ]; then
    printf "  %-${W_REPO}s %-${W_BRANCH}s ${RED}%-${W_STATE}s${RESET} ${RED}%s${RESET}\n" \
      "$name" "$branch" "divergio" "omitido, resuelve a mano"
    omitidos=$((omitidos + 1))
    continue
  fi

  if git -C "$dir" merge --ff-only -q "origin/$branch" 2>/dev/null; then
    printf "  %-${W_REPO}s %-${W_BRANCH}s ${GREEN}%-${W_STATE}s${RESET} ${GREEN}%s${RESET}\n" \
      "$name" "$branch" "actualizado" "+$detras commits"
    actualizados=$((actualizados + 1))
  else
    printf "  %-${W_REPO}s %-${W_BRANCH}s ${RED}%-${W_STATE}s${RESET} ${RED}%s${RESET}\n" \
      "$name" "$branch" "error" "fallo el merge"
    fallidos=$((fallidos + 1))
  fi
done

dashes
printf "  ${GREEN}%d actualizados${RESET}   ${DIM}%d al dia${RESET}   ${YELLOW}%d omitidos${RESET}" \
  "$actualizados" "$al_dia" "$omitidos"
[ "$fallidos" -gt 0 ] && printf "   ${RED}%d con error${RESET}" "$fallidos"
printf "\n"

if [ "$actualizados" -gt 0 ]; then
  printf "\n  ${CYAN}Los repos actualizados necesitan rebuild:${RESET} make ecosystem-deploy\n"
fi
printf "\n"

[ "$fallidos" -eq 0 ]
