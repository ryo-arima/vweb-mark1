# Service Layout

## Multi-service model

The repository is organized as a collection of independently buildable
services. Each service has a Vue/Vite front end and a V back end:

The back-end layout follows the [`cmn-core`](https://github.com/ryo-arima/cmn-core)
repository's top-level organization.

```text
service-a/
├── front/                  # Vite + Vue application
└── back/                   # V service implementation

service-b/
├── front/                  # Vite + Vue application
└── back/                   # V service implementation
```

Additional services use the same `service-<name>/front` and
`service-<name>/back` pattern. The BFF routes requests to the back end that
owns the requested service, and each front end calls the BFF through its
same-origin API paths.

## Back-end layout

Each `back/` directory follows the top-level layout of `cmn-core`. The
implementation language changes from Go to V, but the directory responsibilities
remain aligned with the reference repository.

```text
service-a/back/
├── cmd/
│   ├── server/
│   │   └── main.v             # Service entry point
│   └── client/                 # Optional service-specific clients
│       ├── admin/
│       ├── anonymous/
│       └── app/
├── pkg/
│   ├── client/                 # Optional client controllers, repositories, and use cases
│   ├── code/                  # Response and message codes
│   ├── config/                # Configuration and external-service settings
│   ├── entity/
│   │   ├── model/             # Persistent and domain models
│   │   ├── request/            # Request DTOs
│   │   └── response/           # Response DTOs
│   ├── global/                # Shared logger and global values
│   └── server/
│       ├── controller/         # HTTP controllers
│       ├── repository/         # PostgreSQL and identity-provider access
│       ├── share/              # Request context, logging, and common server code
│       └── usecase/            # Service use cases
├── docker/                    # Service-specific Compose fragments
├── etc/                       # Example and container configuration
├── scripts/
│   ├── data/                  # Seed and service data
│   └── lib/                   # Shared shell helpers
├── test/
│   ├── e2e/                   # End-to-end tests
│   └── unit/                  # Unit tests and fixtures
├── Dockerfile
├── Makefile
├── README.md
├── VERSION
└── v.mod
```

The `service-b/back/` tree has the same structure. Package and configuration
names are service-specific, but the `cmd`, `pkg`, `docker`, `etc`, `scripts`,
and `test` boundaries remain consistent across services.

Go-specific files in `cmn-core`, such as `go.mod` and `.go` source files, are
replaced by V equivalents. The structural relationship between controllers,
use cases, repositories, entities, configuration, and tests must be retained.

## Front-end layout

Each `front/` directory is a Vite + Vue application using Vuetify 4 for the
component system:

```text
service-a/front/
├── public/
├── src/
│   ├── api/                  # Same-origin BFF API clients
│   ├── components/           # Reusable Vue components
│   ├── layouts/              # Page layouts
│   ├── router/               # Vue Router configuration
│   ├── stores/               # Client state
│   ├── types/                # TypeScript types
│   ├── views/                # Service screens
│   ├── App.vue
│   └── main.ts
├── index.html
├── package.json
├── tsconfig.json
└── vite.config.ts
```

`service-b/front/` follows the same layout. Front ends do not call back ends
directly and do not store access tokens in browser storage. OpenResty serves
the built assets and routes API calls to the matching back end.

## Mail UI

The independent mail UI is Roundcube, backed by the `mailserver` and `dns`
Compose services. Roundcube is bound to `127.0.0.1:3005` in development, is
not routed through OpenResty, and does not share the vweb application network.
The mail domain is `vweb.local`.

## Service routing

The initial BFF route convention is:

| Route | Destination |
|---|---|
| `/service-a/` | `service-a/front` static assets |
| `/api/service-a/v1/*` | `service-a/back` |
| `/api/service-a/v1/authorization/decision` | `service-a/back` authorization decision endpoint |
| `/service-b/` | `service-b/front` static assets |
| `/api/service-b/v1/*` | `service-b/back` |
| `/api/service-b/v1/authorization/decision` | `service-b/back` authorization decision endpoint |
| `/` | Redirect to `/service-a/` after BFF authentication |

The exact public route names may change with the product design, but each
service must have an explicit front-end and back-end ownership boundary.

