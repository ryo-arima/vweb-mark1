# Open Items

The following decisions remain for detailed design and implementation:

- Business domain, screen list, API list, and authorization matrix.
- PostgreSQL driver and migration tool implementation details.
- BFF session encryption algorithm, key rotation, and session lifetime.
- Client-certificate distribution, renewal, revocation, and device-to-user
  association.
- step-ca provisioner type and SAN issuance policy.
- Whether to use mTLS between OpenResty and service back ends as defense in depth.
- Keycloak group/role projection reconciliation, retry, and drift detection
  strategy.
- Production PostgreSQL backup, CA key custody, monitoring, and alerting.
- Exact versions and image digests for Keycloak, OpenResty, step-ca, and
  PostgreSQL.
- Exact V builder image version or digest for the service back-end images.
- Production mail DNS, TLS, mailbox persistence, account lifecycle, and
  outbound-delivery policy.

Each resolved item must be reflected in the relevant mdBook chapter and in the
AI-agent instructions if it changes an implementation invariant.

