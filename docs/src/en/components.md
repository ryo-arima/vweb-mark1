# Component Design

## Service back ends

Each service back end implements service logic and is not directly exposed to
browsers. `service-a/back` and `service-b/back` follow the directory and layer
structure described in [Service Layout](service-layout.md), based on the
`cmn-core` repository. HTTP-specific handling is separated from the domain,
application, and infrastructure layers.

The current HTTP scaffold uses Veb, V's standard web framework. The
PostgreSQL repository boundary is used by `/readyz` to verify database
connectivity without exposing credentials to the HTTP adapter. Every service
back end exposes separate `/healthz` and `/readyz` checks and keeps service
rules independent from the HTTP adapter.

The back-end repository is split into `psql.v` and `keycloak.v` behind the
authorization repository facade. `psql.v` owns service-scoped Users, Groups,
Members, and MemberRoles, while `keycloak.v` uses a service account and a
service-specific mTLS certificate to call the Keycloak Admin API. Group and
member mutations update the Keycloak projection through that API and persist
service details in PostgreSQL; the back end never writes Keycloak tables.

The management API provides authenticated CRUD routes for `/v1/groups`,
`/v1/groups/:group_id/members`, and `/v1/members/:member_id`, plus a service
administrator-only `/v1/members` list. The Vue UI provides Overview, Groups,
and Members screens through a Vuetify navigation drawer. Service
administrators can open every list screen; group-scoped users remain limited
to the groups granted in their session.

The UI asks the authorization decision endpoint before rendering privileged
controls. Service group creation, group editing, and deletion are shown only
to service administrators; member mutations are shown only to users who can
manage the selected group. The all-members screen is hidden from the drawer
and displays an explanatory message when a non-service administrator opens its
route directly. These checks improve usability but do not replace back-end
authorization. The member form requires an email address, sends it with a new
member request, and displays the API conflict when the address is already in
use.

## Vue UI

- Use Vue 3.
- Use Vuetify 4 with the Vite auto-import plugin for the service UI.
- Call APIs through same-origin relative paths such as
  `/api/service-a/v1/...`.
- Do not store access tokens in `localStorage`.
- Use the HttpOnly session cookie issued by the BFF.
- Keep CORS unnecessary by serving the UI and API on one origin.

Roundcube is an independent third-party UI container connected to the
`mailserver`, `dns`, and dedicated Roundcube PostgreSQL database; it has no
OpenResty dependency. Service UIs are served by `service-a/front` and
`service-b/front` through the authenticated OpenResty routes.

## OpenResty BFF

OpenResty combines Nginx reverse-proxy behavior with Lua-based OIDC and
session handling.

The OpenResty image pins `lua-resty-openidc` 1.8.0 because it is compatible
with the `lua-resty-session` 4.x API used for PostgreSQL-backed sessions.

| Route | Responsibility |
|---|---|
| `/service-a/`, `/service-b/` | Serve Vue static files for each service |
| `/` | Redirect to `/service-a/` after BFF authentication |
| `/auth/login` | Start the OIDC authorization-code flow |
| `/auth/callback` | Validate the callback and exchange the code with Keycloak over mTLS |
| `/auth/logout` | Remove the BFF session and return to the application entry point |
| `/auth/session` | Return the current login state to the UI |
| `/api/service-a/v1/*` | Check the BFF session and proxy to `service-a/back` |
| `/api/service-b/v1/*` | Check the BFF session and proxy to `service-b/back` |
| `/healthz` | Provide an internal health endpoint |
| `/auth/realms/*` | Proxy only the Keycloak protocol paths required by the flow |

The browser receives only an opaque session ID. Access and refresh tokens are
encrypted before being stored in PostgreSQL. The local Compose environment
supplies the session encryption key and BFF database password through `.env`,
which is ignored by Git and must not be published.

## Keycloak

- Use `vweb` as the initial realm name.
- Register a confidential BFF client such as `vweb-bff`.
- Use Authorization Code Flow with PKCE (S256).
- Keep Direct Access Grants disabled unless a later requirement explicitly
  justifies them.
- Use the `platform-admin` realm role and the service/group roles defined in
  [Keycloak Authorization Model](keycloak-authorization.md).
- Create `service-a-api` and `service-b-api` confidential service-account
  clients during seeding. Their secrets remain in `.env`, and their
  `manage-users`, `query-clients`, `query-groups`, `query-users`, `view-clients`,
  and `view-users` permissions
  are used only from the corresponding private service network.
- Do not expose the `master` realm Admin Console or Admin API through public
  OpenResty routes.
- Configure Keycloak's public URL as the OpenResty URL and keep the internal
  service address separate.

The platform/service/group authorization hierarchy is defined in
[Keycloak Authorization Model](keycloak-authorization.md). Keycloak provides
identity, coarse roles, and group-path claims; each service back end evaluates
its canonical Role, Policy, and Member records.

## step-ca

step-ca is the private PKI and must have persistent CA data. The initial
certificate issuance flow creates at least:

- An OpenResty server certificate with the public development/prod DNS names.
- A Keycloak server certificate with the internal Keycloak DNS name.
- An OpenResty client certificate for the Keycloak backend connection.
- Client/device certificates for approved browser or API clients.

The SAN and provisioner policy must restrict certificates to their intended
identities. Certificate renewal must not require replacing the CA root.

## PostgreSQL

Use one PostgreSQL instance with separate logical databases and users:

| Database | Owner | Purpose |
|---|---|---|
| `keycloak` | `keycloak` | Keycloak internal data |
| `vweb` | `service_a` and `service_b` schemas | BFF sessions and service application data |
| `roundcube` | `roundcube` | Roundcube metadata and preferences |

The initial SQL follows the `cmn-core` pattern: create databases and users on
first initialization, grant each owner access only to its database, and keep
database initialization scripts read-only when mounted into the container.
The independent mail stack uses the idempotent `make init-roundcube` target
for existing PostgreSQL volumes. Service migrations are run by `make migrate`
against the already-running PostgreSQL container rather than by dedicated
migration containers.

