SHELL := /bin/sh
COMPOSE := docker compose --env-file .env -f compose.yaml

.PHONY: up down logs config clean-cache clean-host-cache

up:
	./scripts/up.sh

down:
	$(COMPOSE) down --remove-orphans

logs:
	$(COMPOSE) logs -f

config:
	$(COMPOSE) config

clean-cache:
	./scripts/clean-jenkins-cache.sh

clean-host-cache:
	./scripts/clean-host-cache.sh
