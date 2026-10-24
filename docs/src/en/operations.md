# Operations and Non-Functional Requirements

## Security controls

- Expose only OpenResty application routes to untrusted clients.
- Keep Keycloak's `master` realm and Admin Console out of public routes.
- Overwrite trusted proxy headers at OpenResty instead of forwarding client
  values unchanged.
- Validate OIDC `state`, `nonce`, PKCE, issuer, audience, and token timestamps.
- Use secure HttpOnly SameSite cookies and do not use browser token storage.
- Limit request sizes, HTTP methods, and allowed proxy paths in OpenResty.
- Restrict permissions on CA keys, service keys, and client keys.
- Monitor certificate expiration, renewal failures, and CA reachability.
- Do not log tokens, cookies, passwords, private keys, or full certificates.

## Non-functional targets

| Area | Initial target |
|---|---|
| Availability | Single-host Compose environment; HA is out of scope |
| Performance | OpenResty serves static files; API work runs in the selected service back end |
| Extensibility | Keep domain logic independent from HTTP and authentication adapters |
| Auditability | Record request ID, user subject, and client certificate serial where appropriate |
| Operability | Write container logs to stdout/stderr for Compose log collection |
| Backup | Back up PostgreSQL, step-ca, and issued-certificate data separately |
| Development | Allow `DOCKER_PLATFORM` overrides for Apple Silicon and other hosts |

## Initial construction procedure

The intended workflow is:

```bash
cp .env.example .env
make compose-config
make up
make logs
```

First-start tasks:

1. Set the database passwords, BFF session database password, Keycloak
   administrator values, BFF client secret, session encryption key, sample
   user password, truststore password, step-ca bootstrap password, and
   development mail address/password in `.env`.
2. Initialize step-ca and record the CA fingerprint.
3. Run `make up`; its `make init-pki` step issues OpenResty and Keycloak server
   certificates and the OpenResty client certificate without a dedicated init
   container.
4. Import the Keycloak realm, client, and roles.
5. Install the step-ca root certificate and a client certificate on the
   approved development device.
6. Verify the Keycloak and service sample dataset. The `seed-keycloak` target
   creates `sample-user-01` through `sample-user-20`; the `migrate` target
   applies the service SQL. Run `make user-passwords` when a local credential
   list is needed; it writes the ignored file
   `private/keycloak/user-passwords.txt` with mode `0600`.
   Users `sample-user-01` through `sample-user-10` have verified email
   addresses, while `sample-user-11` through `sample-user-20` are unverified.
   The generated TSV also includes each sample user's service, group, and role
   access pattern. Use `sample-user-01`, `sample-user-02`, or `sample-user-04`
   to test the complete Service A administrator view; use `sample-user-03` or
   `sample-user-05` for the equivalent Service B administrator view.
7. `make up` creates or updates the development mail account through
   `make init-mailserver`, then open Roundcube at
   `http://127.0.0.1:3005/`. The mail UI is independent of OpenResty.
8. Open `/service-a/` or `/service-b/` through OpenResty. The browser must
   first present the client certificate and then complete the Keycloak login.
   OpenResty stores the opaque OIDC session in PostgreSQL and only then
   forwards API requests with server-generated identity headers. Use
   `/auth/session` to inspect login state and `/auth/logout` to remove it.

For local hostname resolution, add the development domain to the host file
before opening the browser:

```bash
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
```

OpenResty accepts only ports 80 and 443 on the host. Port 80 redirects to
HTTPS, and Keycloak and the service front/back containers are reached through
the OpenResty proxy. The loopback Keycloak port `127.0.0.1:9443` is only a
bootstrap endpoint for Make targets; the independent Roundcube UI remains at
`http://127.0.0.1:3005/`.

For local hostname resolution, add the development domain to the host file
before opening the browser:

```bash
echo '127.0.0.1 vweb.local' | sudo tee -a /etc/hosts
```

OpenResty accepts only ports 80 and 443 on the host. Port 80 redirects to
HTTPS, and Keycloak and the service front/back containers are reached through
the OpenResty proxy. The loopback Keycloak port `127.0.0.1:9443` is only a
bootstrap endpoint for Make targets; the independent Roundcube UI remains at
`http://127.0.0.1:3005/`.

The service back ends expose `/healthz`, `/readyz`, `/v1/identity`,
`/v1/authorization/decision`, and the group/member management routes described
in the data design inside the Compose network. The service administrator-only
`GET /v1/members` route supplies the Members list across all groups. Management requests require the
BFF-generated `X-User-Sub`, `X-User-Roles`, and `X-User-Groups` headers. These
endpoints are not exposed to the host; browsers reach them only through
`/api/service-a/v1/*` or `/api/service-b/v1/*` after OIDC login.

For a service administrator, the API contract is JSON. For example, create a
group with `POST /api/service-a/v1/groups` and body
`{"name":"reviewers","description":"Review team"}`. Add an existing
Keycloak subject with
`POST /api/service-a/v1/groups/<group-id>/members` and body
`{"keycloak_sub":"<subject>","email":"user@example.test","role_names":["group-viewer"]}`.
The email is required and must match the existing Keycloak user's email. A
duplicate email returns HTTP 409; adding the same user to another group is
allowed. The
service back calls Keycloak's Admin API over mTLS and stores the service-owned
details in PostgreSQL.

Certificate replacement must preserve the existing CA trust chain unless a
planned CA rotation is being performed.

The host-side bootstrap targets require Docker, `curl`, `jq`, and `keytool`.
They invoke scripts through the existing PostgreSQL and step-ca containers, so
initialization and migration do not add persistent or one-shot containers to
the Compose project.

### Browser client certificate installation on macOS

After `make up` reports healthy services, install the generated client
certificate in the macOS login keychain:

```bash
security add-trusted-cert \
  -d -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db \
  private/pki/ca/root_ca.crt

read -r -s -p "PKCS#12 password: " P12_PASSWORD
printf "\n"
export P12_PASSWORD
openssl pkcs12 -export \
  -out private/pki/openresty/vweb-client.p12 \
  -inkey private/pki/openresty/client.key \
  -in private/pki/openresty/client.crt \
  -certfile private/pki/ca/root_ca.crt \
  -name vweb-client \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  -passout env:P12_PASSWORD
security import \
  private/pki/openresty/vweb-client.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD"
unset P12_PASSWORD
```

The PKCS#12 password protects the bundle. If Chrome asks to use the private
key, enter the macOS `login` keychain password, not the PKCS#12 password.
Select `openresty-client` when it is shown as the certificate subject and
allow Chrome to use the key. The SHA-1/3DES options keep the bundle
compatible with macOS Security.framework versions that reject OpenSSL 3
default PBES2/AES PKCS#12 files.

### First access and lifecycle

Verify mTLS from the host and then open the browser routes:

```bash
curl --cacert private/pki/ca/root_ca.crt \
  --cert private/pki/openresty/client.crt \
  --key private/pki/openresty/client.key \
  https://vweb.local/service-a/
```

- Application entry point: `https://vweb.local/` (redirects to Service A)
- Service A: `https://vweb.local/service-a/`
- Service B: `https://vweb.local/service-b/`
- Independent Roundcube: `http://127.0.0.1:3005/`

When opening the application entry point or a service page in a browser, select
the installed `openresty-client` certificate when prompted. The page then redirects to
Keycloak; sign in with `sample-user-01` or `sample-user-01@vweb.local` and
`KEYCLOAK_SAMPLE_USER_PASSWORD`. To test the unverified flow, use
`sample-user-11@vweb.local`; Keycloak sends the verification message through
the internal mailserver. Open Roundcube at `http://127.0.0.1:3005/` and sign in
as the matching sample mailbox to read it.
The BFF session cookie is issued only after the OIDC callback succeeds.

Use the configured `VWEB_MAIL_ADDRESS` and `VWEB_MAIL_PASSWORD` for the
development mailbox. The mail UI is independent of OpenResty.

Use `make down` and `make up` for a full stop and rebuild while retaining
persistent data. Do not use `docker compose down -v` during normal development.

## GitHub Pages publication

`.github/workflows/docs.yml` builds one bilingual mdBook and uploads one Pages
artifact:

- `/en/` contains the English book;
- `/jp/` contains the Japanese book;
- `/` provides links to both language versions and redirects to English.

Pull requests build both books without deploying. Pushes to `main` and manual
workflow runs deploy through the `github-pages` environment. The repository's
Pages source must be set to **GitHub Actions** in the repository settings.

## Verification expectations

At every implementation stage, verify both positive and negative paths:

- Compose configuration resolves successfully.
- Services start in the documented order.
- Untrusted or missing client certificates are rejected.
- OpenResty rejects an untrusted Keycloak server certificate.
- Keycloak rejects a backend connection without the OpenResty client
  certificate.
- OIDC callbacks reject invalid state, nonce, and PKCE values.
- Expired sessions cannot reach any service back end.
- Unauthorized roles cannot access protected endpoints.
- Client-supplied identity headers cannot override BFF-generated headers.

