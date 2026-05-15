.PHONY: help up down restart deploy build logs ps \
        ecosystem-up ecosystem-down ecosystem-restart ecosystem-status \
        ecosystem-pull ecosystem-update \
        network

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

MARIACHI_FILES := -f docker-compose.yml
MARIACHI_ENV := --env-file .env.production
MAPALAB_FILES := -f docker-compose.yml
MAPALAB_ENV := --env-file .env.production
GATEWAY_FILES := -f docker-compose.yml

help:
	@echo ""
	@echo "  Gateway-hub (este repo):"
	@echo "    up                  Levantar gateway-hub usando la imagen actual (rapido)"
	@echo "    build               Solo rebuildear la imagen (sin levantar)"
	@echo "    deploy              build + up (usar tras cambios en nginx config, templates, etc.)"
	@echo "    down                Tumbar gateway-hub"
	@echo "    restart             Reiniciar gateway-hub"
	@echo "    logs                Logs del gateway"
	@echo "    ps                  Status de gateway"
	@echo ""
	@echo "  Ecosistema completo en modo production local (orden topologico):"
	@echo "    ecosystem-up        Levantar acervo + huachicol + dataengine + geoserver"
	@echo "                        + sieej dist + mariachi + mapalab + gateway-hub"
	@echo "    ecosystem-down      Tumbar todo el stack"
	@echo "    ecosystem-restart   ecosystem-down + ecosystem-up"
	@echo "    ecosystem-status    docker compose ls (estado de cada compose project)"
	@echo "    ecosystem-pull      git pull en cada repo del orquestador (sin levantar nada)"
	@echo "    ecosystem-update    ecosystem-pull + ecosystem-up (despliegue completo)"
	@echo ""
	@echo "  Servicios NO incluidos en ecosystem-up (levantar manualmente si se requiere):"
	@echo "    - sitio2026 (cd ../sitio2026 && make up ENV=gcp)"
	@echo "    - minerva   (cd ../minerva   && make up)"
	@echo ""

network:
	@docker network inspect $(NETWORK_NAME) >/dev/null 2>&1 || \
	    (echo "Creando red $(NETWORK_NAME)..."; docker network create $(NETWORK_NAME))

up: network
	docker compose $(GATEWAY_FILES) up -d

build:
	docker compose $(GATEWAY_FILES) build

deploy: network
	docker compose $(GATEWAY_FILES) up -d --build

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

ecosystem-up: network
	@echo "[1/7] acervo (SeaweedFS)..."
	@$(MAKE) -C $(ACERVO_DIR) up
	@echo ""
	@echo "[2/7] huachicol (monitoring stack)..."
	@$(MAKE) -C $(HUACHICOL_DIR) start
	@echo ""
	@echo "[3/7] dataengine..."
	@$(MAKE) -C $(DATAENGINE_DIR) up
	@echo ""
	@echo "[4/7] geoserver..."
	@cd $(GEOSERVER_DIR) && docker compose up -d
	@echo ""
	@echo "[5/7] sieej (build idempotente del dist)..."
	@$(MAKE) -C $(SIEEJ_DIR) build
	@echo ""
	@echo "[6/7] mariachi (make deploy)..."
	@$(MAKE) -C $(MARIACHI_DIR) deploy
	@echo ""
	@echo "[7/7] mapalab (make deploy)..."
	@$(MAKE) -C $(MAPALAB_DIR) deploy
	@echo ""
	@echo "[8/8] gateway-hub (make deploy)..."
	@$(MAKE) deploy
	@echo ""
	@echo "Stack production local arriba."
	@$(MAKE) ecosystem-status

ecosystem-down:
	@echo "Tumbando gateway-hub..."
	-@$(MAKE) down
	@echo "Tumbando mapalab..."
	-@cd $(MAPALAB_DIR) && docker compose $(MAPALAB_FILES) $(MAPALAB_ENV) --profile staging down
	@echo "Tumbando mariachi..."
	-@cd $(MARIACHI_DIR) && docker compose $(MARIACHI_FILES) $(MARIACHI_ENV) down
	@echo "Tumbando geoserver..."
	-@cd $(GEOSERVER_DIR) && docker compose down
	@echo "Tumbando dataengine..."
	-@$(MAKE) -C $(DATAENGINE_DIR) down
	@echo "Tumbando huachicol..."
	-@$(MAKE) -C $(HUACHICOL_DIR) stop
	@echo "Tumbando acervo..."
	-@$(MAKE) -C $(ACERVO_DIR) down

ecosystem-restart: ecosystem-down ecosystem-up

ecosystem-status:
	@docker compose ls

ecosystem-pull:
	@for d in $(ECOSYSTEM_REPOS); do \
	    echo ""; \
	    echo "── git pull en $$d ──"; \
	    if [ -d "$$d/.git" ]; then \
	        git -C "$$d" pull --ff-only || echo "  ! pull fallo en $$d (probablemente working tree sucio o branch divergente)"; \
	    else \
	        echo "  (no es repo git, omitido)"; \
	    fi; \
	done

ecosystem-update: ecosystem-pull ecosystem-up
