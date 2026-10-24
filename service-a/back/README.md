# service-a back end

This directory contains service A service logic implemented in V. The package
boundaries follow the `cmn-core` repository layout while replacing Go modules
and source files with V modules and source files.

The current executable exposes `/healthz`, `/readyz`, `/v1/identity`, and
`/v1/authorization/decision` as a container-safe HTTP scaffold. `/readyz`
checks the configured PostgreSQL connection through the repository boundary.
The decision endpoint evaluates the BFF-issued roles and group paths.
Resource endpoints must load canonical authorization data from PostgreSQL
before they are added.
