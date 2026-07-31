#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[0;97m'
RESET='\033[0m'

REPOS_DIR="${1:-..}"
GATEWAY_DIR="${2:-.}"
FILTER="${3:-}"

REPO_ORDER=(
  "gateway-hub:$GATEWAY_DIR"
  "acervo:$REPOS_DIR/acervo"
  "huachicol:$REPOS_DIR/huachicol"
  "dataengine:$REPOS_DIR/dataengine"
  "sextante:$REPOS_DIR/sextante"
  "mariachi:$REPOS_DIR/mariachi"
  "mapalab:$REPOS_DIR/mapalab"
  "sieej:$REPOS_DIR/sieej"
  "context-ame-esta:$REPOS_DIR/context-ame-esta"
)

W_REPO=18
W_BRANCH=14
W_RESULT=28
WIDTH=$((W_REPO + W_BRANCH + W_RESULT + 6))

pushed=0
skipped=0
failed=0
dirty_warn=()

dashes() {
  printf "  ${DIM}"
  printf '%*s\n' "$WIDTH" '' | tr ' ' '-'
  printf "${RESET}"
}

row() {
  printf "  %-${W_REPO}s %-${W_BRANCH}s %b\n" "$1" "$2" "$3"
}

echo ""
printf "  ${BOLD}${WHITE}ECOSISTEMA IIEG — PUSH${RESET}  ${DIM}%s${RESET}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
dashes
printf "  ${BOLD}${DIM}%-${W_REPO}s %-${W_BRANCH}s %s${RESET}\n" "REPO" "RAMA" "RESULTADO"
dashes

for entry in "${REPO_ORDER[@]}"; do
  name="${entry%%:*}"
  dir="${entry#*:}"

  if [ -n "$FILTER" ] && ! printf ',%s,' "$FILTER" | grep -q ",$name,"; then
    continue
  fi

  if [ ! -d "$dir/.git" ]; then
    row "$name" "-" "${DIM}no es repo git${RESET}"
    skipped=$((skipped + 1))
    continue
  fi

  branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "")
  if [ -z "$branch" ]; then
    row "$name" "DETACHED" "${RED}omitido: HEAD detached${RESET}"
    skipped=$((skipped + 1))
    continue
  fi

  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    dirty_warn+=("$name")
  fi

  upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo "")
  if [ -n "$upstream" ]; then
    ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
    if [ "$ahead" -eq 0 ]; then
      row "$name" "$branch" "${DIM}al dia, nada que subir${RESET}"
      skipped=$((skipped + 1))
      continue
    fi
    label="$ahead commit(s)"
  else
    label="rama nueva"
  fi

  if out=$(git -C "$dir" push -u origin "$branch" 2>&1); then
    row "$name" "$branch" "${GREEN}subido${RESET}  ${DIM}${label}${RESET}"
    pushed=$((pushed + 1))
  else
    row "$name" "$branch" "${RED}fallo${RESET}"
    echo "$out" | tail -6 | while IFS= read -r line; do
      printf "  ${DIM}       %s${RESET}\n" "$line"
    done
    failed=$((failed + 1))
  fi
done

dashes
printf "  ${GREEN}%d subidos${RESET}   ${DIM}%d omitidos${RESET}   ${RED}%d fallidos${RESET}\n" \
  "$pushed" "$skipped" "$failed"

if [ ${#dirty_warn[@]} -gt 0 ]; then
  echo ""
  printf "  ${YELLOW}Con cambios sin commitear:${RESET} ${CYAN}%s${RESET}\n" "${dirty_warn[*]}"
  printf "  ${DIM}Se subio lo commiteado; esos cambios siguen solo en local.${RESET}\n"
fi

echo ""
[ "$failed" -eq 0 ]
