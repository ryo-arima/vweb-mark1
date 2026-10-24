module usecase

import pkg.server.share

fn test_platform_admin_can_manage_all_service_configuration() {
	identity := share.from_headers('user-1', 'platform-admin', '')
	decision := decide(identity, 'service-b', 'group-b')
	assert decision.can_manage_groups
	assert decision.can_manage_roles
	assert decision.can_manage_policies
	assert decision.can_manage_members
	assert decision.can_write_resources
}

fn test_service_admin_requires_service_scope() {
	identity := share.from_headers('user-1', 'service-b-admin', '/services/service-b/administrators')
	assert is_service_admin(identity, 'service-b')
	assert !is_service_admin(identity, 'service-a')
}

fn test_group_admin_can_manage_members_but_not_policies() {
	identity := share.from_headers('user-1', 'group-admin', '/services/service-b/groups/group-b/administrators')
	decision := decide(identity, 'service-b', 'group-b')
	assert decision.can_manage_members
	assert decision.can_assign_roles
	assert !decision.can_manage_policies
	assert !decision.can_write_resources
}

fn test_nested_group_uses_full_scope_path() {
	identity := share.from_headers('user-1', 'group-admin',
		'/services/service-b/groups/parent/child/administrators')
	decision := decide(identity, 'service-b', '/services/service-b/groups/parent/child')
	assert decision.can_manage_members
}

fn test_group_editor_and_viewer_have_resource_boundaries() {
	editor := share.from_headers('user-1', 'group-editor', '/services/service-b/groups/group-b/editors')
	viewer := share.from_headers('user-2', 'group-viewer', '/services/service-b/groups/group-b/viewers')
	assert decide(editor, 'service-b', 'group-b').can_write_resources
	assert !decide(viewer, 'service-b', 'group-b').can_write_resources
	assert decide(viewer, 'service-b', 'group-b').can_read_resources
}
