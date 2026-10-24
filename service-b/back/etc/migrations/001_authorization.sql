CREATE TABLE IF NOT EXISTS service_b.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    keycloak_sub TEXT NOT NULL UNIQUE,
    email TEXT,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_b.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID REFERENCES service_b.groups(id),
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_b.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS service_b.policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES service_b.roles(id),
    resource TEXT NOT NULL,
    action TEXT NOT NULL,
    effect TEXT NOT NULL CHECK (effect IN ('allow', 'deny')),
    condition JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_b.members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES service_b.groups(id),
    user_id UUID NOT NULL REFERENCES service_b.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS service_b.member_roles (
    member_id UUID NOT NULL REFERENCES service_b.members(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES service_b.roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (member_id, role_id)
);
