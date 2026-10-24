#!/bin/sh
set -eu

: "${KEYCLOAK_TRUSTSTORE_PASSWORD:?KEYCLOAK_TRUSTSTORE_PASSWORD is required}"

PKI_DIR="${PKI_DIR:-/pki}"
ROOT_CA="$PKI_DIR/ca/root_ca.crt"
TRUSTSTORE="$PKI_DIR/keycloak/keycloak-truststore.p12"

# Rebuild this derived file so rerunning the bootstrap target is idempotent.
rm -f "$TRUSTSTORE"

keytool -importcert \
  -noprompt \
  -alias vweb-root-ca \
  -file "$ROOT_CA" \
  -keystore "$TRUSTSTORE" \
  -storetype PKCS12 \
  -storepass "$KEYCLOAK_TRUSTSTORE_PASSWORD"

# The truststore contains only the public CA certificate and must be readable
# by the non-root Keycloak user in a different container image.
chmod 0644 "$TRUSTSTORE"
