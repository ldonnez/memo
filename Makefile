.PHONY: test

start:
	@docker compose start memo-sh

stop:
	@docker compose stop memo-sh

restart:
	@docker compose restart memo-sh

up:
	@docker compose up -d

log:
	@if [ -z "memo-sh" ]; then \
		docker compose logs -f --tail 10000; \
	else \
		docker compose logs -f --tail 10000 --no-log-prefix memo-sh; \
	fi

build:
	@docker compose build

shell:
	@docker compose exec memo-sh /bin/bash || { \
		printf "\033[38;5;214m[!] Fallback to 'docker compose run'\033[0m"; \
		docker compose run --rm --no-deps memo-sh /bin/bash; \
	}

test:
	@docker compose run --rm memo-sh go test -v ./...
	@docker compose run --rm memo-sh bats test/$(file)
