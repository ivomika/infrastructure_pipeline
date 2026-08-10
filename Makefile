SHELL := /bin/sh
PROD_COMPOSE := COMPOSE_PROFILES=production docker compose --env-file .env -f compose.yaml
LOCAL_COMPOSE := COMPOSE_PROFILES= docker compose --env-file .env.local -f compose.yaml

.PHONY: up down restart logs config cert cert-renew \
	local-up local-down local-restart local-logs local-config \
	clean-cache local-clean-cache clean-host-cache

up:
	COMPOSE_PROFILES=production ./scripts/up.sh .env

down:
	$(PROD_COMPOSE) down --remove-orphans

restart:
	$(PROD_COMPOSE) restart $(SERVICE)

logs:
	$(PROD_COMPOSE) logs -f

config:
	$(PROD_COMPOSE) config

cert:
	NGINX_TEMPLATE_FILE=acme.conf.template $(PROD_COMPOSE) up -d --force-recreate nginx
	$(PROD_COMPOSE) run --rm certbot
	$(PROD_COMPOSE) up -d --force-recreate nginx certbot-renew

cert-renew:
	$(PROD_COMPOSE) run --rm --entrypoint certbot certbot renew --webroot --webroot-path /var/www/certbot
	$(PROD_COMPOSE) exec nginx nginx -s reload

local-up:
	COMPOSE_PROFILES= ./scripts/up.sh .env.local

local-down:
	$(LOCAL_COMPOSE) down --remove-orphans

local-restart:
	$(LOCAL_COMPOSE) restart $(SERVICE)

local-logs:
	$(LOCAL_COMPOSE) logs -f

local-config:
	$(LOCAL_COMPOSE) config

clean-cache:
	ENV_FILE=.env COMPOSE_PROFILES=production ./scripts/clean-jenkins-cache.sh

local-clean-cache:
	ENV_FILE=.env.local COMPOSE_PROFILES= ./scripts/clean-jenkins-cache.sh

clean-host-cache:
	./scripts/clean-host-cache.sh
