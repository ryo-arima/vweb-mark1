#!/bin/sh
set -eu

service_name="${1:?service name is required}"
: "${VWEB_SERVICE_DB_PASSWORD:?VWEB_SERVICE_DB_PASSWORD is required}"

case "$service_name" in
  service-a)
    database_user=service_a
    migration_dir=/migrations/service-a
    ;;
  service-b)
    database_user=service_b
    migration_dir=/migrations/service-b
    ;;
  *)
    echo "Unsupported service: $service_name" >&2
    exit 1
    ;;
esac

export PGPASSWORD="$VWEB_SERVICE_DB_PASSWORD"

psql \
  --set=ON_ERROR_STOP=1 \
  --host=postgres \
  --username="$database_user" \
  --dbname=vweb \
  --file="$migration_dir/001_authorization.sql" \
  --file="$migration_dir/002_sample_data.sql" \
  --file="$migration_dir/003_management.sql" \
  --file="$migration_dir/004_sample_access_patterns.sql" \
  --file="$migration_dir/005_user_email_constraints.sql"
