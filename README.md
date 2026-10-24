# vweb-mark1

`vweb-mark1` is a local Docker Compose environment for a certificate-bound,
OIDC-authenticated web platform. It contains two independent services with V
back ends and Vue 3/Vuetify front ends.

## Architecture

- OpenResty is the only public application entry point and enforces mTLS and
  the OIDC BFF session boundary.
- Keycloak owns the `vweb` realm, users, email verification, groups, and roles.
- PostgreSQL stores Keycloak data, BFF sessions, and service-owned authorization
  data.
- step-ca issues the local private-PKI certificates.
- `service-a` and `service-b` each have an independent front end and V back end.
- The mailserver and Roundcube run as an independent mail stack.

The detailed English design is in [`docs/src/en/`](docs/src/en/). The Japanese
translation is in [`docs/src/jp/`](docs/src/jp/).

## Requirements

- Docker Desktop with Docker Compose
- `curl`, `jq`, and `keytool` on the host
- V for local back-end tests
- mdBook for documentation builds

## Quick start

Create the local environment file and replace every placeholder with a
development-only value:

```bash
cp .env.example .env
make compose-config
make up
```

Add the development hostname before opening the browser:

```bash
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
```

Open Service A at <https://vweb.local/service-a/> or Service B at
<https://vweb.local/service-b/>. The browser must have the issued client
certificate installed. Roundcube is independent from OpenResty and is
available at <http://127.0.0.1:3005/>.

`make up` performs initialization through Make targets and scripts. It does not
create dedicated migration or initialization containers. Use `make down` for a
normal stop; do not use `docker compose down -v` because it removes persistent
PostgreSQL and step-ca data.

## Common commands

```bash
make up                # Build and start the complete local environment
make logs SERVICE=...  # Follow logs for a Compose service
make migrate           # Apply service database migrations
make seed-keycloak     # Seed the vweb realm and development users
make user-passwords    # Write the ignored local credential list
make test-v            # Run V tests
make build-front       # Build both Vue applications
make docs              # Build the mdBook
make down              # Stop containers and preserve volumes
```

Service member creation requires a non-blank email address matching the
existing Keycloak user. Keycloak rejects duplicate email addresses, and each
service database also enforces case-insensitive email uniqueness.

## Secret handling

Never commit `.env`, `private/`, generated certificates, private keys, access
tokens, client secrets, or local credential lists. The repository contains only
the safe `.env.example` template. Development values must remain local and
must never be reused in production.

## License

This project is licensed under the [MIT License](LICENSE).
