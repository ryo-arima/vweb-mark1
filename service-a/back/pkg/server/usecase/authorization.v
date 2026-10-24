module usecase

import pkg.server.share

pub const role_platform_admin = 'platform-admin'
pub const role_group_admin = 'group-admin'
pub const role_group_editor = 'group-editor'
pub const role_group_viewer = 'group-viewer'

pub struct AuthorizationDecision {
pub:
	can_manage_groups   bool
	can_manage_roles    bool
	can_manage_policies bool
	can_manage_members  bool
	can_assign_roles    bool
	can_read_resources  bool
	can_write_resources bool
}

pub fn decide(identity share.BffIdentity, service string, group string) AuthorizationDecision {
	service_admin := is_service_admin(identity, service)
	group_admin := has_group_capability(identity, service, group, role_group_admin)
	group_editor := has_group_capability(identity, service, group, role_group_editor)
	group_viewer := has_group_capability(identity, service, group, role_group_viewer)

	return AuthorizationDecision{
		can_manage_groups:   service_admin
		can_manage_roles:    service_admin
		can_manage_policies: service_admin
		can_manage_members:  service_admin || group_admin
		can_assign_roles:    service_admin || group_admin
		can_read_resources:  service_admin || group_editor || group_viewer
		can_write_resources: service_admin || group_editor
	}
}

pub fn is_service_admin(identity share.BffIdentity, service string) bool {
	if has_role(identity, role_platform_admin) {
		return true
	}
	return has_role(identity, '${service}-admin')
		&& has_group(identity, '/services/${service}/administrators')
}

pub fn has_group_capability(identity share.BffIdentity, service string, group string, role string) bool {
	if is_service_admin(identity, service) {
		return true
	}
	return has_role(identity, role)
		&& has_group(identity, group_scope_path(service, group, role))
}

pub fn can_view_group(identity share.BffIdentity, service string, group_path string) bool {
	decision := decide(identity, service, group_path)
	return decision.can_manage_groups || decision.can_manage_members || decision.can_read_resources
}

fn group_scope_path(service string, group string, role string) string {
	base_path := if group.starts_with('/services/') {
		group
	} else {
		'/services/${service}/groups/${group}'
	}
	return '${base_path}/${role_group_name(role)}'
}

fn role_group_name(role string) string {
	return match role {
		role_group_admin { 'administrators' }
		role_group_editor { 'editors' }
		role_group_viewer { 'viewers' }
		else { '' }
	}
}

fn has_role(identity share.BffIdentity, role string) bool {
	return role in identity.roles
}

fn has_group(identity share.BffIdentity, path string) bool {
	return path in identity.groups
}
