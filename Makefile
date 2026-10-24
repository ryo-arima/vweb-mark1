SHELL := /bin/sh

ENV_FILE ?= .env

# Load the same values for host-side bootstrap scripts that Compose uses.
-include $(ENV_FILE)

export KEYCLOAK_ADMIN
export KEYCLOAK_ADMIN_PASSWORD
export KEYCLOAK_SAMPLE_USER_PASSWORD
export KEYCLOAK_BFF_CLIENT_SECRET
export KEYCLOAK_SERVICE_A_CLIENT_SECRET
export KEYCLOAK_SERVICE_B_CLIENT_SECRET
export KEYCLOAK_TRUSTSTORE_PASSWORD
export VWEB_PUBLIC_URL
export VWEB_MAIL_ADDRESS
export VWEB_MAIL_PASSWORD

# Compose fragments are merged in the same way as cmn-core so every entry
# point uses one consistent project definition.
COMPOSE_FILES := \
	-f docker/network.yaml \
	-f docker/postgres.yaml \
	-f docker/step-ca.yaml \
	-f docker/keycloak.yaml \
	-f docker/openresty.yaml \
	-f docker/dns.yaml \
	-f docker/mailserver.yaml \
	-f docker/roundcube.yaml \
	-f docker/service-a.yaml \
	-f docker/service-b.yaml

COMPOSE := docker compose --env-file $(ENV_FILE) --project-directory . $(COMPOSE_FILES)

.PHONY: check-env host-tools prepare-pki-data prepare-mail-data compose-config up init-postgres sync-postgres-roles init-mailserver init-pki \
	seed-keycloak user-passwords migrate init-roundcube down logs build build-back build-front \
	test-v docs

check-env:
	@test -f "$(ENV_FILE)" || { \
		echo "[ERROR] $(ENV_FILE) is missing. Run: cp .env.example $(ENV_FILE)" >&2; \
		exit 1; \
	}

compose-config: check-env
	$(COMPOSE) config

host-tools: check-env
	@for tool in docker curl jq keytool; do \
		command -v "$$tool" >/dev/null 2>&1 || { \
			echo "[ERROR] Required host tool is missing: $$tool" >&2; \
			exit 1; \
		}; \
	done

prepare-pki-data:
	@mkdir -p private/pki
	@chmod 0777 private/pki

prepare-mail-data:
	@mkdir -p private/mailserver
	@chmod 0700 private/mailserver

up: check-env host-tools prepare-pki-data prepare-mail-data
	$(COMPOSE) up -d --build --remove-orphans --wait postgres step-ca dns service-a-front service-b-front
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) init-postgres
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) sync-postgres-roles
	$(COMPOSE) up -d --build mailserver
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) init-mailserver
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) init-pki
	$(COMPOSE) up -d --build --wait keycloak
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) seed-keycloak
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) migrate
	$(MAKE) --no-print-directory ENV_FILE=$(ENV_FILE) init-roundcube
	$(COMPOSE) up -d --build --wait service-a-back service-b-back roundcube openresty

init-postgres: check-env
	$(COMPOSE) exec -T postgres sh /docker-entrypoint-initdb.d/01-postgres-init.sh

sync-postgres-roles: check-env
	$(COMPOSE) exec -T postgres sh /scripts/sync-postgres-roles.sh

init-mailserver: check-env
	@test -n "$(VWEB_MAIL_ADDRESS)" || { echo "[ERROR] VWEB_MAIL_ADDRESS is required" >&2; exit 1; }
	@test -n "$(VWEB_MAIL_PASSWORD)" || { echo "[ERROR] VWEB_MAIL_PASSWORD is required" >&2; exit 1; }
	@set -eu; \
	ensure_mailbox() { \
		address="$$1"; \
		password="$$2"; \
		if $(COMPOSE) exec -T mailserver sh -c 'grep -Fq -- "$$1|" /tmp/docker-mailserver/postfix-accounts.cf' sh "$$address" 2>/dev/null; then \
			$(COMPOSE) exec -T mailserver setup email update "$$address" "$$password"; \
		else \
			$(COMPOSE) exec -T mailserver setup email add "$$address" "$$password"; \
		fi; \
	}; \
	ensure_mailbox "$$VWEB_MAIL_ADDRESS" "$$VWEB_MAIL_PASSWORD"; \
	for user_number in $$(seq 1 20); do \
		address="sample-user-$$(printf '%02d' "$$user_number")@vweb.local"; \
		ensure_mailbox "$$address" "$$KEYCLOAK_SAMPLE_USER_PASSWORD"; \
	done

init-pki: check-env host-tools prepare-pki-data
	$(COMPOSE) exec -T step-ca sh /scripts/issue-certificates.sh
	@set -eu; tmp_dir=$$(mktemp -d); \
		trap 'rm -rf "$$tmp_dir"' EXIT INT TERM; \
		mkdir -p "$$tmp_dir/ca" "$$tmp_dir/keycloak"; \
		$(COMPOSE) cp step-ca:/pki/ca/root_ca.crt "$$tmp_dir/ca/root_ca.crt"; \
		PKI_DIR="$$tmp_dir" sh scripts/pki/create-keycloak-truststore.sh; \
		$(COMPOSE) cp "$$tmp_dir/keycloak/keycloak-truststore.p12" step-ca:/pki/keycloak/keycloak-truststore.p12; \
		$(COMPOSE) exec -T step-ca chmod 0644 /pki/keycloak/keycloak-truststore.p12

seed-keycloak: check-env host-tools
	@set -eu; tmp_dir=$$(mktemp -d); \
		trap 'rm -rf "$$tmp_dir"' EXIT INT TERM; \
		mkdir -p "$$tmp_dir/ca" "$$tmp_dir/openresty"; \
		$(COMPOSE) cp step-ca:/pki/ca/root_ca.crt "$$tmp_dir/ca/root_ca.crt"; \
		$(COMPOSE) cp step-ca:/pki/openresty/client.crt "$$tmp_dir/openresty/client.crt"; \
		$(COMPOSE) cp step-ca:/pki/openresty/client.key "$$tmp_dir/openresty/client.key"; \
		PKI_DIR="$$tmp_dir" \
		VWEB_PUBLIC_URL="$$VWEB_PUBLIC_URL" \
		KEYCLOAK_URL=https://localhost:9443 \
		KEYCLOAK_REALM=vweb \
		KEYCLOAK_ADMIN_USERNAME="$$KEYCLOAK_ADMIN" \
		sh docker/keycloak-seed/seed.sh

user-passwords: check-env
	@sh scripts/keycloak/write-user-password-list.sh

migrate: check-env
	$(COMPOSE) exec -T postgres sh /scripts/run-service-migrations.sh service-a
	$(COMPOSE) exec -T postgres sh /scripts/run-service-migrations.sh service-b

init-roundcube: check-env
	$(COMPOSE) exec -T postgres sh /scripts/roundcube-init.sh

down: check-env
	$(COMPOSE) down --remove-orphans

logs: check-env
	$(COMPOSE) logs -f $(SERVICE)

build: check-env
	$(COMPOSE) build

build-back:
	docker build -t vweb/service-a-back:dev service-a/back
	docker build -t vweb/service-b-back:dev service-b/back

build-front:
	npm --prefix service-a/front install
	npm --prefix service-a/front run build
	npm --prefix service-b/front install
	npm --prefix service-b/front run build

test-v:
	v test service-a/back/test/unit
	v test service-b/back/test/unit
	v test service-a/back/pkg/server/share
	v test service-a/back/pkg/server/usecase
	v test service-a/back/pkg/server/repository
	v test service-b/back/pkg/server/share
	v test service-b/back/pkg/server/usecase
	v test service-b/back/pkg/server/repository

docs:
	mdbook build docs
