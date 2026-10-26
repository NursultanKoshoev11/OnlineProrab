API_IMAGE ?= stroy-api:production
PRODUCTION_ENV_FILE ?= /opt/stroy-api/.env

run:
	go run ./cmd/api

test:
	go test ./...

prod-up:
	docker build --pull --file Dockerfile --tag $(API_IMAGE) .
	API_IMAGE=$(API_IMAGE) docker compose --env-file $(PRODUCTION_ENV_FILE) -f docker-compose.prod.yml up --detach --no-build --pull never --wait api

prod-logs:
	API_IMAGE=$(API_IMAGE) docker compose --env-file $(PRODUCTION_ENV_FILE) -f docker-compose.prod.yml logs -f api

prod-down:
	API_IMAGE=$(API_IMAGE) docker compose --env-file $(PRODUCTION_ENV_FILE) -f docker-compose.prod.yml down