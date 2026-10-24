module repository

import json
import net.http

// KeycloakConfig contains only the connection material needed by the service
// account Admin API client. The private key is read by net/http at request time.
pub struct KeycloakConfig {
pub:
	base_url      string
	realm         string
	client_id     string
	client_secret string
	ca_cert       string
	client_cert   string
	client_key    string
	bff_client_id string
}

pub struct KeycloakRepository {
mut:
	config KeycloakConfig
}

pub struct KeycloakGroup {
pub:
	id   string
	name string
	path string
}

pub struct KeycloakUser {
pub mut:
	id             string
	username       string
	email          string
	first_name     string @[json: firstName]
	last_name      string @[json: lastName]
	enabled        bool
	email_verified bool @[json: emailVerified]
}

struct TokenResponse {
	access_token string
}

struct GroupPayload {
	name string
}

struct KeycloakClient {
pub:
	id        string
	client_id string @[json: clientId]
}

struct KeycloakRole {
pub:
	id   string
	name string
}

pub fn new_keycloak_repository(config KeycloakConfig) &KeycloakRepository {
	return &KeycloakRepository{
		config: config
	}
}

pub fn (repository &KeycloakRepository) ready() bool {
	if repository.config.base_url.trim_space() == '' {
		return true
	}
	_ := repository.request(.get, '/admin/realms/${repository.config.realm}', '') or {
		return false
	}
	return true
}

pub fn (repository &KeycloakRepository) ensure_service_groups(service_name string) !KeycloakGroup {
	return repository.ensure_group_path('/services/${service_name}/groups')
}

pub fn (repository &KeycloakRepository) ensure_group_projection(group_path string) ! {
	for role_group in [
		['administrators', 'group-admin'],
		['editors', 'group-editor'],
		['viewers', 'group-viewer'],
	] {
		group := repository.ensure_group_path('${group_path}/${role_group[0]}')!
		client_id := repository.bff_client_uuid()!
		role := repository.bff_role(client_id, role_group[1])!
		_ := repository.request(.post, '/admin/realms/${repository.config.realm}/groups/${group.id}/role-mappings/clients/${client_id}',
			json.encode([role]))!
	}
}

pub fn (repository &KeycloakRepository) replace_user_role_groups(user_id string, group_path string, old_roles []string, new_roles []string) ! {
	for role_name in old_roles {
		if role_path := repository.role_group_path(group_path, role_name) {
			role_group := repository.group_by_path(role_path)!
			repository.remove_user_from_group(user_id, role_group.id)!
		}
	}
	for role_name in new_roles {
		if role_path := repository.role_group_path(group_path, role_name) {
			role_group := repository.group_by_path(role_path)!
			repository.add_user_to_group(user_id, role_group.id)!
		}
	}
}

pub fn (repository &KeycloakRepository) group_by_path(path string) !KeycloakGroup {
	segments := path.trim('/').split('/').filter(it != '')
	if segments.len == 0 {
		return error('keycloak group path is empty')
	}
	mut parent_id := ''
	mut current := KeycloakGroup{}
	for segment in segments {
		children := repository.children(parent_id)!
		mut found := false
		for child in children {
			if child.name == segment {
				current = child
				parent_id = child.id
				found = true
				break
			}
		}
		if !found {
			return error('keycloak group not found for path ${path}')
		}
	}
	return current
}

pub fn (repository &KeycloakRepository) create_group(name string, parent_id string) !KeycloakGroup {
	payload := json.encode(GroupPayload{ name: name })
	endpoint := if parent_id == '' {
		'/admin/realms/${repository.config.realm}/groups'
	} else {
		'/admin/realms/${repository.config.realm}/groups/${parent_id}/children'
	}
	response := repository.request(.post, endpoint, payload)!
	if location := response.header.get(.location) {
		created_id := location.all_after_last('/')
		if created_id != '' {
			return repository.get_group(created_id)
		}
	}
	children := repository.children(parent_id)!
	for child in children {
		if child.name == name {
			return child
		}
	}
	return error('Keycloak created a group but did not return its id')
}

pub fn (repository &KeycloakRepository) update_group(group_id string, name string) !KeycloakGroup {
	response := repository.request(.put, '/admin/realms/${repository.config.realm}/groups/${group_id}',
		json.encode(GroupPayload{ name: name }))!
	_ = response
	return repository.get_group(group_id)
}

pub fn (repository &KeycloakRepository) delete_group(group_id string) ! {
	_ := repository.request(.delete, '/admin/realms/${repository.config.realm}/groups/${group_id}',
		'')!
}

pub fn (repository &KeycloakRepository) get_user(user_id string) !KeycloakUser {
	response := repository.request(.get, '/admin/realms/${repository.config.realm}/users/${user_id}',
		'')!
	return json.decode(KeycloakUser, response.body)
}

pub fn (repository &KeycloakRepository) find_user_by_email(email string) !KeycloakUser {
	query := http.url_encode_form_data({
		'email': email
		'exact': 'true'
		'max':   '10'
	})
	response := repository.request(.get, '/admin/realms/${repository.config.realm}/users?${query}',
		'')!
	users := json.decode([]KeycloakUser, response.body)!
	if users.len == 0 {
		return error('Keycloak user not found')
	}
	return users[0]
}

pub fn (repository &KeycloakRepository) find_user_by_username(username string) !KeycloakUser {
	query := http.url_encode_form_data({
		'username': username
		'exact':    'true'
		'max':      '10'
	})
	response := repository.request(.get, '/admin/realms/${repository.config.realm}/users?${query}',
		'')!
	users := json.decode([]KeycloakUser, response.body)!
	if users.len == 0 {
		return error('Keycloak user not found')
	}
	return users[0]
}

pub fn (repository &KeycloakRepository) update_user(user KeycloakUser) ! {
	payload := json.encode(user)
	_ := repository.request(.put, '/admin/realms/${repository.config.realm}/users/${user.id}',
		payload)!
}

pub fn (repository &KeycloakRepository) add_user_to_group(user_id string, group_id string) ! {
	_ := repository.request(.put, '/admin/realms/${repository.config.realm}/users/${user_id}/groups/${group_id}',
		'')!
}

pub fn (repository &KeycloakRepository) remove_user_from_group(user_id string, group_id string) ! {
	_ := repository.request(.delete, '/admin/realms/${repository.config.realm}/users/${user_id}/groups/${group_id}',
		'')!
}

fn (repository &KeycloakRepository) ensure_group_path(path string) !KeycloakGroup {
	segments := path.trim('/').split('/').filter(it != '')
	mut parent_id := ''
	mut current := KeycloakGroup{}
	for segment in segments {
		children := repository.children(parent_id)!
		mut found := false
		for child in children {
			if child.name == segment {
				current = child
				parent_id = child.id
				found = true
				break
			}
		}
		if !found {
			current = repository.create_group(segment, parent_id)!
			parent_id = current.id
		}
	}
	return current
}

fn (repository &KeycloakRepository) get_group(group_id string) !KeycloakGroup {
	response := repository.request(.get, '/admin/realms/${repository.config.realm}/groups/${group_id}',
		'')!
	return json.decode(KeycloakGroup, response.body)
}

fn (repository &KeycloakRepository) bff_client_uuid() !string {
	client_id := if repository.config.bff_client_id == '' {
		'vweb-bff'
	} else {
		repository.config.bff_client_id
	}
	response := repository.request(.get, '/admin/realms/${repository.config.realm}/clients?clientId=${client_id}',
		'')!
	clients := json.decode([]KeycloakClient, response.body)!
	if clients.len == 0 {
		return error('BFF client not found')
	}
	return clients[0].id
}

fn (repository &KeycloakRepository) bff_role(client_id string, role_name string) !KeycloakRole {
	response := repository.request(.get, '/admin/realms/${repository.config.realm}/clients/${client_id}/roles/${role_name}',
		'')!
	return json.decode(KeycloakRole, response.body)
}

fn (repository &KeycloakRepository) role_group_path(group_path string, role_name string) ?string {
	return match role_name {
		'group-admin' { '${group_path}/administrators' }
		'group-editor' { '${group_path}/editors' }
		'group-viewer' { '${group_path}/viewers' }
		'service-admin' { '/services/${group_path.split('/')[2]}/administrators' }
		else { none }
	}
}

fn (repository &KeycloakRepository) children(parent_id string) ![]KeycloakGroup {
	endpoint := if parent_id == '' {
		'/admin/realms/${repository.config.realm}/groups?briefRepresentation=false&max=1000'
	} else {
		'/admin/realms/${repository.config.realm}/groups/${parent_id}/children?briefRepresentation=false&max=1000'
	}
	response := repository.request(.get, endpoint, '')!
	return json.decode([]KeycloakGroup, response.body)
}

fn (repository &KeycloakRepository) token() !string {
	endpoint := '${repository.config.base_url.trim_right('/')}/realms/${repository.config.realm}/protocol/openid-connect/token'
	data := http.url_encode_form_data({
		'grant_type':    'client_credentials'
		'client_id':     repository.config.client_id
		'client_secret': repository.config.client_secret
	})
	mut request := http.new_request(.post, endpoint, data)
	request.validate = true
	request.verify = repository.config.ca_cert
	request.cert = repository.config.client_cert
	request.cert_key = repository.config.client_key
	request.allow_redirect = false
	request.add_custom_header('Content-Type', 'application/x-www-form-urlencoded') or { return err }
	response := request.do() or { return err }
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Keycloak token endpoint returned status ${response.status_code}')
	}
	token_response := json.decode(TokenResponse, response.body)!
	return token_response.access_token
}

fn (repository &KeycloakRepository) request(method http.Method, path string, body string) !http.Response {
	token := repository.token()!
	mut request := http.new_request(method, '${repository.config.base_url.trim_right('/')}${path}',
		body)
	request.validate = true
	request.verify = repository.config.ca_cert
	request.cert = repository.config.client_cert
	request.cert_key = repository.config.client_key
	request.allow_redirect = false
	request.add_custom_header('Authorization', 'Bearer ${token}') or { return err }
	request.add_custom_header('Accept', 'application/json') or { return err }
	if body != '' {
		request.add_custom_header('Content-Type', 'application/json') or { return err }
	}
	response := request.do() or { return err }
	if response.status_code < 200 || response.status_code >= 300 {
		if response.status_code == 409 {
			return error('user email already exists')
		}
		return error('Keycloak Admin API returned status ${response.status_code}')
	}
	return response
}
