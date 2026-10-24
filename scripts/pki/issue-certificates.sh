#!/bin/sh
set -eu

: "${STEP_CA_PROVISIONER_PASSWORD_FILE:=/home/step/secrets/password}"

mkdir -p /pki/ca /pki/keycloak /pki/openresty /pki/service-a /pki/service-b
cp /home/step/certs/root_ca.crt /pki/ca/root_ca.crt

issue_certificate() {
  common_name="$1"
  certificate_path="$2"
  key_path="$3"
  shift 3

  certificate_has_sans() {
    certificate_path="$1"
    shift
    certificate_json=$(step certificate inspect "$certificate_path" --format json 2>/dev/null) || return 1
    for san in "$@"; do
      printf '%s' "$certificate_json" | grep -Fq "\"$san\"" || return 1
    done
    return 0
  }

  if [ -s "$certificate_path" ] && [ -s "$key_path" ] &&
    certificate_has_sans "$certificate_path" "$common_name" "$@"; then
    return 0
  fi

  rm -f "$certificate_path" "$key_path"

  case "$#" in
    0)
      step ca certificate "$common_name" "$certificate_path" "$key_path" \
        --ca-url https://step-ca:9000 \
        --root /pki/ca/root_ca.crt \
        --provisioner admin \
        --provisioner-password-file "$STEP_CA_PROVISIONER_PASSWORD_FILE" \
        --san "$common_name"
      ;;
    1)
      step ca certificate "$common_name" "$certificate_path" "$key_path" \
        --ca-url https://step-ca:9000 \
        --root /pki/ca/root_ca.crt \
        --provisioner admin \
        --provisioner-password-file "$STEP_CA_PROVISIONER_PASSWORD_FILE" \
        --san "$common_name" \
        --san "$1"
      ;;
    2)
      step ca certificate "$common_name" "$certificate_path" "$key_path" \
        --ca-url https://step-ca:9000 \
        --root /pki/ca/root_ca.crt \
        --provisioner admin \
        --provisioner-password-file "$STEP_CA_PROVISIONER_PASSWORD_FILE" \
        --san "$common_name" \
        --san "$1" \
        --san "$2"
      ;;
    *)
      echo "At most two additional SANs are supported for $common_name" >&2
      exit 1
      ;;
  esac
}

issue_certificate keycloak /pki/keycloak/keycloak.crt /pki/keycloak/keycloak.key localhost
issue_certificate vweb.local /pki/openresty/openresty.crt /pki/openresty/openresty.key localhost openresty
issue_certificate openresty-client /pki/openresty/client.crt /pki/openresty/client.key openresty-client
issue_certificate service-a-client /pki/service-a/client.crt /pki/service-a/client.key service-a-client
issue_certificate service-b-client /pki/service-b/client.crt /pki/service-b/client.key service-b-client

chmod 0644 /pki/ca/root_ca.crt /pki/keycloak/keycloak.crt /pki/openresty/*.crt /pki/service-a/*.crt /pki/service-b/*.crt
chmod 0600 /pki/keycloak/keycloak.key /pki/openresty/*.key /pki/service-a/*.key /pki/service-b/*.key
