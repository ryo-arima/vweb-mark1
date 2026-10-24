ALTER TABLE service_a.groups
    ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS keycloak_id TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS service_a_groups_keycloak_id_idx
    ON service_a.groups (keycloak_id)
    WHERE keycloak_id <> '';

ALTER TABLE service_a.members
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS service_a_members_group_idx
    ON service_a.members (group_id);

CREATE INDEX IF NOT EXISTS service_a_users_email_idx
    ON service_a.users (email);
