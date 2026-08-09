COMPOSE ?= docker compose

.PHONY: help init-env infra-check infra-up infra-down infra-restart infra-logs infra-ps

help: ## Show the available development commands.
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "%-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init-env: ## Create .env from .env.example when it does not exist.
	@test -f .env || cp .env.example .env

infra-check: ## Validate the resolved Docker Compose configuration.
	@$(COMPOSE) config --quiet

infra-up: init-env ## Start PostgreSQL, Redis, and pgAdmin and wait for health checks.
	@$(COMPOSE) up -d --wait

infra-down: ## Stop local infrastructure while preserving data volumes.
	@$(COMPOSE) down

infra-restart: ## Restart local infrastructure services.
	@$(COMPOSE) restart

infra-logs: ## Follow local infrastructure logs.
	@$(COMPOSE) logs --follow postgres redis pgadmin

infra-ps: ## Show local infrastructure status.
	@$(COMPOSE) ps
