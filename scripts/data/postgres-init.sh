#!/bin/sh
set -eu

: "${VWEB_KEYCLOAK_DB_PASSWORD:?VWEB_KEYCLOAK_DB_PASSWORD is required}"
: "${VWEB_SERVICE_DB_PASSWORD:?VWEB_SERVICE_DB_PASSWORD is required}"
: "${VWEB_BFF_DB_PASSWORD:?VWEB_BFF_DB_PASSWORD is required}"
: "${VWEB_ROUNDCUBE_DB_PASSWORD:?VWEB_ROUNDCUBE_DB_PASSWORD is required}"

create_role() {
  role_name="$1"
  role_password="$2"
  escaped_password=$(printf '%s' "$role_password" | sed "s/'/''/g")
  if ! psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --tuples-only --no-align \
    --command "SELECT 1 FROM pg_roles WHERE rolname = '$role_name'" | grep -q '^1$'; then
    psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
      --command "CREATE ROLE $role_name LOGIN PASSWORD '$escaped_password'"
  fi
}

create_database() {
  database_name="$1"
  owner_name="$2"
  if ! psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --tuples-only --no-align \
    --command "SELECT 1 FROM pg_database WHERE datname = '$database_name'" | grep -q '^1$'; then
    psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
      --command "CREATE DATABASE $database_name OWNER $owner_name"
  fi
}

create_role keycloak "$VWEB_KEYCLOAK_DB_PASSWORD"
create_role service_a "$VWEB_SERVICE_DB_PASSWORD"
create_role service_b "$VWEB_SERVICE_DB_PASSWORD"
create_role bff "$VWEB_BFF_DB_PASSWORD"
create_role roundcube "$VWEB_ROUNDCUBE_DB_PASSWORD"
create_database keycloak keycloak
create_database vweb service_a
create_database roundcube roundcube

psql --username "$POSTGRES_USER" --dbname vweb <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS service_a AUTHORIZATION service_a;
CREATE SCHEMA IF NOT EXISTS service_b AUTHORIZATION service_b;
CREATE SCHEMA IF NOT EXISTS bff AUTHORIZATION bff;
GRANT CONNECT ON DATABASE vweb TO service_a;
GRANT CONNECT ON DATABASE vweb TO service_b;
GRANT CONNECT ON DATABASE vweb TO bff;
CREATE TABLE IF NOT EXISTS bff.sessions (
  sid TEXT PRIMARY KEY,
  name TEXT,
  data TEXT,
  exp TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS sessions_exp_idx ON bff.sessions (exp);
CREATE TABLE IF NOT EXISTS bff.sessions_meta (
  aud TEXT,
  sub TEXT,
  sid TEXT REFERENCES bff.sessions (sid) ON DELETE CASCADE ON UPDATE CASCADE,
  PRIMARY KEY (aud, sub, sid)
);
GRANT USAGE ON SCHEMA bff TO bff;
GRANT SELECT, INSERT, UPDATE, DELETE ON bff.sessions, bff.sessions_meta TO bff;
SQL
