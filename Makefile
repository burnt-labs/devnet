# Xion Devnet — Makefile
PROFILE ?= core
COMMIT  ?= $(shell cd ./xion && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

.PHONY: build build-no-cache start stop down clean purge logs status singleton core apps oauth zk ibc full

build:
	COMMIT=$(COMMIT) docker compose --profile $(PROFILE) build --pull

build-no-cache:
	COMMIT=$(COMMIT) docker compose --profile $(PROFILE) build --pull --no-cache

start up:
	docker compose --profile $(PROFILE) up -d

stop:
	docker compose --profile $(PROFILE) stop

down:
	docker compose --profile $(PROFILE) down

clean:
	docker compose --profile $(PROFILE) rm -f -s -v

purge:
	docker compose --profile $(PROFILE) down -v --remove-orphans

logs:
	docker compose --profile $(PROFILE) logs -f

status:
	docker compose --profile $(PROFILE) ps

core:
	$(MAKE) start PROFILE=core

apps:
	$(MAKE) start PROFILE=apps

oauth:
	$(MAKE) start PROFILE=oauth

zk:
	$(MAKE) start PROFILE=zk

ibc:
	$(MAKE) start PROFILE=ibc

full:
	$(MAKE) start PROFILE=full

singleton:
	. .env && ./scripts/docker-run.sh
