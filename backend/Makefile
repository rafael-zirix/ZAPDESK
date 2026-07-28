.PHONY: dev build tidy up down logs

# Sobe Postgres + API para desenvolvimento.
up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f api

# Roda a API localmente (precisa do Postgres no ar: make up).
dev:
	go run ./cmd/api

build:
	CGO_ENABLED=0 go build -o bin/api ./cmd/api

tidy:
	go mod tidy
