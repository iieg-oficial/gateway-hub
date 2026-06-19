.PHONY: help up deploy down \
        ecosystem-up ecosystem-down ecosystem-deploy ecosystem-status

.DEFAULT_GOAL := help

MAKEFLAGS += --no-print-directory

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

ECOSYSTEM_STEPS := \
    acervo:$(ACERVO_DIR):up:down \
    huachicol:$(HUACHICOL_DIR):start:stop \
    dataengine:$(DATAENGINE_DIR):up:down \
    geoserver:$(GEOSERVER_DIR):up:down \
    sieej:$(SIEEJ_DIR):build:down \
    mariachi:$(MARIACHI_DIR):deploy:down:ENV=prod \
    mapalab:$(MAPALAB_DIR):deploy:down \
    gateway:.:deploy:down

GATEWAY_FILES := -f docker-compose.yml
STACKS ?=

C_BOLD := \033[1m
C_DIM := \033[2m
C_GREEN := \033[0;32m
C_RED := \033[0;31m
C_YELLOW := \033[0;33m
C_CYAN := \033[0;36m
C_RESET := \033[0m

help:
	@echo ""
	@echo "Gateway Hub"
	@echo ""
	@echo "  up              Iniciar gateway-hub (sin rebuildear)"
	@echo "  deploy          Detener + rebuild + levantar gateway-hub"
	@echo "  down            Detener gateway-hub"
	@echo ""
	@echo "Ecosistema:"
	@echo ""
	@echo "  ecosystem-up          Levantar todo el ecosistema en orden topologico"
	@echo "  ecosystem-down        Detener todo el ecosistema en orden inverso"
	@echo "  ecosystem-deploy      Pull + down + deploy de todo el ecosistema"
	@echo "  ecosystem-status      Estado del ecosistema: git, docker y errores en logs"
	@echo ""
	@echo "  Filtro: STACKS=mariachi,mapalab make ecosystem-up"
	@echo ""

up:
	@echo ""
	@echo -e "  $(C_BOLD)GATEWAY HUB — UP$(C_RESET)"
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
	@if docker network inspect $(NETWORK_NAME) >/dev/null 2>&1; then \
	     echo -e "  Red           $(C_GREEN)ya existe$(C_RESET)    ($(NETWORK_NAME))"; \
	 else \
	     docker network create $(NETWORK_NAME) >/dev/null 2>&1 && echo -e "  Red           $(C_GREEN)creada$(C_RESET)      ($(NETWORK_NAME))"; \
	 fi
	@SIEEJ_DIST_PATH=$$(grep -E '^SIEEJ_DIST_PATH=' .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'); \
	 SIEEJ_DIST_PATH=$${SIEEJ_DIST_PATH:-../sieej/frontend/dist}; \
	 if [ -d "$$SIEEJ_DIST_PATH" ]; then \
	     echo -e "  SIEEJ dist    $(C_GREEN)OK$(C_RESET)           $$SIEEJ_DIST_PATH"; \
	 else \
	     echo -e "  SIEEJ dist    $(C_RED)ERROR$(C_RESET)         $$SIEEJ_DIST_PATH no existe"; \
	     echo ""; \
	     echo "  Construye el dist primero: make -C $(SIEEJ_DIR) build"; \
	     exit 1; \
	 fi
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
	@printf "  $(C_DIM)...%s$(C_RESET) " "Up"; \
	 docker compose $(GATEWAY_FILES) up -d > /tmp/gateway-up.log 2>&1 & pid=$$!; \
	 sp='⣾⣽⣻⢿⡿⣟⣯⣷'; start=$$(date +%s); i=0; elapsed=0; \
	 while kill -0 $$pid 2>/dev/null; do \
	     now=$$(date +%s); elapsed=$$((now - start)); \
	     frame="$${sp:$$((i % 8)):1}"; \
	     printf "\r\033[K  $(C_DIM)...%s$(C_RESET)  %s  %02d:%02d" "Up" "$$frame" "$$((elapsed/60))" "$$((elapsed%60))"; \
	     sleep 0.15; \
	     i=$$((i+1)); \
	 done; \
	 printf "\r\033[K"; \
	 set +e; wait $$pid; rc=$$?; set -e; \
	 if [ $$rc -eq 0 ]; then \
	     printf "  $(C_GREEN)Up$(C_RESET)            ok  %02d:%02d\n" "$$((elapsed/60))" "$$((elapsed%60))"; \
	 else \
	     printf "  $(C_RED)Up$(C_RESET)            fail  %02d:%02d\n" "$$((elapsed/60))" "$$((elapsed%60))"; \
	     tail -40 /tmp/gateway-up.log | while IFS= read -r line; do echo "         $$line"; done; \
	     rm -f /tmp/gateway-up.log; \
	     exit 1; \
	 fi; \
	 rm -f /tmp/gateway-up.log
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
	@echo ""

deploy:
	@echo ""
	@deploy_start=$$(date +%s); \
	 echo -e "  $(C_BOLD)GATEWAY HUB — DEPLOY$(C_RESET)"; \
	 echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"; \
	 if docker network inspect $(NETWORK_NAME) >/dev/null 2>&1; then \
	     echo -e "  Red           $(C_GREEN)ya existe$(C_RESET)    ($(NETWORK_NAME))"; \
	 else \
	     docker network create $(NETWORK_NAME) >/dev/null 2>&1 && echo -e "  Red           $(C_GREEN)creada$(C_RESET)      ($(NETWORK_NAME))"; \
	 fi; \
	 version=$$(cat VERSION 2>/dev/null || echo "?"); \
	 echo -e "  Version       $(C_GREEN)$$version$(C_RESET)"; \
	 ./scripts/gen-version-json.sh 2>&1 | while IFS= read -r line; do \
	     case "$$line" in \
	         *WARN*) echo -e "               $(C_YELLOW)$$line$(C_RESET)" ;; \
	         *)      echo -e "               $(C_DIM)$$line$(C_RESET)" ;; \
	     esac; \
	 done; \
	 SIEEJ_DIST_PATH=$$(grep -E '^SIEEJ_DIST_PATH=' .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'); \
	 SIEEJ_DIST_PATH=$${SIEEJ_DIST_PATH:-../sieej/frontend/dist}; \
	 if [ -d "$$SIEEJ_DIST_PATH" ]; then \
	     echo -e "  SIEEJ dist    $(C_GREEN)OK$(C_RESET)           $$SIEEJ_DIST_PATH"; \
	 else \
	     echo -e "  SIEEJ dist    $(C_RED)ERROR$(C_RESET)         $$SIEEJ_DIST_PATH no existe"; \
	     echo ""; \
	     echo "  Construye el dist primero: make -C $(SIEEJ_DIR) build"; \
	     exit 1; \
	 fi; \
	 echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"; \
	 if output=$$(docker compose $(GATEWAY_FILES) down 2>&1); then \
	     echo -e "  Down          $(C_GREEN)ok$(C_RESET)"; \
	 else \
	     echo -e "  Down          $(C_RED)fail$(C_RESET)"; \
	     echo "$$output" | tail -40 | while IFS= read -r line; do echo "         $$line"; done; \
	     exit 1; \
	 fi; \
	 echo ""; \
	 printf "  $(C_DIM)...%s$(C_RESET) " "Build+Up"; \
	 docker compose $(GATEWAY_FILES) up -d --build > /tmp/gateway-build.log 2>&1 & pid=$$!; \
	 sp='⣾⣽⣻⢿⡿⣟⣯⣷'; start=$$(date +%s); i=0; elapsed=0; \
	 while kill -0 $$pid 2>/dev/null; do \
	     now=$$(date +%s); elapsed=$$((now - start)); \
	     frame="$${sp:$$((i % 8)):1}"; \
	     printf "\r\033[K  $(C_DIM)...%s$(C_RESET)  %s  %02d:%02d" "Build+Up" "$$frame" "$$((elapsed/60))" "$$((elapsed%60))"; \
	     sleep 0.15; \
	     i=$$((i+1)); \
	 done; \
	 printf "\r\033[K"; \
	 set +e; wait $$pid; rc=$$?; set -e; \
	 if [ $$rc -eq 0 ]; then \
	     printf "  $(C_GREEN)Build+Up$(C_RESET)      ok  %02d:%02d\n" "$$((elapsed/60))" "$$((elapsed%60))"; \
	 else \
	     printf "  $(C_RED)Build+Up$(C_RESET)      fail  %02d:%02d\n" "$$((elapsed/60))" "$$((elapsed%60))"; \
	     tail -40 /tmp/gateway-build.log | while IFS= read -r line; do echo "         $$line"; done; \
	     rm -f /tmp/gateway-build.log; \
	     exit 1; \
	 fi; \
	 rm -f /tmp/gateway-build.log; \
	 echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"; \
	 deploy_end=$$(date +%s); \
	 total=$$((deploy_end - deploy_start)); \
	 echo ""; \
	 printf "  $(C_GREEN)Deploy completado$(C_RESET)  %02d:%02d\n" "$$((total/60))" "$$((total%60))"; \
	 echo ""

down:
	docker compose $(GATEWAY_FILES) down

ecosystem-up:
	@echo ""
	@echo -e "  $(C_BOLD)ECOSISTEMA — UP + BUILD$(C_RESET)"
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
	@STEPS="$(ECOSYSTEM_STEPS)"; \
	 FILTER="$(STACKS)"; \
	 SELECTED=""; \
	 for step in $$STEPS; do \
	     name=$$(echo $$step | cut -d: -f1); \
	     if [ -z "$$FILTER" ] || echo ",$$FILTER," | grep -q ",$$name,"; then \
	         SELECTED="$$SELECTED $$step"; \
	     fi; \
	 done; \
	 for step in $$SELECTED; do \
	     name=$$(echo $$step | cut -d: -f1); \
	     dir=$$(echo $$step | cut -d: -f2); \
	     tgt=$$(echo $$step | cut -d: -f3); \
	     extra=$$(echo $$step | cut -d: -f5); \
	     if [ -d "$$dir" ]; then \
	         printf "  $(C_DIM)...%s$(C_RESET) " "$$name"; \
	         $(MAKE) -C $$dir $$tgt $$extra > /tmp/ecosystem-up-$$name.log 2>&1 & pid=$$!; \
	         sp='⣾⣽⣻⢿⡿⣟⣯⣷'; start=$$(date +%s); i=0; elapsed=0; \
	         while kill -0 $$pid 2>/dev/null; do \
	             now=$$(date +%s); elapsed=$$((now - start)); \
	             frame="$${sp:$$((i % 8)):1}"; \
	             printf "\r\033[K  $(C_DIM)...%s$(C_RESET)  %s  %02d:%02d" "$$name" "$$frame" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             sleep 0.15; \
	             i=$$((i+1)); \
	         done; \
	         printf "\r\033[K"; \
	         set +e; wait $$pid; rc=$$?; set -e; \
	         if [ $$rc -eq 0 ]; then \
	             printf "  $(C_GREEN)ok$(C_RESET)            %-14s %02d:%02d\n" "$$name" "$$((elapsed/60))" "$$((elapsed%60))"; \
	         else \
	             printf "  $(C_RED)fail$(C_RESET)          %-14s %02d:%02d\n" "$$name" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             tail -40 /tmp/ecosystem-up-$$name.log | while IFS= read -r line; do echo "         $$line"; done; \
	             rm -f /tmp/ecosystem-up-$$name.log; \
	             exit 1; \
	         fi; \
	         rm -f /tmp/ecosystem-up-$$name.log; \
	     else \
	         printf "  $(C_DIM)skip$(C_RESET)          %s\n" "$$name"; \
	     fi; \
	 done
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
	@echo ""
	@$(MAKE) ecosystem-status

ecosystem-down:
	@echo ""
	@echo -e "  $(C_BOLD)ECOSISTEMA — DOWN$(C_RESET)"
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
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
	     extra=$$(echo $$step | cut -d: -f5); \
	     if [ -d "$$dir" ]; then \
	         printf "  $(C_DIM)...%s$(C_RESET) " "$$name"; \
	         $(MAKE) -C $$dir $$tgt $$extra > /tmp/ecosystem-down-$$name.log 2>&1 & pid=$$!; \
	         sp='⣾⣽⣻⢿⡿⣟⣯⣷'; start=$$(date +%s); i=0; elapsed=0; \
	         while kill -0 $$pid 2>/dev/null; do \
	             now=$$(date +%s); elapsed=$$((now - start)); \
	             frame="$${sp:$$((i % 8)):1}"; \
	             printf "\r\033[K  $(C_DIM)...%s$(C_RESET)  %s  %02d:%02d" "$$name" "$$frame" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             sleep 0.15; \
	             i=$$((i+1)); \
	         done; \
	         printf "\r\033[K"; \
	         set +e; wait $$pid; rc=$$?; set -e; \
	         if [ $$rc -eq 0 ]; then \
	             printf "  $(C_GREEN)ok$(C_RESET)            %-14s %02d:%02d\n" "$$name" "$$((elapsed/60))" "$$((elapsed%60))"; \
	         else \
	             if ( cd "$$dir" && docker compose down ) > /tmp/ecosystem-down-fb-$$name.log 2>&1; then \
	                 printf "  $(C_GREEN)ok$(C_RESET)            %-14s %02d:%02d\n" "$$name" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             elif ( cd "$$dir" && for f in docker-compose.yml compose.yml docker-compose.yaml compose.yaml; do [ -f "$$f" ] && docker compose -f "$$f" down && exit 0; done; exit 1 ) > /tmp/ecosystem-down-fb-$$name.log 2>&1; then \
	                 printf "  $(C_GREEN)ok$(C_RESET)            %-14s %02d:%02d\n" "$$name" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             else \
	                 printf "  $(C_RED)fail$(C_RESET)          %-14s %02d:%02d\n" "$$name" "$$((elapsed/60))" "$$((elapsed%60))"; \
	                 tail -40 /tmp/ecosystem-down-$$name.log | while IFS= read -r line; do echo "         $$line"; done; \
	                 tail -40 /tmp/ecosystem-down-fb-$$name.log | while IFS= read -r line; do echo "         $$line"; done; \
	             fi; \
	             rm -f /tmp/ecosystem-down-fb-$$name.log; \
	         fi; \
	         rm -f /tmp/ecosystem-down-$$name.log; \
	     else \
	         printf "  $(C_DIM)skip$(C_RESET)          %s\n" "$$name"; \
	     fi; \
	 done
	@echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"
	@echo ""

ecosystem-deploy:
	@echo ""
	@deploy_start=$$(date +%s); \
	 echo -e "  $(C_BOLD)ECOSISTEMA — DEPLOY$(C_RESET)"; \
	 echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"; \
	 echo -e "  $(C_CYAN)Pull ...$(C_RESET)"; \
	 section_start=$$(date +%s); \
	 STEPS="$(ECOSYSTEM_STEPS)"; \
	 FILTER="$(STACKS)"; \
	 for step in $$STEPS; do \
	     name=$$(echo $$step | cut -d: -f1); \
	     dir=$$(echo $$step | cut -d: -f2); \
	     if [ -z "$$FILTER" ] || echo ",$$FILTER," | grep -q ",$$name,"; then \
	     if [ -d "$$dir/.git" ]; then \
	         branch=$$(git -C "$$dir" branch --show-current 2>/dev/null || echo "?"); \
	         printf "  $(C_DIM)...%s$(C_RESET) " "$$name"; \
	         git -C "$$dir" pull --ff-only > /tmp/ecosystem-pull-$$name.log 2>&1 & pid=$$!; \
	         sp='⣾⣽⣻⢿⡿⣟⣯⣷'; start=$$(date +%s); i=0; elapsed=0; \
	         while kill -0 $$pid 2>/dev/null; do \
	             now=$$(date +%s); elapsed=$$((now - start)); \
	             frame="$${sp:$$((i % 8)):1}"; \
	             printf "\r\033[K  $(C_DIM)...%s$(C_RESET)  %s  %02d:%02d" "$$name" "$$frame" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             sleep 0.15; \
	             i=$$((i+1)); \
	         done; \
	         printf "\r\033[K"; \
	         set +e; wait $$pid; rc=$$?; set -e; \
	         if [ $$rc -eq 0 ]; then \
	             printf "  $(C_GREEN)ok$(C_RESET)            %-14s %-12s %02d:%02d\n" "$$name" "$$branch" "$$((elapsed/60))" "$$((elapsed%60))"; \
	         else \
	             printf "  $(C_RED)fail$(C_RESET)          %-14s %-12s %02d:%02d\n" "$$name" "$$branch" "$$((elapsed/60))" "$$((elapsed%60))"; \
	             tail -40 /tmp/ecosystem-pull-$$name.log | while IFS= read -r line; do echo "         $$line"; done; \
	         fi; \
	         rm -f /tmp/ecosystem-pull-$$name.log; \
	         elif [ -d "$$dir" ]; then \
	             printf "  $(C_DIM)n/a$(C_RESET)           %s\n" "$$name"; \
	         else \
	             printf "  $(C_DIM)skip$(C_RESET)          %s\n" "$$name"; \
	         fi; \
	     fi; \
	 done; \
	 section_end=$$(date +%s); \
	 section_elapsed=$$((section_end - section_start)); \
	 echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"; \
	 printf "  $(C_DIM)Pull total$(C_RESET)    %02d:%02d\n\n" "$$((section_elapsed/60))" "$$((section_elapsed%60))"; \
	 section_start=$$(date +%s); \
	 $(MAKE) ecosystem-down; \
	 section_end=$$(date +%s); \
	 section_elapsed=$$((section_end - section_start)); \
	 printf "  $(C_DIM)Down total$(C_RESET)    %02d:%02d\n\n" "$$((section_elapsed/60))" "$$((section_elapsed%60))"; \
	 section_start=$$(date +%s); \
	 $(MAKE) ecosystem-up; \
	 section_end=$$(date +%s); \
	 section_elapsed=$$((section_end - section_start)); \
	 printf "  $(C_DIM)Up total$(C_RESET)      %02d:%02d\n" "$$((section_elapsed/60))" "$$((section_elapsed%60))"; \
	 total_end=$$(date +%s); \
	 total_elapsed=$$((total_end - deploy_start)); \
	 echo ""; \
	 echo -e "  $(C_DIM)------------------------------------------$(C_RESET)"; \
	 printf "  $(C_BOLD)Total$(C_RESET)         %02d:%02d\n" "$$((total_elapsed/60))" "$$((total_elapsed%60))"; \
	 echo ""

ecosystem-status:
	@./scripts/ecosystem-status.sh "$(REPOS_DIR)" "$(GATEWAY_DIR)"
