#!/bin/sh
set -eu

: "${KEYCLOAK_ADMIN:?KEYCLOAK_ADMIN is required}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD is required}"
: "${KEYCLOAK_SAMPLE_USER_PASSWORD:?KEYCLOAK_SAMPLE_USER_PASSWORD is required}"
: "${VWEB_PUBLIC_URL:?VWEB_PUBLIC_URL is required}"

OUTPUT_FILE="${USER_PASSWORD_LIST_FILE:-private/keycloak/user-passwords.txt}"
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")

sample_user_access_pattern() {
    case "$1" in
        1) printf '%s' 'platform-admin; service-a-admin; service-b-admin' ;;
        2) printf '%s' 'service-a-admin' ;;
        3) printf '%s' 'service-b-admin' ;;
        4) printf '%s' 'service-a-admin; service-b/group-a viewer' ;;
        5) printf '%s' 'service-b-admin; service-a/group-b editor' ;;
        6) printf '%s' 'service-a/group-a admin; service-b/group-b admin' ;;
        7) printf '%s' 'service-a/group-a editor; service-b/group-b editor' ;;
        8) printf '%s' 'service-a/group-a viewer; service-b/group-b viewer' ;;
        9) printf '%s' 'service-a/group-b admin+group-c viewer; service-b/group-c admin' ;;
        10) printf '%s' 'service-a/group-b editor; service-b/group-b viewer' ;;
        11) printf '%s' 'service-a/group-c viewer; service-b/group-d viewer' ;;
        12) printf '%s' 'service-a/group-c editor; service-b/group-c admin' ;;
        13) printf '%s' 'service-a/group-d admin; service-b/group-e editor' ;;
        14) printf '%s' 'service-a/group-d editor; service-b/group-e viewer' ;;
        15) printf '%s' 'service-a/group-e viewer; service-b/group-a editor' ;;
        16) printf '%s' 'service-a/group-a admin+editor; service-b/group-b admin+editor' ;;
        17) printf '%s' 'service-a/group-b viewer; service-b/group-b viewer' ;;
        18) printf '%s' 'service-a/group-c editor; service-b/group-c editor' ;;
        19) printf '%s' 'authenticated; no service membership' ;;
        20) printf '%s' 'service-a/group-e viewer; service-b/group-e admin' ;;
        *) printf '%s' 'unknown' ;;
    esac
}

# Keep the generated credential list local and readable only by the current user.
umask 077
mkdir -p "$OUTPUT_DIR"
temporary_file="${OUTPUT_FILE}.tmp.$$"
trap 'rm -f "$temporary_file"' EXIT INT TERM

{
    printf '%s\n' '# Local development credentials. Do not publish or reuse in production.'
    printf '%s\n' 'Realm: vweb'
    printf 'Application URL: %s/\n' "$VWEB_PUBLIC_URL"
    printf '%s\n' 'Keycloak admin realm: master'
    printf 'Account type\tUsername\tEmail\tEmail verified\tPassword\tAccess pattern\n\n'
    printf 'Keycloak bootstrap admin\t%s\t-\t-\t%s\tserver administrator\n' "$KEYCLOAK_ADMIN" "$KEYCLOAK_ADMIN_PASSWORD"

    for user_number in $(seq 1 20); do
        if [ "$user_number" -le 10 ]; then
            email_verified=true
        else
            email_verified=false
        fi
        printf 'vweb sample user\tsample-user-%02d\tsample-user-%02d@vweb.local\t%s\t%s\t%s\n' \
            "$user_number" "$user_number" "$email_verified" "$KEYCLOAK_SAMPLE_USER_PASSWORD" \
            "$(sample_user_access_pattern "$user_number")"
    done
} > "$temporary_file"

mv "$temporary_file" "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"
printf 'Created local credential list: %s\n' "$OUTPUT_FILE"
