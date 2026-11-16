# DX infra repo. The same commands as every other repo; each target is a thin
# wrapper over docker compose, and the logic lives in compose.yaml.
# Run `make` or `make help` for the list.

ENV ?= development
# Every versions.<env>.env is an environment that runs on a server. Adding a
# feature server means adding its versions file; nothing here changes.
SERVER_ENVS := $(patsubst versions.%.env,%,$(wildcard versions.*.env))

# Servers keep their env file outside the checkout: make up ENV=staging ENV_DIR=/opt/dx
ENV_DIR ?= .
ENV_FILE ?= $(ENV_DIR)/.env.$(ENV)

ifeq ($(ENV),development)
# Development builds every app image from the checkouts next to this repo
# (compose.dev.yaml), plus compose.override.yaml if you have one. The versions
# file only fills in compose.yaml's image tags, which development doesn't pull.
VERSIONS_FILE ?= versions.staging.env
COMPOSE_FILES := -f compose.yaml -f compose.dev.yaml $(if $(wildcard compose.override.yaml),-f compose.override.yaml)
else
ifeq ($(wildcard versions.$(ENV).env),)
$(error ENV=$(ENV) has no versions.$(ENV).env. Environments: development $(SERVER_ENVS))
endif
VERSIONS_FILE ?= versions.$(ENV).env
COMPOSE_FILES := -f compose.yaml -f compose.prod.yaml
endif

# One compose project per environment keeps staging's containers, networks and
# volumes apart from production's on the same host.
DC := docker compose -p dx-$(ENV) --env-file $(ENV_FILE) --env-file $(VERSIONS_FILE) $(COMPOSE_FILES)

# Without Docker (make native), the data commands (seed, backup, restore,
# script) take NATIVE=1 and use the local MongoDB and ../dx.backend instead.
NATIVE ?=

# compose.yaml reads ENV_FILE to hand the env file to the containers, and the
# scripts in scripts/ run $DC.
export ENV ENV_FILE DC NATIVE

svc ?=
only ?=

.DEFAULT_GOAL := help
.PHONY: help checkouts dev build up down logs shell migrate seed env repos native native-setup pull ps config check config-check backup restore script import-legacy

help: ## List the commands
	@echo "Usage: make <command> [ENV=development|$(subst $(eval) ,|,$(SERVER_ENVS))] [svc=<service>]"
	@echo
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'

# ----------------------------------------------------------------- the standard commands

dev: env checkouts ## Build every image from your checkouts and start the stack in Docker
	@[ "$(ENV)" = development ] || { echo "make dev is for ENV=development; use make up ENV=$(ENV)" >&2; exit 1; }
	$(DC) up -d --build --remove-orphans
	@$(DC) ps

build: env checkouts ## Build the images (development: from your checkouts next to this repo)
	$(DC) build

up: env ## Pull and start the services with ENV's settings: make up ENV=staging
	$(DC) pull --quiet --ignore-buildable
	$(DC) up -d --remove-orphans --wait --wait-timeout 600

down: env ## Stop the services (data volumes are kept)
	$(DC) down --remove-orphans

logs: env ## Follow the logs, of one service with svc=server
	$(DC) logs -f --tail=200 $(svc)

shell: env ## Open a shell in a running container: make shell svc=server
	@[ -n "$(svc)" ] || { echo "Usage: make shell svc=<service>" >&2; exit 1; }
	$(DC) exec $(svc) sh

migrate: env ## Run the server's database migrations
	$(DC) run --rm server node ./dist/migrate

seed: env ## Load the sample data in prepopulate-data/ into the database (NATIVE=1 without Docker)
	bash scripts/prepopulate.sh

# ---------------------------------------------------------------- without Docker

native: ## Run the whole stack on this machine without Docker (only="server backend" for some)
	ONLY="$(only)" bash scripts/native.sh run

native-setup: ## Run make setup in every app repo, for make native
	ONLY="$(only)" bash scripts/native.sh setup

# ----------------------------------------------------------------------------- more

repos: ## Clone the app repos next to this one, on the branches ENV follows (development: staging's)
	bash scripts/clone-repos.sh "$(VERSIONS_FILE)"

checkouts:
	@if [ "$(ENV)" = development ]; then \
	  for d in dx.client dx.server dx.backend general-ai-api; do \
	    [ -d "../$$d" ] || { echo "../$$d is missing. Clone the app repos next to this one first: make repos" >&2; exit 1; }; \
	  done; \
	fi

env: ## Check ENV's env file exists (development: create it from .env.example)
	@if [ -n "$(NATIVE)" ]; then \
	  exit 0; \
	elif [ ! -f "$(ENV_FILE)" ]; then \
	  if [ "$(ENV)" = development ]; then \
	    cp .env.example "$(ENV_FILE)" && echo "Created $(ENV_FILE) from .env.example; fill in real keys for the features you need."; \
	  else \
	    echo "$(ENV_FILE) is missing. On a server it lives in /opt/dx: make <command> ENV=$(ENV) ENV_DIR=/opt/dx" >&2; exit 1; \
	  fi; \
	fi; \
	if [ -z "$(NATIVE)" ] && [ "$(ENV)" = development ]; then \
	  mkdir -p secrets/backend secrets/server && touch secrets/backend/kaggle.json; \
	  [ -s secrets/backend/hdx_configuration.yaml ] || echo 'hdx_key: ""' > secrets/backend/hdx_configuration.yaml; \
	fi

pull: env ## Pull ENV's images
	$(DC) pull --ignore-buildable

ps: env ## List ENV's containers and their health
	$(DC) ps

config: env ## Print the full compose config ENV runs
	$(DC) config

check: ## Check the compose files render for every environment, with .env.example
	@for env in development $(SERVER_ENVS); do \
	  COMPOSE_PROFILES=cms $(MAKE) --no-print-directory config-check ENV=$$env ENV_FILE=.env.example || exit 1; \
	done
	@COMPOSE_PROFILES=cms $(MAKE) --no-print-directory config-check ENV=development ENV_FILE=.env.example \
	  COMPOSE_FILES="-f compose.yaml -f compose.dev.yaml -f compose.override.example.yaml"

config-check:
	@$(DC) config --quiet && echo "ok  $(ENV): $(COMPOSE_FILES) $(VERSIONS_FILE)"

backup: env ## Dump ENV's database into snapshots/ (mongodump; NATIVE=1 without Docker)
	bash scripts/snapshot_db.sh

restore: env ## Restore a dump into ENV's database: make restore snapshot=<name in snapshots/>
	bash scripts/snapshot_db_restore.sh "$(snapshot)"

script: env ## Run a maintenance script from scripts/ against ENV: make script name=patchCharts
	@[ -n "$(name)" ] && [ -f "scripts/$(name).sh" ] || { echo "Usage: make script name=<file in scripts/, without .sh>" >&2; exit 1; }
	bash "scripts/$(name).sh"

import-legacy: env ## One-off: copy data from the old submodule checkout: make import-legacy ENV=production OLD_DIR=/root/DX
	bash scripts/import-legacy-data.sh "$(OLD_DIR)" "$(OLD_PROJECT)"
