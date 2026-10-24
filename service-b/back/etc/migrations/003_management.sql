ALTER TABLE service_b.groups
    ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS keycloak_id TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS service_b_groups_keycloak_id_idx
    ON service_b.groups (keycloak_id)
    WHERE keycloak_id <> '';

ALTER TABLE service_b.members
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS service_b_members_group_idx
    ON service_b.members (group_id);

CREATE INDEX IF NOT EXISTS service_b_users_email_idx
    ON service_b.users (email);
