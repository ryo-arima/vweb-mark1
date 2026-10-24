#!/bin/sh
set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${VWEB_KEYCLOAK_DB_PASSWORD:?VWEB_KEYCLOAK_DB_PASSWORD is required}"
: "${VWEB_SERVICE_DB_PASSWORD:?VWEB_SERVICE_DB_PASSWORD is required}"
: "${VWEB_BFF_DB_PASSWORD:?VWEB_BFF_DB_PASSWORD is required}"
: "${VWEB_ROUNDCUBE_DB_PASSWORD:?VWEB_ROUNDCUBE_DB_PASSWORD is required}"

export PGPASSWORD="$POSTGRES_PASSWORD"

role_exists() {
  role_name="$1"
  psql --set=ON_ERROR_STOP=1 \
    --host=postgres \
    --username="$POSTGRES_USER" \
    --dbname=postgres \
    --tuples-only \
    --no-align \
    --command "SELECT 1 FROM pg_roles WHERE rolname = '$role_name'" \
    | grep -q '^1$'
}

sync_role_password() {
  role_name="$1"
  role_password="$2"
  escaped_password=$(printf '%s' "$role_password" | sed "s/'/''/g")
  if role_exists "$role_name"; then
    psql --set=ON_ERROR_STOP=1 \
      --host=postgres \
      --username="$POSTGRES_USER" \
      --dbname=postgres \
      --command "ALTER ROLE $role_name PASSWORD '$escaped_password'"
  fi
}

sync_role_password keycloak "$VWEB_KEYCLOAK_DB_PASSWORD"
sync_role_password service_a "$VWEB_SERVICE_DB_PASSWORD"
sync_role_password service_b "$VWEB_SERVICE_DB_PASSWORD"
sync_role_password bff "$VWEB_BFF_DB_PASSWORD"
sync_role_password roundcube "$VWEB_ROUNDCUBE_DB_PASSWORD"
