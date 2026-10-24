module repository

import pkg.entity.model

pub struct AuthorizationRepository {
mut:
	psql         &PsqlRepository
	keycloak     &KeycloakRepository
	service_name string
}

pub fn new_authorization_repository(database_url string) &AuthorizationRepository {
	return new_authorization_repository_with_config(database_url, 'service-a', KeycloakConfig{})
}

pub fn new_authorization_repository_with_config(database_url string, service_name string, keycloak_config KeycloakConfig) &AuthorizationRepository {
	return &AuthorizationRepository{
		psql:         new_psql_repository(database_url, service_name)
		keycloak:     new_keycloak_repository(keycloak_config)
		service_name: service_name
	}
}

pub fn (repository &AuthorizationRepository) ready() bool {
	return repository.psql.ready() && repository.keycloak.ready()
}

pub fn (repository &AuthorizationRepository) list_groups() ![]model.Group {
	return repository.psql.list_groups()
}

pub fn (repository &AuthorizationRepository) get_group(group_id string) !model.Group {
	return repository.psql.get_group(group_id)
}

pub fn (repository &AuthorizationRepository) create_group(name string, description string, parent_id string) !model.Group {
	parent_keycloak_id := if parent_id == '' {
		repository.keycloak.ensure_service_groups(repository.service_name)!.id
	} else {
		parent := repository.psql.get_group(parent_id)!
		repository.resolve_keycloak_group(parent)!.id
	}
	projected := repository.keycloak.create_group(name, parent_keycloak_id)!
	repository.keycloak.ensure_group_projection(projected.path)!
	return repository.psql.create_group(name, description, parent_id, projected.id)
}

pub fn (repository &AuthorizationRepository) update_group(group model.Group, name string, description string) !model.Group {
	projected := repository.resolve_keycloak_group(group)!
	_ = repository.keycloak.update_group(projected.id, name)!
	return repository.psql.update_group(group.id, name, description)
}

pub fn (repository &AuthorizationRepository) delete_group(group model.Group) ! {
	if repository.psql.has_child_groups(group.id)! {
		return error('group has child groups')
	}
	projected := repository.resolve_keycloak_group(group)!
	repository.keycloak.delete_group(projected.id)!
	repository.psql.delete_group(group.id)!
}

pub fn (repository &AuthorizationRepository) list_members(group_id string) ![]model.Member {
	return repository.psql.list_members(group_id)
}

pub fn (repository &AuthorizationRepository) list_all_members() ![]model.Member {
	return repository.psql.list_all_members()
}

pub fn (repository &AuthorizationRepository) get_member(member_id string) !model.Member {
	return repository.psql.get_member(member_id)
}

pub fn (repository &AuthorizationRepository) create_member(group model.Group, keycloak_sub string, email string, role_names []string) !model.Member {
	projected_group := repository.resolve_keycloak_group(group)!
	user := repository.keycloak.get_user(keycloak_sub)!
	requested_email := email.trim_space().to_lower()
	keycloak_email := user.email.trim_space().to_lower()
	if requested_email == '' {
		return error('user email is required')
	}
	if keycloak_email == '' {
		return error('Keycloak user email is required')
	}
	if requested_email != keycloak_email {
		return error('member email must match the Keycloak user email')
	}
	repository.psql.ensure_user_email_available(keycloak_email, user.id)!
	repository.keycloak.add_user_to_group(user.id, projected_group.id)!
	repository.keycloak.ensure_group_projection(group.path)!
	repository.keycloak.replace_user_role_groups(user.id, group.path, []string{}, role_names)!
	return repository.psql.create_member(group.id, user.id, keycloak_email, display_name(user),
		role_names)
}

pub fn (repository &AuthorizationRepository) update_member(member model.Member, email string, display_name_value string, role_names []string) !model.Member {
	group := repository.psql.get_group(member.group_id)!
	mut user := repository.resolve_member_user(member)!
	if user.id != member.keycloak_sub {
		repository.psql.sync_member_subject(member.id, user.id)!
	}
	if email != '' {
		user.email = email
	}
	if display_name_value != '' {
		parts := display_name_value.split_nth(' ', 2)
		user.first_name = parts[0]
		user.last_name = if parts.len > 1 { parts[1] } else { '' }
	}
	next_email := if email.trim_space() != '' { email.trim_space().to_lower() } else {
		member.email.trim_space().to_lower()
	}
	if next_email == '' {
		return error('user email is required')
	}
	if next_email != member.email.trim_space().to_lower() {
		repository.psql.ensure_user_email_available(next_email, user.id)!
	}
	user.email = next_email
	repository.keycloak.update_user(user)!
	repository.keycloak.ensure_group_projection(group.path)!
	repository.keycloak.replace_user_role_groups(user.id, group.path, member.role_names,
		role_names)!
	return repository.psql.update_member(member.id, next_email,
		if display_name_value != '' { display_name_value } else { member.display_name },
		role_names)
}

pub fn (repository &AuthorizationRepository) delete_member(member model.Member) ! {
	group := repository.psql.get_group(member.group_id)!
	projected_group := repository.resolve_keycloak_group(group)!
	user := repository.resolve_member_user(member)!
	if user.id != member.keycloak_sub {
		repository.psql.sync_member_subject(member.id, user.id)!
	}
	repository.keycloak.remove_user_from_group(user.id, projected_group.id)!
	repository.keycloak.replace_user_role_groups(user.id, group.path, member.role_names,
		[]string{})!
	repository.psql.delete_member(member.id)!
}

fn (repository &AuthorizationRepository) resolve_keycloak_group(group model.Group) !KeycloakGroup {
	if group.keycloak_id != '' {
		return KeycloakGroup{
			id:   group.keycloak_id
			name: group.name
			path: group.path
		}
	}
	return repository.keycloak.group_by_path(group.path)
}

fn (repository &AuthorizationRepository) resolve_member_user(member model.Member) !KeycloakUser {
	return repository.keycloak.get_user(member.keycloak_sub) or {
		if member.email == '' {
			return err
		}
		return repository.keycloak.find_user_by_username(member.email.all_before('@'))
	}
}

fn display_name(user KeycloakUser) string {
	name := '${user.first_name} ${user.last_name}'.trim_space()
	return if name == '' { user.username } else { name }
}
