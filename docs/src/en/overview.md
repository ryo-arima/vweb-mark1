# Overview

[English documentation](./) | [Japanese documentation](../jp/)

## Document status

| Item | Value |
|---|---|
| Document | vweb-mark1 Basic Design |
| Version | 0.2 (Draft) |
| Date | 2026-10-24 |
| Language | English |
| Scope | Web application and local/development runtime foundation |
| Reference approach | Compose fragments merged in the `cmn-core` style |

## Purpose

`vweb-mark1` is a multi-service web application in which each service has a
Vite + Vue front end and a V back end. OpenResty acts as the Backend for
Frontend (BFF) and routes requests to the selected service back end.

Keycloak is the central identity provider for OIDC authentication and role
management. step-ca is the private certificate authority for service and
client certificates. PostgreSQL stores identity-provider data, BFF sessions,
and application data.

## Authentication model

The design separates device/channel authentication from user authentication:

1. A client certificate issued by step-ca proves that the connecting device
   or client is approved to reach OpenResty.
2. OIDC login through Keycloak proves the user identity and supplies roles.
3. The BFF creates the application session and forwards a sanitized identity
   context to the selected service back end.

A valid client certificate alone is not sufficient to use protected business
APIs.

## Scope

### In scope

- Service-specific V logic and its application boundaries.
- Service-specific Vue 3 web UIs.
- The service-specific Vue 3 Web UIs and an independent Roundcube mail UI.
- OpenResty TLS termination, mTLS, OIDC BFF behavior, static-file serving,
  and API routing.
- Keycloak OIDC, users, realms, clients, and roles.
- step-ca certificate issuance and renewal.
- PostgreSQL for Keycloak, BFF, and application data.
- Docker Compose for the initial infrastructure environment.

### Out of scope

- Business-domain-specific screens, tables, and API details.
- Production high availability, load balancers, and cloud-specific deployment.
- The operational process for distributing certificates to external devices.
- Public operation of the Keycloak Admin Console.

## Interpretation of the requested Compose services

The four infrastructure services requested for Docker Compose are interpreted
as:

- Keycloak
- OpenResty
- step-ca
- PostgreSQL

The service-specific front and back components are defined as application
components. The platform `main` Web UI is an internal Compose component
reached through OpenResty. The Roundcube mail UI, mail server, and DNS are
separate loopback-oriented Compose components and are intentionally outside
the OpenResty/BFF boundary.

