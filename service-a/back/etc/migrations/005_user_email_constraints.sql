-- Keep service-owned user email addresses present and unique across the service.
DO $$
DECLARE
    duplicate_email TEXT;
    canonical_id UUID;
    duplicate_id UUID;
    duplicate_member_id UUID;
    canonical_member_id UUID;
    duplicate_group_id UUID;
BEGIN
    -- Merge legacy local projections before adding the unique index. A real
    -- Keycloak subject is preferred over the old generated placeholder.
    FOR duplicate_email IN
        SELECT lower(btrim(email))
        FROM service_a.users
        WHERE email IS NOT NULL
        GROUP BY lower(btrim(email))
        HAVING count(*) > 1
    LOOP
        SELECT id INTO canonical_id
        FROM service_a.users
        WHERE lower(btrim(email)) = duplicate_email
        ORDER BY (keycloak_sub LIKE '00000000-0000-0000-0000-%'), created_at, id
        LIMIT 1;

        FOR duplicate_id IN
            SELECT id
            FROM service_a.users
            WHERE lower(btrim(email)) = duplicate_email
              AND id <> canonical_id
        LOOP
            FOR duplicate_member_id, duplicate_group_id IN
                SELECT id, group_id
                FROM service_a.members
                WHERE user_id = duplicate_id
            LOOP
                canonical_member_id := NULL;
                SELECT id INTO canonical_member_id
                FROM service_a.members
                WHERE group_id = duplicate_group_id
                  AND user_id = canonical_id;

                IF canonical_member_id IS NULL THEN
                    UPDATE service_a.members
                    SET user_id = canonical_id
                    WHERE id = duplicate_member_id;
                ELSE
                    INSERT INTO service_a.member_roles (member_id, role_id)
                    SELECT canonical_member_id, role_id
                    FROM service_a.member_roles
                    WHERE member_id = duplicate_member_id
                    ON CONFLICT (member_id, role_id) DO NOTHING;
                    DELETE FROM service_a.member_roles WHERE member_id = duplicate_member_id;
                    DELETE FROM service_a.members WHERE id = duplicate_member_id;
                END IF;
            END LOOP;
            DELETE FROM service_a.users WHERE id = duplicate_id;
        END LOOP;
    END LOOP;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM service_a.users
        WHERE email IS NULL OR btrim(email) = ''
    ) THEN
        RAISE EXCEPTION 'service_a.users contains a user without an email address';
    END IF;
END
$$;

ALTER TABLE service_a.users
    ALTER COLUMN email SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'service_a_users_email_not_blank'
          AND conrelid = 'service_a.users'::regclass
    ) THEN
        ALTER TABLE service_a.users
            ADD CONSTRAINT service_a_users_email_not_blank CHECK (btrim(email) <> '');
    END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS service_a_users_email_unique_idx
    ON service_a.users (lower(btrim(email)));
