-- Reset only the generated sample memberships before applying the explicit access matrix.
DELETE FROM service_a.member_roles mr
USING service_a.members m
JOIN service_a.users u ON u.id = m.user_id
WHERE mr.member_id = m.id
  AND u.email LIKE 'sample-user-%@vweb.local';

DELETE FROM service_a.members m
USING service_a.users u
WHERE m.user_id = u.id
  AND u.email LIKE 'sample-user-%@vweb.local';

WITH sample_memberships(user_number, group_name) AS (
    VALUES
        (1, 'group-a'), (2, 'group-a'), (4, 'group-a'),
        (5, 'group-b'), (6, 'group-a'), (7, 'group-a'), (8, 'group-a'),
        (9, 'group-b'), (9, 'group-c'), (10, 'group-b'),
        (11, 'group-c'), (12, 'group-c'), (13, 'group-d'),
        (14, 'group-d'), (15, 'group-e'), (16, 'group-a'),
        (17, 'group-b'), (18, 'group-c'), (20, 'group-e')
)
INSERT INTO service_a.members (group_id, user_id)
SELECT g.id, u.id
FROM sample_memberships sm
JOIN service_a.users u
    ON u.email = 'sample-user-' || lpad(sm.user_number::text, 2, '0') || '@vweb.local'
JOIN service_a.groups g ON g.name = sm.group_name
ON CONFLICT (group_id, user_id) DO NOTHING;

WITH sample_roles(user_number, group_name, role_name) AS (
    VALUES
        (1, 'group-a', 'service-admin'),
        (2, 'group-a', 'service-admin'),
        (4, 'group-a', 'service-admin'),
        (5, 'group-b', 'group-editor'),
        (6, 'group-a', 'group-admin'),
        (7, 'group-a', 'group-editor'),
        (8, 'group-a', 'group-viewer'),
        (9, 'group-b', 'group-admin'),
        (9, 'group-c', 'group-viewer'),
        (10, 'group-b', 'group-editor'),
        (11, 'group-c', 'group-viewer'),
        (12, 'group-c', 'group-editor'),
        (13, 'group-d', 'group-admin'),
        (14, 'group-d', 'group-editor'),
        (15, 'group-e', 'group-viewer'),
        (16, 'group-a', 'group-admin'),
        (16, 'group-a', 'group-editor'),
        (17, 'group-b', 'group-viewer'),
        (18, 'group-c', 'group-editor'),
        (20, 'group-e', 'group-viewer')
)
INSERT INTO service_a.member_roles (member_id, role_id)
SELECT m.id, r.id
FROM sample_roles sr
JOIN service_a.users u
    ON u.email = 'sample-user-' || lpad(sr.user_number::text, 2, '0') || '@vweb.local'
JOIN service_a.groups g ON g.name = sr.group_name
JOIN service_a.members m ON m.group_id = g.id AND m.user_id = u.id
JOIN service_a.roles r ON r.name = sr.role_name
ON CONFLICT (member_id, role_id) DO NOTHING;
