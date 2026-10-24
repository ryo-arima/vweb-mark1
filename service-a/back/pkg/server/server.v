module server

import json
import net.http
import pkg.server.controller
import pkg.server.repository
import pkg.server.share
import pkg.server.usecase
import veb

pub struct Context {
	veb.Context
}

pub struct App {
pub:
	service_name string
	database     &repository.AuthorizationRepository
}

pub struct AuthorizationResponse {
pub:
	service  string
	group    string
	subject  string
	decision usecase.AuthorizationDecision
}

pub struct GroupRequest {
pub:
	name        string
	description string
	parent_id   string
}

pub struct MemberCreateRequest {
pub:
	keycloak_sub string
	email        string
	role_names   []string
}

pub struct MemberUpdateRequest {
pub:
	email        string
	display_name string
	role_names   []string
}

struct ErrorResponse {
pub:
	error string
}

pub fn new_app(service_name string) &App {
	return new_app_with_database(service_name, '')
}

pub fn new_app_with_database(service_name string, database_url string) &App {
	return &App{
		service_name: service_name
		database:     repository.new_authorization_repository(database_url)
	}
}

pub fn new_app_with_config(service_name string, database_url string, keycloak_config repository.KeycloakConfig) &App {
	return &App{
		service_name: service_name
		database:     repository.new_authorization_repository_with_config(database_url,
			service_name, keycloak_config)
	}
}

@[get]
pub fn (app &App) healthz(mut ctx Context) veb.Result {
	return ctx.json(controller.health_response(app.service_name, 'ok'))
}

@['/readyz'; get]
pub fn (app &App) readiness(mut ctx Context) veb.Result {
	if !app.database.ready() {
		ctx.res.set_status(.service_unavailable)
		return ctx.json(controller.health_response(app.service_name, 'not_ready'))
	}
	return ctx.json(controller.health_response(app.service_name, 'ready'))
}

@['/v1/identity'; get]
pub fn (app &App) identity(mut ctx Context) veb.Result {
	subject := usecase.subject_from_header(ctx.get_custom_header('X-User-Sub') or { '' })
	return ctx.json(controller.identity_response(app.service_name, subject))
}

@['/v1/authorization/decision'; get]
pub fn (app &App) authorization_decision(mut ctx Context) veb.Result {
	identity := identity_from_context(ctx)
	group := ctx.query['group'] or { '' }
	if identity.subject == '' || group == '' {
		return failure(mut ctx, .unauthorized, 'authenticated BFF identity and group query parameter are required')
	}
	return ctx.json(AuthorizationResponse{
		service:  app.service_name
		group:    group
		subject:  identity.subject
		decision: usecase.decide(identity, app.service_name, group)
	})
}

@['/v1/groups'; get]
pub fn (app &App) list_groups(mut ctx Context) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	groups := app.database.list_groups() or { return repository_failure(mut ctx, err.msg()) }
	visible_groups := groups.filter(usecase.can_view_group(identity, app.service_name, it.path))
	return ctx.json(visible_groups)
}

@['/v1/groups'; post]
pub fn (app &App) create_group(mut ctx Context) veb.Result {
	identity := identity_from_context(ctx)
	decision := usecase.decide(identity, app.service_name, '')
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	if !decision.can_manage_groups {
		return failure(mut ctx, .forbidden, 'service administrator role is required')
	}
	request := json.decode(GroupRequest, ctx.req.data) or {
		return failure(mut ctx, .bad_request, 'invalid group request')
	}
	name := valid_name(request.name) or {
		return failure(mut ctx, .bad_request, 'group name is invalid')
	}
	group := app.database.create_group(name, request.description, request.parent_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	return ctx.json(group)
}

@['/v1/groups/:group_id'; get]
pub fn (app &App) get_group(mut ctx Context, group_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	group := app.database.get_group(group_id) or { return repository_failure(mut ctx, err.msg()) }
	if !usecase.can_view_group(identity, app.service_name, group.path) {
		return failure(mut ctx, .forbidden, 'group access is required')
	}
	return ctx.json(group)
}

@['/v1/groups/:group_id'; patch]
pub fn (app &App) update_group(mut ctx Context, group_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	group := app.database.get_group(group_id) or { return repository_failure(mut ctx, err.msg()) }
	if !usecase.decide(identity, app.service_name, group.path).can_manage_groups {
		return failure(mut ctx, .forbidden, 'service administrator role is required')
	}
	request := json.decode(GroupRequest, ctx.req.data) or {
		return failure(mut ctx, .bad_request, 'invalid group request')
	}
	name := valid_name(request.name) or {
		return failure(mut ctx, .bad_request, 'group name is invalid')
	}
	updated := app.database.update_group(group, name, request.description) or {
		return repository_failure(mut ctx, err.msg())
	}
	return ctx.json(updated)
}

@['/v1/groups/:group_id'; delete]
pub fn (app &App) delete_group(mut ctx Context, group_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	group := app.database.get_group(group_id) or { return repository_failure(mut ctx, err.msg()) }
	if !usecase.decide(identity, app.service_name, group.path).can_manage_groups {
		return failure(mut ctx, .forbidden, 'service administrator role is required')
	}
	members := app.database.list_members(group.id) or {
		return repository_failure(mut ctx, err.msg())
	}
	if members.len > 0 {
		return failure(mut ctx, .conflict, 'group still has members')
	}
	app.database.delete_group(group) or { return repository_failure(mut ctx, err.msg()) }
	return ctx.json({
		'deleted': group.id
	})
}

@['/v1/groups/:group_id/members'; get]
pub fn (app &App) list_members(mut ctx Context, group_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	group := app.database.get_group(group_id) or { return repository_failure(mut ctx, err.msg()) }
	decision := usecase.decide(identity, app.service_name, group.path)
	if !decision.can_read_resources && !decision.can_manage_members {
		return failure(mut ctx, .forbidden, 'group access is required')
	}
	members := app.database.list_members(group.id) or {
		return repository_failure(mut ctx, err.msg())
	}
	return ctx.json(members)
}

@['/v1/groups/:group_id/members'; post]
pub fn (app &App) create_member(mut ctx Context, group_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	group := app.database.get_group(group_id) or { return repository_failure(mut ctx, err.msg()) }
	if !usecase.decide(identity, app.service_name, group.path).can_manage_members {
		return failure(mut ctx, .forbidden, 'group administrator role is required')
	}
	request := json.decode(MemberCreateRequest, ctx.req.data) or {
		return failure(mut ctx, .bad_request, 'invalid member request')
	}
	if request.keycloak_sub.trim_space() == '' {
		return failure(mut ctx, .bad_request, 'keycloak_sub is required')
	}
	if request.email.trim_space() == '' {
		return failure(mut ctx, .bad_request, 'email is required')
	}
	member := app.database.create_member(group, request.keycloak_sub.trim_space(), request.email,
		request.role_names) or {
		return repository_failure(mut ctx, err.msg())
	}
	return ctx.json(member)
}

@['/v1/members'; get]
pub fn (app &App) list_all_members(mut ctx Context) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	if !usecase.decide(identity, app.service_name, '').can_manage_groups {
		return failure(mut ctx, .forbidden, 'service administrator role is required')
	}
	members := app.database.list_all_members() or {
		return repository_failure(mut ctx, err.msg())
	}
	return ctx.json(members)
}

@['/v1/members/:member_id'; get]
pub fn (app &App) get_member(mut ctx Context, member_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	member := app.database.get_member(member_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	group := app.database.get_group(member.group_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	decision := usecase.decide(identity, app.service_name, group.path)
	if !decision.can_read_resources && !decision.can_manage_members {
		return failure(mut ctx, .forbidden, 'group access is required')
	}
	return ctx.json(member)
}

@['/v1/members/:member_id'; patch]
pub fn (app &App) update_member(mut ctx Context, member_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	member := app.database.get_member(member_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	group := app.database.get_group(member.group_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	if !usecase.decide(identity, app.service_name, group.path).can_manage_members {
		return failure(mut ctx, .forbidden, 'group administrator role is required')
	}
	request := json.decode(MemberUpdateRequest, ctx.req.data) or {
		return failure(mut ctx, .bad_request, 'invalid member request')
	}
	updated := app.database.update_member(member, request.email, request.display_name,
		request.role_names) or { return repository_failure(mut ctx, err.msg()) }
	return ctx.json(updated)
}

@['/v1/members/:member_id'; delete]
pub fn (app &App) delete_member(mut ctx Context, member_id string) veb.Result {
	identity := identity_from_context(ctx)
	if identity.subject == '' {
		return failure(mut ctx, .unauthorized, 'authentication is required')
	}
	member := app.database.get_member(member_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	group := app.database.get_group(member.group_id) or {
		return repository_failure(mut ctx, err.msg())
	}
	if !usecase.decide(identity, app.service_name, group.path).can_manage_members {
		return failure(mut ctx, .forbidden, 'group administrator role is required')
	}
	app.database.delete_member(member) or { return repository_failure(mut ctx, err.msg()) }
	return ctx.json({
		'deleted': member.id
	})
}

fn identity_from_context(ctx &Context) share.BffIdentity {
	return share.from_headers(ctx.get_custom_header('X-User-Sub') or { '' }, ctx.get_custom_header('X-User-Roles') or {
		''
	}, ctx.get_custom_header('X-User-Groups') or { '' })
}

fn valid_name(value string) ?string {
	name := value.trim_space()
	if name == '' || name.contains('/') || name.contains('..') {
		return none
	}
	return name
}

fn failure(mut ctx Context, status http.Status, message string) veb.Result {
	ctx.res.set_status(status)
	return ctx.json(ErrorResponse{ error: message })
}

fn repository_failure(mut ctx Context, message string) veb.Result {
	if message.contains('email is required') || message.contains('must match the Keycloak user email') {
		return failure(mut ctx, .bad_request, message)
	}
	if message.contains('not found') {
		return failure(mut ctx, .not_found, message)
	}
	if message.contains('already exists') || message.contains('child groups') {
		return failure(mut ctx, .conflict, message)
	}
	return failure(mut ctx, .service_unavailable, 'service dependency is unavailable')
}
