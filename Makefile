REPO_NAME    := gateway-hub
COMPOSE_PROD := -f compose.yaml

UP_GUARDS     = ensure_network; check_sieej_dist
DEPLOY_GUARDS = ensure_network; check_sieej_dist

include make/common.mk
include make/ecosystem.mk
