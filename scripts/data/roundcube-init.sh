#!/bin/sh
set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${VWEB_ROUNDCUBE_DB_PASSWORD:?VWEB_ROUNDCUBE_DB_PASSWORD is required}"

export PGPASSWORD="$POSTGRES_PASSWORD"

if ! psql --set=ON_ERROR_STOP=1 --host=postgres --username="$POSTGRES_USER" --dbname=postgres \
  --tuples-only --no-align \
  --command "SELECT 1 FROM pg_roles WHERE rolname = 'roundcube'" | grep -q '^1$'; then
  escaped_password=$(printf '%s' "$VWEB_ROUNDCUBE_DB_PASSWORD" | sed "s/'/''/g")
  psql --set=ON_ERROR_STOP=1 --host=postgres --username="$POSTGRES_USER" --dbname=postgres \
    --command "CREATE ROLE roundcube LOGIN PASSWORD '$escaped_password'"
fi

if ! psql --set=ON_ERROR_STOP=1 --host=postgres --username="$POSTGRES_USER" --dbname=postgres \
  --tuples-only --no-align \
  --command "SELECT 1 FROM pg_database WHERE datname = 'roundcube'" | grep -q '^1$'; then
  psql --set=ON_ERROR_STOP=1 --host=postgres --username="$POSTGRES_USER" --dbname=postgres \
    --command "CREATE DATABASE roundcube OWNER roundcube"
fi
