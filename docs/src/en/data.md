# Data Design

## Database separation

PostgreSQL hosts separate logical databases and users so that Keycloak and the
application do not share ownership of each other's tables.

| Database | Owner | Contents |
|---|---|---|
| `keycloak` | `keycloak` | Realm, client, user, role, and Keycloak session data |
| `vweb` | `service_a` and `service_b` schemas | BFF sessions, service-scoped application tables, and audit data as required |
| `roundcube` | `roundcube` | Roundcube identities, preferences, and mailbox metadata |

Each service back owns its service-scoped User, Group, Role, Policy, and
Member records. The initial database may remain a shared `vweb` database, but
service ownership must be separated by schema or table prefix and enforced by
the service API. A service must not directly modify another service's
authorization tables.

The first-start SQL creates the databases, users, schemas, and minimum
database connectivity grants, and is mounted read-only into the PostgreSQL
container. The idempotent `make init-roundcube` target also creates the
Roundcube role and database when an existing PostgreSQL volume predates the
mail UI. Service migrations run with `make migrate`, separately from
PostgreSQL bootstrap and without dedicated migration containers.
`make init-postgres` reruns the idempotent bootstrap for an existing volume,
and `make sync-postgres-roles` aligns application role passwords with the
current local `.env` values.

## BFF session tables

The OpenResty session adapter creates the following tables in the `bff` schema:

| Column | Description |
|---|---|
| `sessions.sid` | Unpredictable hashed session ID; primary key |
| `sessions.name` | Session cookie name |
| `sessions.data` | Encrypted serialized session data |
| `sessions.exp` | Session expiration timestamp |
| `sessions_meta.aud` | Session audience |
| `sessions_meta.sub` | Keycloak subject |
| `sessions_meta.sid` | Foreign key to `sessions.sid` |

The browser receives only an opaque session ID in the BFF cookie. Token
encryption uses `SESSION_ENCRYPTION_KEY` from the ignored local `.env` file.
Session cleanup must remove expired rows and revoke server-side sessions during
logout.

## Service authorization entities

| Entity | Required fields | Purpose |
|---|---|---|
| User | `id`, `keycloak_sub`, unique non-blank `email`, profile reference, timestamps | Local identity projection |
| Group | `id`, `parent_group_id`, `name`, `path`, `description`, `keycloak_id`, timestamps | Service-scoped hierarchical group and its Keycloak projection reference |
| Role | `id`, `service_id`, `name`, capability definition, timestamps | Named service capability set |
| Policy | `id`, `service_id`, resource, action, effect, condition | Authorization rule |
| Member | `id`, `group_id`, `user_id`, timestamps | User membership in a group |
| MemberRole | `member_id`, `role_id`, timestamps | Role assignment to a group member |

The service back end is the authority for these records. Keycloak group paths
and user/group membership are projections used to provide authentication
context. The service repository calls the Keycloak Admin API over mTLS for
those projections and stores service-specific descriptions, profiles, and
member roles in PostgreSQL. A group delete is rejected while it still has
members or child groups; Keycloak users are never deleted by member deletion.

The initial management endpoints are:

| Method | Path | Behavior |
|---|---|---|
| `GET` | `/v1/groups` | List service groups from PostgreSQL |
| `POST` | `/v1/groups` | Create a group in PostgreSQL and under `/services/<service>/groups` in Keycloak |
| `PATCH`, `DELETE` | `/v1/groups/:group_id` | Update or remove both projections |
| `GET`, `POST` | `/v1/groups/:group_id/members` | List or add an existing Keycloak user to a service group |
| `GET` | `/v1/members` | List all service members; service administrator only |
| `GET`, `PATCH`, `DELETE` | `/v1/members/:member_id` | Read, update profile/roles, or remove group membership |

Member creation requires an existing Keycloak subject and a non-blank email
address that matches the Keycloak user's email. A service-owned user projection
cannot be created with an empty or duplicate email address; the uniqueness
check is case-insensitive. Adding the same Keycloak user to multiple groups is
allowed, while registering a different user with an existing email is rejected.
Email and display name updates call Keycloak first and then update the
service-owned PostgreSQL user projection. Role names in a member request are
resolved against the service's PostgreSQL `roles` table.

## Development sample dataset

The Makefile seed flow creates a non-production dataset:

| Scope | Users | Groups | Contents |
|---|---:|---:|---|
| Keycloak `vweb` realm | 20 shared users | 5 under `service-a`, 5 under `service-b` | Service-admin and group-admin/editor/viewer mappings |
| `service-a` schema | 20 | 5 | Users, groups, roles, policies, members, and member roles |
| `service-b` schema | 20 | 5 | Users, groups, roles, policies, members, and member roles |

Usernames use `sample-user-01` through `sample-user-20`, with matching email
addresses from `sample-user-01@vweb.local` through `sample-user-20@vweb.local`.
The first ten email addresses are seeded as verified and the remaining ten as
unverified. The password is provided at runtime with
`KEYCLOAK_SAMPLE_USER_PASSWORD` and must be replaced with a development-only
value in `.env`. The seed operation is idempotent and must never be enabled
with production credentials.

The sample access matrix intentionally covers service-wide, group-scoped,
cross-service, multi-group, multi-role, and no-membership cases:

| Users | Sample access pattern |
|---|---|
| `01` | `platform-admin`, both service administrators |
| `02` | `service-a-admin` |
| `03` | `service-b-admin` |
| `04` | Service A administrator; Service B group-a viewer |
| `05` | Service B administrator; Service A group-b editor |
| `06` | group-a administrator in A; group-b administrator in B |
| `07` | group-a editor in A; group-b editor in B |
| `08` | group-a viewer in A; group-b viewer in B |
| `09` | A group-b administrator and group-c viewer; B group-c administrator |
| `10` | A group-b editor; B group-b viewer |
| `11` | A group-c viewer; B group-d viewer; unverified email |
| `12` | A group-c editor; B group-c administrator; unverified email |
| `13` | A group-d administrator; B group-e editor; unverified email |
| `14` | A group-d editor; B group-e viewer; unverified email |
| `15` | A group-e viewer; B group-a editor; unverified email |
| `16` | administrator and editor in A group-a and B group-b; unverified email |
| `17` | group-b viewer in both services; unverified email |
| `18` | group-c editor in both services; unverified email |
| `19` | Authenticated user with no service membership; unverified email |
| `20` | A group-e viewer; B group-e administrator; unverified email |

The Keycloak seed resets generated sample memberships before applying this
matrix. The service migrations perform the equivalent reset for generated
PostgreSQL members and member roles, so rerunning `make seed-keycloak` and
`make migrate` converges an existing local environment to the same dataset.

## Application data

Application entities and indexes are intentionally deferred until the business
domain is defined. New tables must specify:

- ownership and migration order;
- primary and foreign keys;
- audit timestamps;
- authorization scope;
- retention and backup requirements;
- expected query patterns and indexes.

## Backup and recovery

Back up PostgreSQL data independently from step-ca data. Recovery planning
must cover:

- the `keycloak` database;
- the `vweb` database;
- BFF session behavior after restore;
- the step-ca root/intermediate keys and certificates;
- the order in which PostgreSQL, step-ca, Keycloak, and OpenResty are restored.

Do not use `docker compose down -v` as a normal shutdown operation because it
removes persistent volumes.

The development docker-mailserver follows the `cmn-core` sandbox pattern and
uses tmpfs for mailbox and mail-log directories. Mail content is therefore
ephemeral until a production persistence policy is designed.

