ECOSYSTEM_STEPS := acervo huachicol dataengine minerva sextante sieej mariachi mapalab sitio2026 gateway intranet

REPOS_DIR := ..
GATEWAY_DIR := .

# Que stacks corren en ESTE nodo. Vacio = todos, que es lo correcto en el monolito
# local. En produccion cada VM lo declara en su .env, para que `make ecosystem-deploy`
# funcione sin banderas. La linea de comandos sigue ganando: STACKS=mapalab make ...
STACKS ?= $(shell sed -n 's/^STACKS=//p' .env 2>/dev/null | head -1)

MINERVA_COMPOSE ?= $(shell sed -n 's/^MINERVA_COMPOSE=//p' .env 2>/dev/null | head -1)

export ECOSYSTEM_STEPS STACKS MINERVA_COMPOSE

.PHONY: ecosystem-up ecosystem-down ecosystem-deploy ecosystem-status ecosystem-pull ecosystem-push

##@ Ecosistema

ecosystem-up: ## Levantar todo el ecosistema en orden topologico
	@$(LIB)
	banner 'ECOSISTEMA' 'up'
	ensure_network
	rule
	ecosystem_run _up-prod
	rule
	printf '\n'
	$(MAKE) ecosystem-status

ecosystem-down: ## Detener todo el ecosistema en orden inverso
	@$(LIB)
	banner 'ECOSISTEMA' 'down'
	rule
	ecosystem_run down reverse || true
	rule
	printf '\n'

ecosystem-deploy: ## Actualizar, reconstruir y levantar todo el ecosistema (VERBOSE=1 para ver el build)
	@$(LIB)
	start=$$(date +%s)
	banner 'ECOSISTEMA' 'deploy'
	ensure_network
	rule
	ecosystem_run deploy
	rule
	total=$$(( $$(date +%s) - start ))
	printf '\n  %sTotal%s         %02d:%02d\n\n' \
		"$$C_BOLD" "$$C_RESET" "$$((total / 60))" "$$((total % 60))"
	$(MAKE) ecosystem-status

ecosystem-status: ## Estado del ecosistema: git, docker y errores en logs
	@./scripts/ecosystem-status.sh "$(REPOS_DIR)" "$(GATEWAY_DIR)"

ecosystem-pull: ## Traer la rama actual de cada repo, sin tocar los que tengan cambios
	@./scripts/ecosystem-pull.sh "$(REPOS_DIR)" "$(GATEWAY_DIR)" "$(STACKS)"

ecosystem-push: ## Push de la rama actual de cada repo, lo corre el usuario
	@./scripts/ecosystem-push.sh "$(REPOS_DIR)" "$(GATEWAY_DIR)" "$(STACKS)"
