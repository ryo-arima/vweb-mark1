# Development mail server data

This directory contains only non-secret Postfix and Dovecot overrides for the
independent docker-mailserver container. `make up` mounts the generated account
state from the ignored `private/mailserver` directory and creates the
development and sample accounts through the host-side `init-mailserver` target
so that passwords are not committed to the repository:

```bash
VWEB_MAIL_ADDRESS=dev@vweb.local
VWEB_MAIL_PASSWORD=replace-at-runtime
make init-mailserver
```

The Roundcube UI is available at `http://127.0.0.1:3005/` after the account
has been created. The Keycloak seed uses the same `vweb.local` domain and
sends local email-verification messages through this mailserver.
