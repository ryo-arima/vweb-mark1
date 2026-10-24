# AI Agent Prerequisites

## Mission

Implement `vweb-mark1` according to the Basic Design Book under `docs/src/`.
The design book is the source of truth for the initial architecture. If an
implementation decision changes the design, update the relevant English
chapter in the same change and record the decision in `open-items.md` when it
cannot be resolved immediately.

## Mandatory language

- The English documentation under `docs/src/en/` is the canonical design
  source.
- The Japanese documentation under `docs/src/jp/` is the translated `/jp`
  publication and must keep the same chapter structure as the English book.
- Write all source-code, configuration, shell-script, and infrastructure
  comments in English.
- Use English for configuration keys, service names, log messages, and public
  API descriptions unless a domain requirement explicitly requires another
  language.
- When a user-facing design changes, update the English chapter first and then
  update the corresponding Japanese translation.

## Required reading before implementation

Read the English design files before making implementation changes:

1. `docs/src/SUMMARY.md`
2. `docs/src/en/index.md`
3. `docs/src/en/overview.md`
4. `docs/src/en/architecture.md`
5. `docs/src/en/service-layout.md`
6. `docs/src/en/components.md`
7. `docs/src/en/security/authentication.md`
8. `docs/src/en/data.md`
9. `docs/src/en/compose.md`
10. `docs/src/en/operations.md`
11. `docs/src/en/open-items.md`

Read the corresponding Japanese chapter when changing the published
translation under `docs/src/jp/`.

The short `docs/basic-design.md` file is only a compatibility entry point;
the single mdBook is authoritative. GitHub Pages publishes the English
chapters at `/en/` and the Japanese chapters at `/jp/`.

## Architecture invariants

- V is used for service logic in every service back end.
- Every service follows the `service-<name>/front` and
  `service-<name>/back` layout.
- Each service `back/` follows the `cmn-core` directory structure, adapted
  from Go to V.
- Each service `front/` is an independent Vite + Vue application.
- Vue 3 is used for the web UI.
- OpenResty is the only externally exposed application entry point.
- Keycloak owns OIDC authentication, users, and roles.
- step-ca owns the private PKI and issues service and client certificates.
- mTLS is required from approved clients to OpenResty and from OpenResty to
  Keycloak.
- Keycloak, all service back ends, and PostgreSQL are not directly exposed to
  clients.
- PostgreSQL stores the Keycloak database, BFF sessions, and application data.
- `platform-admin` is an application role in the `vweb` realm, not the
  Keycloak `master` realm server-admin role.
- Each service back end is the source of truth for its User, Group, Role,
  Policy, and Member records; Keycloak group paths and role mappings are
  projections for authentication context.
- The initial infrastructure is built with Docker Compose using service-level
  Compose files merged by a Makefile, following the `cmn-core` pattern.

Do not bypass the BFF by exposing Keycloak or a service back end for
convenience.
Do not replace the mTLS or OIDC boundary with a client-side token-only design.

## Implementation order

Implement in this order unless a documented dependency requires otherwise:

1. Repository and English documentation structure.
2. Compose network and PostgreSQL with separate `keycloak` and `vweb`
   databases.
3. step-ca persistence, bootstrap, certificate issuance, and renewal flow.
4. Keycloak HTTPS, trust store, client certificate requirement, realm import,
   and reverse-proxy settings.
5. OpenResty TLS, client certificate verification, OIDC BFF, session storage,
   header sanitization, and routing.
6. `service-a/back` and `service-b/back` with health endpoints,
   `cmd`, `pkg/controller`, `pkg/usecase`, `pkg/repository`, `pkg/entity`,
   `pkg/config`, PostgreSQL migrations, and BFF identity handling.
7. `service-a/front` and `service-b/front` as Vite + Vue applications using
   same-origin relative API paths and HttpOnly session cookies.
8. Integration tests for startup, certificate validation, OIDC login, session
   expiry, authorization, service routing, and API boundaries.

## Security requirements

- Never commit passwords, client secrets, private keys, CA keys, access tokens,
  refresh tokens, session encryption keys, or generated certificates.
- Never log tokens, cookie values, passwords, private keys, or full client
  certificates.
- Overwrite incoming `Host`, `Forwarded`, and `X-Forwarded-*` headers at the
  trusted proxy boundary.
- Strip client-supplied identity headers and generate them only in OpenResty.
- Keep Keycloak Admin Console and the `master` realm out of public routes.
- Use secure, HttpOnly, SameSite session cookies. Do not put access tokens in
  `localStorage`.
- Keep CA and database volumes persistent. Do not use `docker compose down -v`
  as a normal stop command.
- Bind development-only administrative ports to loopback when they must be
  exposed.

## Documentation and comments

When adding a service, endpoint, configuration item, volume, certificate, or
security rule, update the appropriate English mdBook chapter and its Japanese
translation. Keep the single `docs/src/SUMMARY.md` synchronized with both
language trees. All code and configuration comments must explain intent in
English; avoid comments that merely repeat the syntax.

## Validation expectations

At minimum, run the checks relevant to the change:

```bash
mdbook build docs
docker compose config
```

For service changes, also run the V tests and relevant integration tests. For
TLS or authentication changes, verify both successful and rejected flows,
including missing certificates, untrusted certificates, expired sessions,
invalid OIDC state, and unauthorized roles.

Do not report a feature as complete without stating which checks were run and
which checks were not possible in the current environment.

