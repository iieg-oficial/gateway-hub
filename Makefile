REPO_NAME    := gateway-hub
COMPOSE_PROD := -f compose.yaml

UP_GUARDS     = ensure_network; check_sieej_dist; ensure_mantenimiento
DEPLOY_GUARDS = ensure_network; check_sieej_dist; ensure_mantenimiento

include make/common.mk
include make/ecosystem.mk
include make/mantenimiento.mk
