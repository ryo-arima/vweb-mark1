#!/bin/sh
set -eu

: "${KEYCLOAK_URL:?KEYCLOAK_URL is required}"
: "${KEYCLOAK_REALM:?KEYCLOAK_REALM is required}"
: "${KEYCLOAK_ADMIN_USERNAME:?KEYCLOAK_ADMIN_USERNAME is required}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD is required}"
: "${KEYCLOAK_SAMPLE_USER_PASSWORD:?KEYCLOAK_SAMPLE_USER_PASSWORD is required}"
: "${KEYCLOAK_BFF_CLIENT_SECRET:?KEYCLOAK_BFF_CLIENT_SECRET is required}"
: "${KEYCLOAK_SERVICE_A_CLIENT_SECRET:?KEYCLOAK_SERVICE_A_CLIENT_SECRET is required}"
: "${KEYCLOAK_SERVICE_B_CLIENT_SECRET:?KEYCLOAK_SERVICE_B_CLIENT_SECRET is required}"
: "${VWEB_MAIL_ADDRESS:?VWEB_MAIL_ADDRESS is required}"
: "${VWEB_PUBLIC_URL:?VWEB_PUBLIC_URL is required}"

PKI_DIR="${PKI_DIR:-/pki}"
ROOT_CA="$PKI_DIR/ca/root_ca.crt"
CLIENT_CERT="$PKI_DIR/openresty/client.crt"
CLIENT_KEY="$PKI_DIR/openresty/client.key"
ADMIN_ROOT="${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}"

kc_curl() {
  curl --fail --silent --show-error --retry 20 --retry-delay 2 \
    --cacert "$ROOT_CA" \
    --cert "$CLIENT_CERT" \
    --key "$CLIENT_KEY" \
    "$@"
}

get_token() {
  kc_curl \
    --request POST \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode grant_type=password \
    --data-urlencode "client_id=admin-cli" \
    --data-urlencode "username=${KEYCLOAK_ADMIN_USERNAME}" \
    --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    | jq -er '.access_token'
}

ACCESS_TOKEN=$(get_token)

kc_api() {
  method="$1"
  endpoint="$2"
  shift 2
  kc_curl \
    --request "$method" \
    "${ADMIN_ROOT}${endpoint}" \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" \
    --header 'Content-Type: application/json' \
    "$@"
}

configure_realm() {
  realm_json=$(kc_api GET '')
  kc_api PUT '' \
    --data "$(printf '%s' "$realm_json" | jq \
      --arg mail_from "$VWEB_MAIL_ADDRESS" \
      '.loginWithEmailAllowed = true
       | .duplicateEmailsAllowed = false
       | .verifyEmail = true
       | .smtpServer = {
           "host": "mailserver",
           "port": "25",
           "from": $mail_from,
           "fromDisplayName": "vweb",
           "replyTo": $mail_from,
           "replyToDisplayName": "vweb",
           "envelopeFrom": $mail_from,
           "auth": "false",
           "ssl": "false",
           "starttls": "false"
         }')" >/dev/null
}

find_top_group() {
  name="$1"
  kc_api GET '/groups?briefRepresentation=true&max=1000' \
    | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' \
    | head -n 1
}

find_child_group() {
  parent_id="$1"
  name="$2"
  kc_api GET "/groups/${parent_id}/children?briefRepresentation=true&max=1000" \
    | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' \
    | head -n 1
}

ensure_top_group() {
  name="$1"
  group_id=$(find_top_group "$name")
  if [ -z "$group_id" ]; then
    kc_api POST '/groups' --data "$(jq -n --arg name "$name" '{name: $name}')" >/dev/null
    group_id=$(find_top_group "$name")
  fi
  test -n "$group_id"
  printf '%s' "$group_id"
}

ensure_child_group() {
  parent_id="$1"
  name="$2"
  group_id=$(find_child_group "$parent_id" "$name")
  if [ -z "$group_id" ]; then
    kc_api POST "/groups/${parent_id}/children" \
      --data "$(jq -n --arg name "$name" '{name: $name}')" >/dev/null
    group_id=$(find_child_group "$parent_id" "$name")
  fi
  test -n "$group_id"
  printf '%s' "$group_id"
}

CLIENT_ID=$(kc_api GET '/clients?clientId=vweb-bff' | jq -er '.[0].id')

configure_bff_role_claims() {
  roles_scope_id=$(kc_api GET '/client-scopes' | jq -er '.[] | select(.name == "roles") | .id')
  for mapper_name in 'realm roles' 'client roles'; do
    mapper_json=$(kc_api GET "/client-scopes/${roles_scope_id}/protocol-mappers/models" | jq -er --arg name "$mapper_name" '.[] | select(.name == $name)')
    mapper_id=$(printf '%s' "$mapper_json" | jq -er '.id')
    kc_api PUT "/client-scopes/${roles_scope_id}/protocol-mappers/models/${mapper_id}" \
      --data "$(printf '%s' "$mapper_json" | jq '.config = (.config // {}) | .config["id.token.claim"] = "true" | .config["userinfo.token.claim"] = "true"')" >/dev/null
  done
}

ensure_service_api_client() {
  client_id="$1"
  client_name="$2"
  client_secret="$3"
  client_uuid=$(kc_api GET "/clients?clientId=$client_id" | jq -r 'if .[0] then .[0].id else "" end')
  if [ -z "$client_uuid" ]; then
    kc_api POST '/clients' --data "$(jq -n --arg client_id "$client_id" --arg client_name "$client_name" '{clientId: $client_id, name: $client_name, enabled: true, protocol: "openid-connect", publicClient: false, clientAuthenticatorType: "client-secret", standardFlowEnabled: false, directAccessGrantsEnabled: false, serviceAccountsEnabled: true}')" >/dev/null
    client_uuid=$(kc_api GET "/clients?clientId=$client_id" | jq -er '.[0].id')
  fi
  client_json=$(kc_api GET "/clients/$client_uuid")
  kc_api PUT "/clients/$client_uuid" --data "$(printf '%s' "$client_json" | jq --arg client_secret "$client_secret" --arg client_name "$client_name" '.name = $client_name | .enabled = true | .publicClient = false | .serviceAccountsEnabled = true | .standardFlowEnabled = false | .directAccessGrantsEnabled = false | .secret = $client_secret')" >/dev/null
  management_client_uuid=$(kc_api GET '/clients?clientId=realm-management' | jq -er '.[0].id')
  service_account_id=$(kc_api GET "/clients/$client_uuid/service-account-user" | jq -er '.id')
  for role_name in manage-users query-clients query-groups query-users view-clients view-users; do
    role_json=$(kc_api GET "/clients/$management_client_uuid/roles/$role_name")
    kc_api POST "/users/$service_account_id/role-mappings/clients/$management_client_uuid" --data "$(printf '%s' "$role_json" | jq -c '[.]')" >/dev/null
  done
}

configure_realm

client_json=$(kc_api GET "/clients/${CLIENT_ID}")
kc_api PUT "/clients/${CLIENT_ID}" \
  --data "$(printf '%s' "$client_json" | jq \
    --arg secret "$KEYCLOAK_BFF_CLIENT_SECRET" \
    --arg redirect_uri "${VWEB_PUBLIC_URL%/}/auth/callback" \
    --arg web_origin "${VWEB_PUBLIC_URL%/}" \
    '.secret = $secret | .redirectUris = [$redirect_uri] | .webOrigins = [$web_origin]')" >/dev/null

configure_bff_role_claims

ensure_service_api_client service-a-api 'service-a Admin API' "$KEYCLOAK_SERVICE_A_CLIENT_SECRET"
ensure_service_api_client service-b-api 'service-b Admin API' "$KEYCLOAK_SERVICE_B_CLIENT_SECRET"

add_client_role_to_group() {
  group_id="$1"
  role_name="$2"
  role_id=$(kc_api GET "/clients/${CLIENT_ID}/roles/${role_name}" | jq -er '.id')
  kc_api POST "/groups/${group_id}/role-mappings/clients/${CLIENT_ID}" \
    --data "$(jq -n --arg id "$role_id" --arg name "$role_name" '[{id: $id, name: $name}]')" >/dev/null
}

ensure_service_groups() {
  service_name="$1"
  service_admin_role="${service_name}-admin"
  services_id=$(ensure_top_group services)
  service_id=$(ensure_child_group "$services_id" "$service_name")
  administrators_id=$(ensure_child_group "$service_id" administrators)
  add_client_role_to_group "$administrators_id" "$service_admin_role"
  groups_id=$(ensure_child_group "$service_id" groups)

  for group_name in group-a group-b group-c group-d group-e; do
    group_id=$(ensure_child_group "$groups_id" "$group_name")
    administrators_id=$(ensure_child_group "$group_id" administrators)
    editors_id=$(ensure_child_group "$group_id" editors)
    viewers_id=$(ensure_child_group "$group_id" viewers)
    add_client_role_to_group "$administrators_id" group-admin
    add_client_role_to_group "$editors_id" group-editor
    add_client_role_to_group "$viewers_id" group-viewer
  done
}

find_user() {
  username="$1"
  kc_api GET "/users?username=${username}&exact=true&max=10" \
    | jq -r '.[0].id // empty'
}

ensure_user() {
  username="$1"
  keycloak_id="$2"
  user_number="$3"
  email=$(sample_user_email "$user_number")
  email_verified=$(sample_user_email_verified "$user_number")
  user_id=$(find_user "$username")
  if [ -z "$user_id" ]; then
    kc_api POST '/users' --data "$(jq -n \
      --arg id "$keycloak_id" \
      --arg username "$username" \
      --arg email "$email" \
      --argjson emailVerified "$email_verified" \
      --arg password "$KEYCLOAK_SAMPLE_USER_PASSWORD" \
      '{id: $id, username: $username, enabled: true, emailVerified: $emailVerified, firstName: "Sample", lastName: $username, email: $email, credentials: [{type: "password", value: $password, temporary: false}]}')" >/dev/null
    user_id=$(find_user "$username")
  fi
  test -n "$user_id"
  user_json=$(kc_api GET "/users/${user_id}")
  kc_api PUT "/users/${user_id}" --data "$(printf '%s' "$user_json" | jq \
    --arg email "$email" \
    --argjson emailVerified "$email_verified" \
    '.email = $email | .emailVerified = $emailVerified | .enabled = true')" >/dev/null
  kc_api PUT "/users/${user_id}/reset-password" --data "$(jq -n \
    --arg password "$KEYCLOAK_SAMPLE_USER_PASSWORD" \
    '{type: "password", value: $password, temporary: false}')" >/dev/null
  printf '%s' "$user_id"
}

add_user_to_group() {
  user_id="$1"
  group_id="$2"
  kc_api PUT "/users/${user_id}/groups/${group_id}" >/dev/null
}

reset_user_groups() {
  user_id="$1"
  for group_id in $(kc_api GET "/users/${user_id}/groups" | jq -r '.[].id'); do
    kc_api DELETE "/users/${user_id}/groups/${group_id}" >/dev/null
  done
}

assign_platform_admin() {
  user_id="$1"
  role_json=$(kc_api GET '/roles/platform-admin')
  kc_api POST "/users/${user_id}/role-mappings/realm" --data "$(printf '%s' "$role_json" | jq -c '[.]')" >/dev/null
}

sample_user_id() {
  printf '00000000-0000-0000-0000-%012d' "$1"
}

sample_user_email() {
  printf 'sample-user-%02d@vweb.local' "$1"
}

sample_user_email_verified() {
  if [ "$1" -le 10 ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

assign_group_role() {
  service_name="$1"
  user_id="$2"
  group_name="$3"
  role_name="$4"
  case "$role_name" in
    group-admin) subgroup_name=administrators ;;
    group-editor) subgroup_name=editors ;;
    group-viewer) subgroup_name=viewers ;;
    *)
      echo "Unsupported sample group role: $role_name" >&2
      return 1
      ;;
  esac
  services_id=$(ensure_top_group services)
  service_id=$(ensure_child_group "$services_id" "$service_name")
  groups_id=$(ensure_child_group "$service_id" groups)
  group_id=$(ensure_child_group "$groups_id" "$group_name")
  subgroup_id=$(ensure_child_group "$group_id" "$subgroup_name")
  add_client_role_to_group "$subgroup_id" "$role_name"
  add_user_to_group "$user_id" "$subgroup_id"
}

assign_service_admin() {
  service_name="$1"
  user_id="$2"
  services_id=$(ensure_top_group services)
  service_id=$(ensure_child_group "$services_id" "$service_name")
  administrators_id=$(ensure_child_group "$service_id" administrators)
  add_user_to_group "$user_id" "$administrators_id"
}

assign_sample_access() {
  user_number="$1"
  user_id="$2"
  case "$user_number" in
    1)
      assign_platform_admin "$user_id"
      assign_service_admin service-a "$user_id"
      assign_service_admin service-b "$user_id"
      ;;
    2)
      assign_service_admin service-a "$user_id"
      ;;
    3)
      assign_service_admin service-b "$user_id"
      ;;
    4)
      assign_service_admin service-a "$user_id"
      assign_group_role service-b "$user_id" group-a group-viewer
      ;;
    5)
      assign_service_admin service-b "$user_id"
      assign_group_role service-a "$user_id" group-b group-editor
      ;;
    6)
      assign_group_role service-a "$user_id" group-a group-admin
      assign_group_role service-b "$user_id" group-b group-admin
      ;;
    7)
      assign_group_role service-a "$user_id" group-a group-editor
      assign_group_role service-b "$user_id" group-b group-editor
      ;;
    8)
      assign_group_role service-a "$user_id" group-a group-viewer
      assign_group_role service-b "$user_id" group-b group-viewer
      ;;
    9)
      assign_group_role service-a "$user_id" group-b group-admin
      assign_group_role service-a "$user_id" group-c group-viewer
      assign_group_role service-b "$user_id" group-c group-admin
      ;;
    10)
      assign_group_role service-a "$user_id" group-b group-editor
      assign_group_role service-b "$user_id" group-b group-viewer
      ;;
    11)
      assign_group_role service-a "$user_id" group-c group-viewer
      assign_group_role service-b "$user_id" group-d group-viewer
      ;;
    12)
      assign_group_role service-a "$user_id" group-c group-editor
      assign_group_role service-b "$user_id" group-c group-admin
      ;;
    13)
      assign_group_role service-a "$user_id" group-d group-admin
      assign_group_role service-b "$user_id" group-e group-editor
      ;;
    14)
      assign_group_role service-a "$user_id" group-d group-editor
      assign_group_role service-b "$user_id" group-e group-viewer
      ;;
    15)
      assign_group_role service-a "$user_id" group-e group-viewer
      assign_group_role service-b "$user_id" group-a group-editor
      ;;
    16)
      assign_group_role service-a "$user_id" group-a group-admin
      assign_group_role service-a "$user_id" group-a group-editor
      assign_group_role service-b "$user_id" group-b group-admin
      assign_group_role service-b "$user_id" group-b group-editor
      ;;
    17)
      assign_group_role service-a "$user_id" group-b group-viewer
      assign_group_role service-b "$user_id" group-b group-viewer
      ;;
    18)
      assign_group_role service-a "$user_id" group-c group-editor
      assign_group_role service-b "$user_id" group-c group-editor
      ;;
    19)
      ;;
    20)
      assign_group_role service-a "$user_id" group-e group-viewer
      assign_group_role service-b "$user_id" group-e group-admin
      ;;
  esac
}

ensure_service_groups service-a
ensure_service_groups service-b

for user_number in $(seq 1 20); do
  username="sample-user-$(printf '%02d' "$user_number")"
  user_id=$(ensure_user "$username" "$(sample_user_id "$user_number")" "$user_number")
  reset_user_groups "$user_id"
  assign_sample_access "$user_number" "$user_id"
done
