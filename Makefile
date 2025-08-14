singleton:
	. .env && ./scripts/docker-run.sh

build:
	COMMIT=$$(cd ./xion && git rev-parse --short HEAD) docker compose build --pull

build-no-cache:
	COMMIT=$$(cd ./xion && git rev-parse --short HEAD) docker compose build --pull --no-cache

start:
	 docker compose up -d

stop:
	docker compose stop

down:
	docker compose down

clean:
	docker compose rm -f -s -v

purge:
	docker compose rm -f -s -v
	docker volume rm -f devnet_shared
