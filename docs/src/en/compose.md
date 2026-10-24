# Docker Compose Environment

## Compose file structure

Follow the `cmn-core` pattern: define services in separate YAML fragments and
merge them through a Makefile.

```text
docker/
├── network.yaml        # vweb-network
├── postgres.yaml       # PostgreSQL, bootstrap SQL, and healthcheck
├── step-ca.yaml        # step-ca and CA data volume
├── keycloak.yaml       # Keycloak, realm import, and TLS settings
├── openresty.yaml      # OpenResty, BFF, and Vue delivery
├── dns.yaml             # Independent mail DNS sandbox
├── mailserver.yaml      # Independent docker-mailserver sandbox
├── roundcube.yaml       # Independent Roundcube mail UI
├── service-a.yaml       # service-a front/back application services
└── service-b.yaml       # service-b front/back application services
```

The initial infrastructure Compose command treats the first five fragments as
the platform foundation. The Makefile then merges the application and
independent mail-stack fragments into the same Compose project.

```makefile
ENV_FILE ?= .env
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

up: check-env host-tools
	$(COMPOSE) up -d --build --remove-orphans --wait postgres step-ca dns service-a-front service-b-front
	$(COMPOSE) up -d --build mailserver
	$(MAKE) init-mailserver
	$(MAKE) init-pki
	$(COMPOSE) up -d --build --wait keycloak
	$(MAKE) seed-keycloak
	$(MAKE) migrate
	$(MAKE) init-roundcube
	$(COMPOSE) up -d --build --wait service-a-back service-b-back roundcube openresty
```

`make up` is the canonical container creation entry point. It requires a local
`.env` created from `.env.example`, builds local images, and starts the merged
Compose project. Initialization and migration scripts run from Make targets
against already-running long-lived containers; they do not create dedicated
one-shot Compose containers.

## Startup order

```text
postgres and step-ca healthy
       ↓
make init-postgres / sync-postgres-roles (host script)
       ↓
make init-mailserver (host script)
       ↓
make init-pki (host script)
       ↓
keycloak healthy
       ↓
make seed-keycloak (host script)
       ↓
make migrate (host script)
       ↓
make init-roundcube (host script)
       ↓
service-a/back, service-b/back, roundcube, openresty healthy

service-a-front, service-b-front, and dns are started in the first phase. The
mailserver is started before `make init-mailserver` so its first
account exists before Dovecot completes startup.
```

`make init-pki` runs the certificate script through the already-running
`step-ca` container, then creates the derived Keycloak PKCS#12 truststore on
the host and copies it into the persistent PKI volume. It does not own the CA
data and must not regenerate a new root CA on every startup.
`make seed-keycloak` runs the idempotent realm/group/user seed script on the
host over the loopback-only Keycloak bootstrap port.

Use Compose `depends_on` health conditions where supported:

- Keycloak waits for PostgreSQL; `make up` prepares the PKI before Keycloak is
  started.
- OpenResty waits for Keycloak readiness and its client/server certificates.
- OpenResty waits for `service-a-front` and `service-b-front` to pass their
  static-file health checks.
- `dns`, `mailserver`, and `roundcube` are independent of OpenResty. The mail
  stack uses the `vweb-mail-network` network and the `vweb.local` domain.
- `make init-mailserver` creates or updates the development mailbox from
  `VWEB_MAIL_ADDRESS` and `VWEB_MAIL_PASSWORD`, and creates the 20 sample
  mailboxes with `KEYCLOAK_SAMPLE_USER_PASSWORD`; docker-mailserver requires at
  least one account before it can start Dovecot.
- Keycloak joins the mail network only to send local email-verification
  messages to `mailserver`; browsers still reach mail only through the
  loopback-only Roundcube UI.
- `make migrate` runs each service migration against the healthy PostgreSQL
  container before the service back ends are started.
- `make init-roundcube` creates the Roundcube role and database against the
  healthy PostgreSQL container before Roundcube is started.

The current service migration files are
`001_authorization.sql`, `002_sample_data.sql`, `003_management.sql`,
`004_sample_access_patterns.sql`, and `005_user_email_constraints.sql` under
each service back. The third migration adds group descriptions, Keycloak
projection IDs, and management indexes. The fourth migration converges
generated sample memberships and member roles to the explicit access matrix in
the data design. The fifth migration requires a non-blank user email and adds
a case-insensitive unique index; it also consolidates duplicate legacy local
user projections before applying the constraint. They create the
service-scoped User, Group, Role, Policy, Member, and MemberRole tables. The
migration files also seed 20 users and 5 groups for each service.

`make seed-keycloak` creates the same 20 development users in the `vweb` realm,
creates five groups under each service, applies the service/group client-role
mapping, and assigns the explicit service, group, cross-service, multi-role,
and no-membership patterns documented in the data design. It also creates the `service-a-api` and `service-b-api` service
account clients and grants only the Admin API roles needed by the back-end
projection client. Each service back receives a separate mTLS client
certificate under `/pki/service-a` or `/pki/service-b`. The sample user password is read from
`KEYCLOAK_SAMPLE_USER_PASSWORD`; it is never stored in the repository.
The sample email addresses are `sample-user-01@vweb.local` through
`sample-user-20@vweb.local`; the first ten are email-verified and the remaining
ten are unverified. Keycloak is configured to allow email login, reject
duplicate email addresses, and send verification messages through the internal
mailserver. Service member creation also requires the request email to match
the existing Keycloak user's email.
Run `make user-passwords` to write a local-only tab-separated credential list
to `private/keycloak/user-passwords.txt`. The generated file includes the
Keycloak bootstrap administrator and the 20 `vweb` sample users, is created with
mode `0600`, and must never be published or reused in production.

## Local startup

```bash
cp .env.example .env
# Replace every placeholder value in .env before starting containers.
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
make compose-config
make up
```

See [Initial construction procedure](operations.md#initial-construction-procedure)
for the complete first-checkout procedure, including client certificate
installation for a browser.

Set `VWEB_MAIL_ADDRESS` and `VWEB_MAIL_PASSWORD` in `.env`. `make up` creates
or updates that mailbox before it waits for the rest of the mail stack.

The individual script targets are also available when a long-lived stack is
already running: `make init-postgres`, `make sync-postgres-roles`, `make
init-mailserver`, `make init-pki`, `make seed-keycloak`, `make migrate`, and
`make init-roundcube`. The seed target requires `curl`, `jq`, and `keytool` on
the host.

OpenResty listens on host ports 80 and 443 only. Port 80 redirects to the
canonical `https://vweb.local` URL. The service pages, API routes, and the
OIDC proxy to Keycloak are reached through the HTTPS OpenResty entry point;
the application containers are not published to the host. OpenResty first
requires the approved client certificate and then requires a Keycloak OIDC
session for the service pages. `/` redirects to `/service-a/` after
authentication, `/auth/login` starts the Authorization Code Flow with PKCE,
and API routes return `401` until the same PostgreSQL-backed BFF session is
present. Independent Roundcube is available at
`http://127.0.0.1:3005/`; service pages are available at `/service-a/` and
`/service-b/`.

OpenResty resolves the Compose names for Keycloak and service front/back
containers through Docker's embedded DNS at request time, with a short cache
window. The proxy locations strip their public path prefixes before forwarding
the request. This keeps proxying valid when a container is recreated and
receives a new IP address; static upstream addresses must not be used without
an equivalent reload strategy.

## Development ports

| Service | Container port | Development host binding | Policy |
|---|---:|---|---|
| OpenResty | 80/443 | `80:80`, `443:443` | Only public application entry point; HTTP redirects to HTTPS |
| step-ca | 9000 | `127.0.0.1:9000:9000` | Certificate bootstrap/issuance only |
| Keycloak | 8443 | `127.0.0.1:9443:8443` | Loopback-only bootstrap and seed access; public access remains through OpenResty |
| PostgreSQL | 5432 | Not published by default; loopback when needed | Database tools and migrations |
| `service-a/back` | 8000 | Not published | Reachable only through OpenResty |
| `service-b/back` | 8000 | Not published | Reachable only through OpenResty |
| `service-a/front` | 80 | Not published | Reachable only through OpenResty |
| `service-b/front` | 80 | Not published | Reachable only through OpenResty |
| `roundcube` | 80 | `127.0.0.1:3005:80` | Independent loopback-only mail UI |
| `mailserver` | 25/143/587/993 | Not published | Internal mail transport and mailbox service |
| `dns` | 53/8080 | `127.0.0.1:8053:8080` | Mail DNS sandbox and local diagnostics |

## Persistence

- PostgreSQL uses a `postgres-data` named volume.
- step-ca uses a `step-ca-data` named volume.
- docker-mailserver uses a `vweb-mail-state` named volume for Postfix and
  Dovecot runtime state; generated account hashes are kept in the ignored
  `private/mailserver` directory, while development mailbox contents and mail
  logs remain temporary.
- Issued certificates use the Git-ignored `private/pki` host directory, which is
  prepared by `make prepare-pki-data` and mounted read-only into consumers.
- CA private keys and database data must survive ordinary container restarts.
- Certificates and private keys are mounted read-only into Keycloak and
  OpenResty whenever possible.

## Healthchecks

- PostgreSQL: use `pg_isready` against the required database.
- step-ca: use its health endpoint or an equivalent CA health command.
- Keycloak: probe its internal HTTPS health/readiness endpoint.
- OpenResty: probe an internal `/healthz` route and verify required upstream
  and trust-chain files.
- Each service back: separate process liveness from database-backed readiness.

## Configuration and secrets

Keep `.env.example` limited to variable names, safe examples, and descriptions.
Use `.env` or secret files for real values. Never commit:

- PostgreSQL passwords;
- Keycloak client secrets;
- session encryption keys;
- step-ca provisioner passwords;
- private keys or generated certificates.

Development-only passwords must never be reused in production.

