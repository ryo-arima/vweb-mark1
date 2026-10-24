module repository

import db.pg
import pkg.entity.model

// PsqlRepository is the service-owned source of truth for authorization data.
// The schema name is derived from the fixed service name, never from a request.
pub struct PsqlRepository {
mut:
	database_url string
	schema       string
	base_path    string
}

pub fn new_psql_repository(database_url string, service_name string) &PsqlRepository {
	return &PsqlRepository{
		database_url: database_url
		schema:       service_name.replace('-', '_')
		base_path:    '/services/${service_name}/groups'
	}
}

pub fn (repository &PsqlRepository) ready() bool {
	if repository.database_url.trim_space() == '' {
		return true
	}
	mut database := pg.connect_with_conninfo(repository.database_url) or { return false }
	defer { database.close() or {} }
	value := database.q_int('SELECT 1') or { return false }
	return value == 1
}

pub fn (repository &PsqlRepository) list_groups() ![]model.Group {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec('SELECT id::text, parent_id::text, name, path, description, keycloak_id FROM ${repository.schema}.groups ORDER BY path')!
	mut groups := []model.Group{}
	for row in rows {
		groups << group_from_row(row)
	}
	return groups
}

pub fn (repository &PsqlRepository) get_group(group_id string) !model.Group {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('SELECT id::text, parent_id::text, name, path, description, keycloak_id FROM ${repository.schema}.groups WHERE id = $1',
		[group_id])!
	if rows.len == 0 {
		return error('group not found')
	}
	return group_from_row(rows[0])
}

pub fn (repository &PsqlRepository) create_group(name string, description string, parent_id string, keycloak_id string) !model.Group {
	mut database := repository.connect()!
	defer { database.close() or {} }
	path := repository.path_for_parent(mut database, parent_id, name)!
	rows := database.exec_param_many('INSERT INTO ${repository.schema}.groups (parent_id, name, path, description, keycloak_id) VALUES (CASE WHEN $1 = \'\' THEN NULL::uuid ELSE $1::uuid END, $2, $3, $4, $5) RETURNING id::text, parent_id::text, name, path, description, keycloak_id',
		[parent_id, name, path, description, keycloak_id])!
	if rows.len == 0 {
		return error('group was not created')
	}
	return group_from_row(rows[0])
}

pub fn (repository &PsqlRepository) update_group(group_id string, name string, description string) !model.Group {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('UPDATE ${repository.schema}.groups AS g SET name = $2, description = $3, path = CASE WHEN g.parent_id IS NULL THEN \'${repository.base_path}/\' || $2 ELSE (SELECT p.path FROM ${repository.schema}.groups AS p WHERE p.id = g.parent_id) || \'/\' || $2 END, updated_at = now() WHERE g.id = $1 RETURNING g.id::text, g.parent_id::text, g.name, g.path, g.description, g.keycloak_id',
		[group_id, name, description])!
	if rows.len == 0 {
		return error('group not found')
	}
	_ = database.exec_param_many('WITH RECURSIVE subtree AS (SELECT id, path FROM ${repository.schema}.groups WHERE id = $1 UNION ALL SELECT child.id, subtree.path || \'/\' || child.name FROM ${repository.schema}.groups AS child JOIN subtree ON child.parent_id = subtree.id) UPDATE ${repository.schema}.groups AS g SET path = subtree.path, updated_at = now() FROM subtree WHERE g.id = subtree.id AND g.id <> $1',
		[group_id])!
	return group_from_row(rows[0])
}

pub fn (repository &PsqlRepository) delete_group(group_id string) ! {
	mut database := repository.connect()!
	defer { database.close() or {} }
	child_rows := database.exec_param_many('SELECT id FROM ${repository.schema}.groups WHERE parent_id = $1 LIMIT 1',
		[group_id])!
	if child_rows.len > 0 {
		return error('group has child groups')
	}
	rows := database.exec_param_many('DELETE FROM ${repository.schema}.groups WHERE id = $1 RETURNING id',
		[group_id])!
	if rows.len == 0 {
		return error('group not found')
	}
}

pub fn (repository &PsqlRepository) has_child_groups(group_id string) !bool {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('SELECT id FROM ${repository.schema}.groups WHERE parent_id = $1 LIMIT 1',
		[group_id])!
	return rows.len > 0
}

pub fn (repository &PsqlRepository) list_members(group_id string) ![]model.Member {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('SELECT m.id::text, m.group_id::text, m.user_id::text, u.keycloak_sub, COALESCE(u.email, \'\'), COALESCE(u.display_name, \'\'), COALESCE(string_agg(r.name, \',\' ORDER BY r.name), \'\') FROM ${repository.schema}.members AS m JOIN ${repository.schema}.users AS u ON u.id = m.user_id LEFT JOIN ${repository.schema}.member_roles AS mr ON mr.member_id = m.id LEFT JOIN ${repository.schema}.roles AS r ON r.id = mr.role_id WHERE m.group_id = $1 GROUP BY m.id, m.group_id, m.user_id, u.keycloak_sub, u.email, u.display_name ORDER BY u.display_name, u.email',
		[group_id])!
	mut members := []model.Member{}
	for row in rows {
		members << member_from_row(row)
	}
	return members
}

pub fn (repository &PsqlRepository) list_all_members() ![]model.Member {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec('SELECT m.id::text, m.group_id::text, m.user_id::text, u.keycloak_sub, COALESCE(u.email, \'\'), COALESCE(u.display_name, \'\'), COALESCE(string_agg(r.name, \',\' ORDER BY r.name), \'\'), g.name, g.path FROM ${repository.schema}.members AS m JOIN ${repository.schema}.users AS u ON u.id = m.user_id JOIN ${repository.schema}.groups AS g ON g.id = m.group_id LEFT JOIN ${repository.schema}.member_roles AS mr ON mr.member_id = m.id LEFT JOIN ${repository.schema}.roles AS r ON r.id = mr.role_id GROUP BY m.id, m.group_id, m.user_id, u.keycloak_sub, u.email, u.display_name, g.name, g.path ORDER BY g.path, u.display_name, u.email')!
	mut members := []model.Member{}
	for row in rows {
		members << member_with_group_from_row(row)
	}
	return members
}

pub fn (repository &PsqlRepository) get_member(member_id string) !model.Member {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('SELECT m.id::text, m.group_id::text, m.user_id::text, u.keycloak_sub, COALESCE(u.email, \'\'), COALESCE(u.display_name, \'\'), COALESCE(string_agg(r.name, \',\' ORDER BY r.name), \'\') FROM ${repository.schema}.members AS m JOIN ${repository.schema}.users AS u ON u.id = m.user_id LEFT JOIN ${repository.schema}.member_roles AS mr ON mr.member_id = m.id LEFT JOIN ${repository.schema}.roles AS r ON r.id = mr.role_id WHERE m.id = $1 GROUP BY m.id, m.group_id, m.user_id, u.keycloak_sub, u.email, u.display_name',
		[member_id])!
	if rows.len == 0 {
		return error('member not found')
	}
	return member_from_row(rows[0])
}

pub fn (repository &PsqlRepository) ensure_user_email_available(email string, keycloak_sub string) ! {
	email_value := email.trim_space().to_lower()
	if email_value == '' {
		return error('user email is required')
	}
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('SELECT id::text FROM ${repository.schema}.users WHERE lower(btrim(email)) = lower(btrim($1)) AND keycloak_sub <> $2 LIMIT 1',
		[email_value, keycloak_sub])!
	if rows.len > 0 {
		return error('user email already exists')
	}
}

pub fn (repository &PsqlRepository) create_member(group_id string, keycloak_sub string, email string, display_name string, role_names []string) !model.Member {
	mut database := repository.connect()!
	defer { database.close() or {} }
	email_value := email.trim_space().to_lower()
	if email_value == '' {
		return error('user email is required')
	}
	mut user_rows := database.exec_param_many('SELECT id::text FROM ${repository.schema}.users WHERE keycloak_sub = $1 LIMIT 1',
		[keycloak_sub])!
	mut user_id := ''
	if user_rows.len > 0 {
		user_id = row_text(user_rows[0], 0)
	} else {
		conflicting_rows := database.exec_param_many('SELECT id::text FROM ${repository.schema}.users WHERE lower(btrim(email)) = lower(btrim($1)) LIMIT 1',
			[email_value])!
		if conflicting_rows.len > 0 {
			return error('user email already exists')
		}
	}
	conflicting_rows := database.exec_param_many('SELECT id::text FROM ${repository.schema}.users WHERE lower(btrim(email)) = lower(btrim($1)) AND keycloak_sub <> $2 LIMIT 1',
		[email_value, keycloak_sub])!
	if conflicting_rows.len > 0 {
		return error('user email already exists')
	}
	if user_id != '' {
		user_rows = database.exec_param_many('UPDATE ${repository.schema}.users SET email = $2, display_name = $3, updated_at = now() WHERE id = $1 RETURNING id::text',
			[user_id, email_value, display_name])!
	} else {
		user_rows = database.exec_param_many('INSERT INTO ${repository.schema}.users (keycloak_sub, email, display_name) VALUES ($1, $2, $3) RETURNING id::text',
			[keycloak_sub, email_value, display_name])!
	}
	if user_rows.len == 0 {
		return error('user projection was not created')
	}
	user_id = row_text(user_rows[0], 0)
	member_rows := database.exec_param_many('INSERT INTO ${repository.schema}.members (group_id, user_id) VALUES ($1, $2) ON CONFLICT (group_id, user_id) DO NOTHING RETURNING id::text',
		[group_id, user_id])!
	if member_rows.len == 0 {
		return error('member already exists')
	}
	member_id := row_text(member_rows[0], 0)
	replace_member_roles(mut database, repository.schema, member_id, role_names)!
	return repository.member_by_database(mut database, member_id)
}

pub fn (repository &PsqlRepository) sync_member_subject(member_id string, keycloak_sub string) ! {
	mut database := repository.connect()!
	defer { database.close() or {} }
	merged_rows := database.exec_param_many('UPDATE ${repository.schema}.members AS m SET user_id = existing.id FROM ${repository.schema}.users AS existing WHERE m.id = $1 AND existing.keycloak_sub = $2 RETURNING m.id',
		[member_id, keycloak_sub])!
	if merged_rows.len > 0 {
		return
	}
	rows := database.exec_param_many('UPDATE ${repository.schema}.users AS u SET keycloak_sub = $2, updated_at = now() WHERE u.id = (SELECT user_id FROM ${repository.schema}.members WHERE id = $1) RETURNING u.id',
		[member_id, keycloak_sub])!
	if rows.len == 0 {
		return error('member not found')
	}
}

pub fn (repository &PsqlRepository) update_member(member_id string, email string, display_name string, role_names []string) !model.Member {
	mut database := repository.connect()!
	defer { database.close() or {} }
	email_value := email.trim_space().to_lower()
	if email_value == '' {
		return error('user email is required')
	}
	user_rows := database.exec_param_many('SELECT user_id::text FROM ${repository.schema}.members WHERE id = $1',
		[member_id])!
	if user_rows.len == 0 {
		return error('member not found')
	}
	user_id := row_text(user_rows[0], 0)
	conflicting_rows := database.exec_param_many('SELECT id::text FROM ${repository.schema}.users WHERE lower(btrim(email)) = lower(btrim($1)) AND id <> $2 LIMIT 1',
		[email_value, user_id])!
	if conflicting_rows.len > 0 {
		return error('user email already exists')
	}
	rows := database.exec_param_many('UPDATE ${repository.schema}.users AS u SET email = $2, display_name = $3, updated_at = now() WHERE u.id = $1 RETURNING u.id',
		[user_id, email_value, display_name])!
	if rows.len == 0 {
		return error('member not found')
	}
	replace_member_roles(mut database, repository.schema, member_id, role_names)!
	return repository.member_by_database(mut database, member_id)
}

pub fn (repository &PsqlRepository) delete_member(member_id string) ! {
	mut database := repository.connect()!
	defer { database.close() or {} }
	rows := database.exec_param_many('DELETE FROM ${repository.schema}.members WHERE id = $1 RETURNING id',
		[member_id])!
	if rows.len == 0 {
		return error('member not found')
	}
}

fn (repository &PsqlRepository) connect() !pg.DB {
	if repository.database_url.trim_space() == '' {
		return error('database URL is not configured')
	}
	return pg.connect_with_conninfo(repository.database_url)
}

fn (repository &PsqlRepository) path_for_parent(mut database pg.DB, parent_id string, name string) !string {
	if parent_id == '' {
		return '${repository.base_path}/${name}'
	}
	rows := database.exec_param_many('SELECT path FROM ${repository.schema}.groups WHERE id = $1',
		[parent_id])!
	if rows.len == 0 {
		return error('parent group not found')
	}
	return '${row_text(rows[0], 0)}/${name}'
}

fn (repository &PsqlRepository) member_by_database(mut database pg.DB, member_id string) !model.Member {
	rows := database.exec_param_many('SELECT m.id::text, m.group_id::text, m.user_id::text, u.keycloak_sub, COALESCE(u.email, \'\'), COALESCE(u.display_name, \'\'), COALESCE(string_agg(r.name, \',\' ORDER BY r.name), \'\') FROM ${repository.schema}.members AS m JOIN ${repository.schema}.users AS u ON u.id = m.user_id LEFT JOIN ${repository.schema}.member_roles AS mr ON mr.member_id = m.id LEFT JOIN ${repository.schema}.roles AS r ON r.id = mr.role_id WHERE m.id = $1 GROUP BY m.id, m.group_id, m.user_id, u.keycloak_sub, u.email, u.display_name',
		[member_id])!
	if rows.len == 0 {
		return error('member not found')
	}
	return member_from_row(rows[0])
}

fn replace_member_roles(mut database pg.DB, schema string, member_id string, role_names []string) ! {
	_ := database.exec_param_many('DELETE FROM ${schema}.member_roles WHERE member_id = $1',
		[member_id])!
	for role_name in role_names {
		_ = database.exec_param_many('INSERT INTO ${schema}.member_roles (member_id, role_id) SELECT $1, id FROM ${schema}.roles WHERE name = $2',
			[member_id, role_name])!
	}
}

fn group_from_row(row pg.Row) model.Group {
	parent := row_optional(row, 1)
	return model.Group{
		id:          row_text(row, 0)
		parent_id:   parent
		name:        row_text(row, 2)
		path:        row_text(row, 3)
		description: row_text(row, 4)
		keycloak_id: row_text(row, 5)
	}
}

fn member_from_row(row pg.Row) model.Member {
	return model.Member{
		id:           row_text(row, 0)
		group_id:     row_text(row, 1)
		user_id:      row_text(row, 2)
		keycloak_sub: row_text(row, 3)
		email:        row_text(row, 4)
		display_name: row_text(row, 5)
		role_names:   parse_roles(row_text(row, 6))
	}
}

fn member_with_group_from_row(row pg.Row) model.Member {
	mut member := member_from_row(row)
	member.group_name = row_text(row, 7)
	member.group_path = row_text(row, 8)
	return member
}

fn row_text(row pg.Row, index int) string {
	if index >= row.vals.len {
		return ''
	}
	if value := row.vals[index] {
		return value
	}
	return ''
}

fn row_optional(row pg.Row, index int) ?string {
	value := row_text(row, index)
	if value == '' {
		return none
	}
	return value
}

fn parse_roles(value string) []string {
	if value.trim_space() == '' {
		return []string{}
	}
	return value.split(',').filter(it != '')
}
