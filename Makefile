.PHONY: help up down restart deploy build logs ps urls \
        ecosystem-up ecosystem-down ecosystem-restart ecosystem-status \
        ecosystem-pull ecosystem-pull-others ecosystem-update \
        network version-json check-sieej-dist

# Targets sin comando real (phony) y default goal explicito
.DEFAULT_GOAL := help

# Evitar el ruido "Entering directory 'X'" al delegar a subrepos
MAKEFLAGS += --no-print-directory

# Shell estricto: fallar rapido si algo sale mal a media linea
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

NETWORK_NAME := iieg-network

REPOS_DIR := ..
GATEWAY_DIR := .
ACERVO_DIR := $(REPOS_DIR)/acervo
HUACHICOL_DIR := $(REPOS_DIR)/huachicol
DATAENGINE_DIR := $(REPOS_DIR)/dataengine
GEOSERVER_DIR := $(REPOS_DIR)/geoserver
MARIACHI_DIR := $(REPOS_DIR)/mariachi
MAPALAB_DIR := $(REPOS_DIR)/mapalab
SIEEJ_DIR := $(REPOS_DIR)/sieej

ECOSYSTEM_REPOS := $(GATEWAY_DIR) $(ACERVO_DIR) $(HUACHICOL_DIR) $(DATAENGINE_DIR) $(GEOSERVER_DIR) $(MARIACHI_DIR) $(MAPALAB_DIR) $(SIEEJ_DIR)
ECOSYSTEM_REPOS_OTHERS := $(ACERVO_DIR) $(HUACHICOL_DIR) $(DATAENGINE_DIR) $(GEOSERVER_DIR) $(MARIACHI_DIR) $(MAPALAB_DIR) $(SIEEJ_DIR)

# Orden topologico del ecosistema: "<nombre>:<dir>:<target-up>:<target-down>".
# nombre   = etiqueta legible para el filtro STACKS y los mensajes
# dir      = directorio del subrepo
# target-up   = make target para levantar
# target-down = make target para tumbar
# El orden importa: dependencias de datos primero (storage, monitoring, db),
# luego servicios que las consumen (geoserver, sieej build, mariachi, mapalab),
# y al final el gateway que enruta todo.
ECOSYSTEM_STEPS := \
    acervo:$(ACERVO_DIR):up:down \
    huachicol:$(HUACHICOL_DIR):start:stop \
    dataengine:$(DATAENGINE_DIR):up:down \
    geoserver:$(GEOSERVER_DIR):up:down \
    sieej:$(SIEEJ_DIR):build:down \
    mariachi:$(MARIACHI_DIR):deploy:down \
    mapalab:$(MAPALAB_DIR):deploy:down \
    gateway:.:deploy:down

GATEWAY_FILES := -f docker-compose.yml

# Filtro opcional: `make ecosystem-up STACKS=mariachi,mapalab` levanta solo
# esos. Sin STACKS, levanta todos.
STACKS ?=

help:  ## Mostrar esta ayuda
	@awk 'BEGIN { \
	    FS = ":.*?## "; \
	    print ""; \
	    print "Targets disponibles:"; \
	    print ""; \
	} \
	/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo ""
	@echo "  Servicios NO incluidos en ecosystem-up (levantar manualmente si se requiere):"
	@echo "    - sitio2026 (cd ../sitio2026 && make up ENV=gcp)"
	@echo "    - minerva   (cd ../minerva   && make up)"
	@echo ""
	@echo "  Filtro: STACKS=mariachi,mapalab make ecosystem-up   (levanta solo esos)"
	@echo ""

##@ Gateway (este repo)

network:  ## Crear la red iieg-network si no existe
	@docker network inspect $(NETWORK_NAME) >/dev/null 2>&1 || \
	    (echo "Creando red $(NETWORK_NAME)..."; docker network create $(NETWORK_NAME))

check-sieej-dist:
	@SIEEJ_DIST_PATH=$$(grep -E '^SIEEJ_DIST_PATH=' .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'); \
	 SIEEJ_DIST_PATH=$${SIEEJ_DIST_PATH:-../sieej/frontend/dist}; \
	 if [ ! -d "$$SIEEJ_DIST_PATH" ]; then \
	     echo "ERROR: SIEEJ_DIST_PATH no existe: $$SIEEJ_DIST_PATH" >&2; \
	     echo "       Construye el dist primero: make -C $(SIEEJ_DIR) build" >&2; \
	     exit 1; \
	 fi

up: network version-json check-sieej-dist  ## Levantar gateway-hub usando la imagen actual (rapido)
	docker compose $(GATEWAY_FILES) up -d
	@$(MAKE) urls

build: version-json  ## Solo rebuildear la imagen (sin levantar)
	docker compose $(GATEWAY_FILES) build

deploy: network version-json check-sieej-dist  ## build + up (usar tras cambios en nginx config, templates, etc.)
	docker compose $(GATEWAY_FILES) up -d --build
	@$(MAKE) urls

down:  ## Tumbar gateway-hub
	docker compose $(GATEWAY_FILES) down

restart: down up  ## Reiniciar gateway-hub

logs:  ## Logs del gateway (follow, tail 100)
	docker compose $(GATEWAY_FILES) logs -f --tail=100

ps:  ## Status de gateway
	docker compose $(GATEWAY_FILES) ps

version-json:  ## Regenerar nginx/version.json desde VERSION + CHANGELOG
	@./scripts/gen-version-json.sh

urls:  ## Imprimir URLs publicas del gateway (usa APP_DOMAIN de .env)
	@DOMAIN=$$(grep -E '^APP_DOMAIN=' .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'); \
	 DOMAIN=$${DOMAIN:-iieg.local}; \
	 BASE="https://$$DOMAIN"; \
	 echo ""; \
	 echo "URLs disponibles ($$BASE):"; \
	 printf "  %-22s %s\n" "/"                  "redirect -> /mapalab/"; \
	 printf "  %-22s %s\n" "/mapalab/"          "MapaLab (visor de mapas)"; \
	 printf "  %-22s %s\n" "/sieej/"            "SIEEJ (sistema estadistico)"; \
	 printf "  %-22s %s\n" "/administrador/"    "MARIACHI (panel admin del portal)"; \
	 printf "  %-22s %s\n" "/mariachi/"         "MARIACHI (CMS del ecosistema)"; \
	 printf "  %-22s %s\n" "/huachicol/"        "Huachicol (Grafana)"; \
	 printf "  %-22s %s\n" "/geoserver/web/"    "GeoServer (admin)"; \
	 printf "  %-22s %s\n" "/ontoy"             "version JSON del gateway"; \
	 echo ""

##@ Ecosistema (orquestador local)

ecosystem-up: network  ## Levantar todo el stack en orden topologico (acepta STACKS=a,b)
	@STEPS="$(ECOSYSTEM_STEPS)"; \
	 FILTER="$(STACKS)"; \
	 SELECTED=""; \
	 for step in $$STEPS; do \
	     name=$$(echo $$step | cut -d: -f1); \
	     if [ -z "$$FILTER" ] || echo ",$$FILTER," | grep -q ",$$name,"; then \
	         SELECTED="$$SELECTED $$step"; \
	     fi; \
	 done; \
	 TOTAL=$$(echo $$SELECTED | wc -w); \
	 I=0; \
	 for step in $$SELECTED; do \
	     I=$$((I+1)); \
	     name=$$(echo $$step | cut -d: -f1); \
	     dir=$$(echo $$step | cut -d: -f2); \
	     tgt=$$(echo $$step | cut -d: -f3); \
	     echo ""; \
	     echo "[$$I/$$TOTAL] $$name ($$dir -> make $$tgt)..."; \
	     $(MAKE) -C $$dir $$tgt; \
	 done
	@echo ""
	@echo "Stack production local arriba."
	@$(MAKE) ecosystem-status
	@$(MAKE) urls

ecosystem-down:  ## Tumbar todo el stack (orden inverso, acepta STACKS=a,b)
	@STEPS="$(ECOSYSTEM_STEPS)"; \
	 FILTER="$(STACKS)"; \
	 REVERSED=""; \
	 for step in $$STEPS; do \
	     name=$$(echo $$step | cut -d: -f1); \
	     if [ -z "$$FILTER" ] || echo ",$$FILTER," | grep -q ",$$name,"; then \
	         REVERSED="$$step $$REVERSED"; \
	     fi; \
	 done; \
	 for step in $$REVERSED; do \
	     name=$$(echo $$step | cut -d: -f1); \
	     dir=$$(echo $$step | cut -d: -f2); \
	     tgt=$$(echo $$step | cut -d: -f4); \
	     echo "Tumbando $$name..."; \
	     $(MAKE) -C $$dir $$tgt || echo "  ! fallo al tumbar $$name (continuando)"; \
	 done

ecosystem-restart: ecosystem-down ecosystem-up  ## ecosystem-down + ecosystem-up

ecosystem-status:  ## Estatus del ecosistema: git (cambios, push, pull) + docker de cada repo
	@./scripts/ecosystem-status.sh "$(REPOS_DIR)" "$(GATEWAY_DIR)"

ecosystem-pull:  ## git pull --ff-only en cada repo (incluye gateway-hub)
	@for d in $(ECOSYSTEM_REPOS); do \
	    echo ""; \
	    echo "-- git pull en $$d --"; \
	    if [ -d "$$d/.git" ]; then \
	        git -C "$$d" pull --ff-only || echo "  ! pull fallo en $$d (probablemente working tree sucio o branch divergente)"; \
	    else \
	        echo "  (no es repo git, omitido)"; \
	    fi; \
	done

ecosystem-pull-others:  ## git pull --ff-only en todos los repos EXCEPTO gateway-hub
	@for d in $(ECOSYSTEM_REPOS_OTHERS); do \
	    echo ""; \
	    echo "-- git pull en $$d --"; \
	    if [ -d "$$d/.git" ]; then \
	        git -C "$$d" pull --ff-only || echo "  ! pull fallo en $$d (probablemente working tree sucio o branch divergente)"; \
	    else \
	        echo "  (no es repo git, omitido)"; \
	    fi; \
	done

ecosystem-update: ecosystem-pull ecosystem-up  ## ecosystem-pull + ecosystem-up (despliegue completo)
