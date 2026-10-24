INSERT INTO service_a.users (keycloak_sub, email, display_name)
SELECT
    '00000000-0000-0000-0000-' || lpad(n::text, 12, '0'),
    'sample-user-' || lpad(n::text, 2, '0') || '@vweb.local',
    'Sample User ' || lpad(n::text, 2, '0')
FROM generate_series(1, 20) AS n
ON CONFLICT (keycloak_sub) DO UPDATE
SET email = EXCLUDED.email,
    display_name = EXCLUDED.display_name,
    updated_at = now();

INSERT INTO service_a.groups (name, path)
SELECT
    'group-' || chr(96 + n),
    '/services/service-a/groups/group-' || chr(96 + n)
FROM generate_series(1, 5) AS n
ON CONFLICT (path) DO NOTHING;

INSERT INTO service_a.roles (name, description)
VALUES
    ('service-admin', 'Manage service groups, roles, and policies'),
    ('group-admin', 'Manage group members and assign existing roles'),
    ('group-editor', 'Write resources allowed by group policies'),
    ('group-viewer', 'Read resources allowed by group policies')
ON CONFLICT (name) DO UPDATE
SET description = EXCLUDED.description,
    updated_at = now();

INSERT INTO service_a.policies (role_id, resource, action, effect)
SELECT r.id, p.resource, p.action, 'allow'
FROM service_a.roles r
JOIN (VALUES
    ('service-admin', 'groups', 'manage'),
    ('service-admin', 'roles', 'manage'),
    ('service-admin', 'policies', 'manage'),
    ('group-admin', 'members', 'manage'),
    ('group-admin', 'member-roles', 'assign'),
    ('group-editor', 'resources', 'read'),
    ('group-editor', 'resources', 'write'),
    ('group-viewer', 'resources', 'read')
) AS p(role_name, resource, action) ON p.role_name = r.name
WHERE NOT EXISTS (
    SELECT 1
    FROM service_a.policies existing
    WHERE existing.role_id = r.id
      AND existing.resource = p.resource
      AND existing.action = p.action
);

INSERT INTO service_a.members (group_id, user_id)
SELECT
    g.id,
    u.id
FROM service_a.users u
JOIN service_a.groups g
    ON g.name = 'group-' || chr(96 + ((right(u.keycloak_sub, 2)::int - 1) % 5) + 1)
WHERE u.keycloak_sub LIKE '00000000-0000-0000-0000-%'
ON CONFLICT (group_id, user_id) DO NOTHING;

INSERT INTO service_a.member_roles (member_id, role_id)
SELECT
    m.id,
    r.id
FROM service_a.members m
JOIN service_a.users u ON u.id = m.user_id
JOIN service_a.roles r
    ON r.name = CASE ((right(u.keycloak_sub, 2)::int - 1) % 3)
        WHEN 0 THEN 'group-admin'
        WHEN 1 THEN 'group-editor'
        ELSE 'group-viewer'
    END
WHERE u.keycloak_sub LIKE '00000000-0000-0000-0000-%'
ON CONFLICT (member_id, role_id) DO NOTHING;

INSERT INTO service_a.member_roles (member_id, role_id)
SELECT m.id, r.id
FROM service_a.members m
JOIN service_a.users u ON u.id = m.user_id
JOIN service_a.roles r ON r.name = 'service-admin'
WHERE u.keycloak_sub IN (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000004'
)
ON CONFLICT (member_id, role_id) DO NOTHING;
