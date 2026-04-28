.PHONY: help up down restart logs ps \
        local-up local-down local-restart local-status \
        network

NETWORK_NAME := iieg-network

REPOS_DIR := ..
ACERVO_DIR := $(REPOS_DIR)/acervo
HUACHICOL_DIR := $(REPOS_DIR)/huachicol
DATAENGINE_DIR := $(REPOS_DIR)/mapalab-dataengine
GEOSERVER_DIR := $(REPOS_DIR)/geoserver
MARIACHI_DIR := $(REPOS_DIR)/mariachi
MAPALAB_DIR := $(REPOS_DIR)/mapalab
SIEEJ_DIR := $(REPOS_DIR)/sieej

MARIACHI_FILES := -f docker-compose.yml
MARIACHI_ENV := --env-file .env.production
MAPALAB_FILES := -f docker-compose.yml
MAPALAB_ENV := --env-file .env.production
GATEWAY_FILES := -f docker-compose.yml
GATEWAY_ENV :=

help:
	@echo ""
	@echo "  Gateway-hub (este repo):"
	@echo "    up              Levantar gateway-hub (.env)"
	@echo "    down            Tumbar gateway-hub"
	@echo "    restart         Reiniciar gateway-hub"
	@echo "    logs            Logs del gateway"
	@echo "    ps              Status de gateway"
	@echo ""
	@echo "  Ecosistema completo (orden topologico):"
	@echo "    local-up        Levantar todo el stack en local"
	@echo "    local-down      Tumbar todo el stack local"
	@echo "    local-restart   local-down + local-up"
	@echo "    local-status    Ver estado de todos los compose projects"
	@echo ""

network:
	@docker network inspect $(NETWORK_NAME) >/dev/null 2>&1 || \
	    (echo "Creando red $(NETWORK_NAME)..."; docker network create $(NETWORK_NAME))

up: network
	docker compose $(GATEWAY_FILES) $(GATEWAY_ENV) up -d

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

local-up: network
	@echo "[1/7] acervo (production standalone)..."
	@$(MAKE) -C $(ACERVO_DIR) up ENV=prod
	@docker network connect $(NETWORK_NAME) acervo-minio 2>/dev/null || true
	@echo ""
	@echo "[2/7] huachicol..."
	@$(MAKE) -C $(HUACHICOL_DIR) start
	@echo ""
	@echo "[3/7] mapalab-dataengine..."
	@$(MAKE) -C $(DATAENGINE_DIR) up
	@echo ""
	@echo "[4/7] geoserver..."
	@cd $(GEOSERVER_DIR) && docker compose up -d
	@echo ""
	@echo "[5/7] sieej dist build (idempotente)..."
	@$(MAKE) -C $(SIEEJ_DIR) build
	@echo ""
	@echo "[5/7] mariachi (env=production)..."
	@cd $(MARIACHI_DIR) && docker compose $(MARIACHI_FILES) $(MARIACHI_ENV) up -d
	@echo ""
	@echo "[6/7] mapalab dist build (idempotente)..."
	@cd $(MAPALAB_DIR) && docker compose $(MAPALAB_FILES) $(MAPALAB_ENV) --profile build run --rm --build frontend-build
	@echo ""
	@echo "[6/7] mapalab nginx + backend (profile=staging, env=production)..."
	@cd $(MAPALAB_DIR) && docker compose $(MAPALAB_FILES) $(MAPALAB_ENV) --profile staging up -d
	@echo ""
	@echo "[7/7] gateway-hub..."
	@$(MAKE) up
	@echo ""
	@echo "Stack production local arriba."
	@$(MAKE) local-status

local-down:
	@echo "Tumbando gateway-hub..."
	-@$(MAKE) down
	@echo "Tumbando mapalab..."
	-@cd $(MAPALAB_DIR) && docker compose $(MAPALAB_FILES) $(MAPALAB_ENV) --profile staging down
	@echo "Tumbando mariachi..."
	-@cd $(MARIACHI_DIR) && docker compose $(MARIACHI_FILES) $(MARIACHI_ENV) down
	@echo "Tumbando geoserver..."
	-@cd $(GEOSERVER_DIR) && docker compose down
	@echo "Tumbando mapalab-dataengine..."
	-@$(MAKE) -C $(DATAENGINE_DIR) down
	@echo "Tumbando huachicol..."
	-@$(MAKE) -C $(HUACHICOL_DIR) stop
	@echo "Tumbando acervo..."
	-@$(MAKE) -C $(ACERVO_DIR) down ENV=prod

local-restart: local-down local-up

local-status:
	@docker compose ls
