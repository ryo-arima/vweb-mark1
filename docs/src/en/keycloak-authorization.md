# Keycloak Authorization Model

## Design goal

The authorization hierarchy is:

```text
platform-admin
└── service-a-admin                         # Same pattern for service-b and later services
    └── group-a
        ├── group-admin
        ├── group-editor
        └── group-viewer
```

The same hierarchy is applied independently for every service. A user may be
an administrator in one service and a viewer in a group belonging to another
service.

## Responsibility split

Keycloak is the identity provider and the source of coarse-grained identity
claims. Each service back end is the source of truth for its own service
authorization data.

| Concept | Keycloak representation | Service back-end representation | Source of truth |
|---|---|---|---|
| User | Realm user and `sub` | User projection keyed by `keycloak_sub` | Keycloak identity; service projection |
| Group | Hierarchical realm group and `groups` claim | Service group record and parent relationship | Service back end |
| Role | Fixed application roles used for token context | Service role definition and assignments | Service back end |
| Policy | Optional coarse policy claim; not the initial resource-policy store | Resource, action, condition, and effect | Service back end |
| Member | Keycloak membership projection when needed | Group membership and assigned role | Service back end |

This avoids creating an unbounded number of Keycloak roles and authorization
policies for every service resource. Keycloak's groups and roles provide the
authentication context, while the service back end evaluates the final
resource policy.

## Realm and client model

Use one application realm, `vweb`. Do not use the Keycloak `master` realm's
`admin` role for application authorization; that role is for managing the
Keycloak server itself.

### Realm role

| Role | Meaning |
|---|---|
| `platform-admin` | Full administrative authority across all services |

`platform-admin` is an application role in the `vweb` realm. It is distinct
from the Keycloak server administrator role.

### BFF client roles

The `vweb-bff` client has service-level roles using this naming convention:

| Client role | Scope |
|---|---|
| `service-a-admin` | Administration of service A |
| `service-b-admin` | Administration of service B |

Additional services add their own service-admin role. The BFF client uses
restricted role scope mappings so that tokens contain only roles needed by the
application client.

## Group hierarchy in Keycloak

The identity projection uses hierarchical realm groups:

```text
/services
├── /service-a
│   ├── /administrators
│   └── /groups
│       └── /group-a
│           ├── /administrators
│           ├── /editors
│           └── /viewers
└── /service-b
    ├── /administrators
    └── /groups
        └── /group-b
            ├── /administrators
            ├── /editors
            └── /viewers
```

The development seed creates `group-a` through `group-e` below each
`/groups` node. The diagram shows only `group-a` as the representative shape.

The group path supplies scope and the assigned client role supplies the
capability:

| Keycloak group | Assigned client role | Service meaning |
|---|---|---|
| `/services/service-a/administrators` | `service-a-admin` | Service A administrator |
| `/services/service-a/groups/group-a/administrators` | `group-admin` | Group A administrator |
| `/services/service-a/groups/group-a/editors` | `group-editor` | Group A editor |
| `/services/service-a/groups/group-a/viewers` | `group-viewer` | Group A viewer |

The `vweb-bff` client has a group-membership mapper that includes full group
paths in the `groups` claim. The service back end must not authorize from a
role name alone; it must combine the role with the service/group path or its
service database projection.

## Service-side authorization model

The service back end owns the following concepts:

- **User:** a local projection of a Keycloak user, keyed by `keycloak_sub`.
- **Group:** a service-scoped container with a stable identifier and optional
  parent group.
- **Role:** a service-scoped named capability set, such as administrator,
  editor, or viewer.
- **Policy:** a rule that maps a role or member context to resource and action
  permissions, optionally with conditions.
- **Member:** an assignment of a user to a group with one or more roles.

The default role capabilities are:

| Role | Default authority |
|---|---|
| Service administrator | Create and manage groups, roles, and policies within the service |
| Group administrator | Add/remove group members and update member role assignments for the group |
| Group editor | Perform resource actions allowed by the group's policies |
| Group viewer | Read resources allowed by the group's policies |

Group administrators cannot create roles or policies and cannot manage a
different group. Editors and viewers cannot manage membership or authorization
configuration.

## Management flows

### Service administrator creates a group, role, or policy

1. The user authenticates through Keycloak and the BFF.
2. The service back verifies `platform-admin` or the relevant service-admin
   authority.
3. The service back updates the corresponding Keycloak group or role mapping
   through a dedicated service account.
4. After the projection succeeds, the service back persists the canonical
   service record in PostgreSQL. Projection reconciliation remains required
   for failures between these two systems.
5. The operation writes an audit record and an outbox event for reconciliation.

### Group administrator manages members

1. The group administrator calls the service member-management API.
2. The service back verifies that the caller administers the target group.
3. The service back updates the Keycloak group membership projection and role
   mapping through its service account.
4. The service back creates or updates the canonical `member` record and role
   assignment in PostgreSQL.
5. The operation is audited. The browser never receives Keycloak Admin API
   credentials.

### Role update

A group administrator may assign or replace an existing role for a member but
cannot create a new role or change a policy. Role and policy creation remains
restricted to the service administrator or `platform-admin`.

## Token and BFF handling

The BFF validates the Keycloak token and extracts:

- `sub`;
- realm roles, including `platform-admin`;
- `resource_access.vweb-bff.roles`, including service-admin and group roles;
- the `groups` claim containing hierarchical paths.

The BFF forwards only server-generated identity context to the selected service
back end. The service back end uses `keycloak_sub` to load the canonical User,
Group, Role, Policy, and Member records and performs the final authorization
decision.

## Keycloak administration boundary

The application must not expose the Keycloak Admin Console or unrestricted
Admin REST API to users. Service back ends may use separate confidential
service-account clients with the minimum required realm-management permissions
to maintain their own group projection. Those credentials are server-side
secrets and are never sent to browsers.

Keycloak Authorization Services can represent resources, scopes, permissions,
and policies, but the initial design keeps dynamic service policies in the
service database to avoid two competing policy stores. Introducing Keycloak as
the policy decision point later requires a migration and consistency design.

