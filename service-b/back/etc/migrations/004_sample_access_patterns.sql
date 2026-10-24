-- Reset only the generated sample memberships before applying the explicit access matrix.
DELETE FROM service_b.member_roles mr
USING service_b.members m
JOIN service_b.users u ON u.id = m.user_id
WHERE mr.member_id = m.id
  AND u.email LIKE 'sample-user-%@vweb.local';

DELETE FROM service_b.members m
USING service_b.users u
WHERE m.user_id = u.id
  AND u.email LIKE 'sample-user-%@vweb.local';

WITH sample_memberships(user_number, group_name) AS (
    VALUES
        (1, 'group-a'), (3, 'group-a'), (4, 'group-a'),
        (5, 'group-a'), (6, 'group-b'), (7, 'group-b'), (8, 'group-b'),
        (9, 'group-c'), (10, 'group-b'), (11, 'group-d'),
        (12, 'group-c'), (13, 'group-e'), (14, 'group-e'),
        (15, 'group-a'), (16, 'group-b'), (17, 'group-b'),
        (18, 'group-c'), (20, 'group-e')
)
INSERT INTO service_b.members (group_id, user_id)
SELECT g.id, u.id
FROM sample_memberships sm
JOIN service_b.users u
    ON u.email = 'sample-user-' || lpad(sm.user_number::text, 2, '0') || '@vweb.local'
JOIN service_b.groups g ON g.name = sm.group_name
ON CONFLICT (group_id, user_id) DO NOTHING;

WITH sample_roles(user_number, group_name, role_name) AS (
    VALUES
        (1, 'group-a', 'service-admin'),
        (3, 'group-a', 'service-admin'),
        (5, 'group-a', 'service-admin'),
        (4, 'group-a', 'group-viewer'),
        (6, 'group-b', 'group-admin'),
        (7, 'group-b', 'group-editor'),
        (8, 'group-b', 'group-viewer'),
        (9, 'group-c', 'group-admin'),
        (10, 'group-b', 'group-viewer'),
        (11, 'group-d', 'group-viewer'),
        (12, 'group-c', 'group-admin'),
        (13, 'group-e', 'group-editor'),
        (14, 'group-e', 'group-viewer'),
        (15, 'group-a', 'group-editor'),
        (16, 'group-b', 'group-admin'),
        (16, 'group-b', 'group-editor'),
        (17, 'group-b', 'group-viewer'),
        (18, 'group-c', 'group-editor'),
        (20, 'group-e', 'group-admin')
)
INSERT INTO service_b.member_roles (member_id, role_id)
SELECT m.id, r.id
FROM sample_roles sr
JOIN service_b.users u
    ON u.email = 'sample-user-' || lpad(sr.user_number::text, 2, '0') || '@vweb.local'
JOIN service_b.groups g ON g.name = sr.group_name
JOIN service_b.members m ON m.group_id = g.id AND m.user_id = u.id
JOIN service_b.roles r ON r.name = sr.role_name
ON CONFLICT (member_id, role_id) DO NOTHING;
