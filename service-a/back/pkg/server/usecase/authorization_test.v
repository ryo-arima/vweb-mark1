module usecase

import pkg.server.share

fn test_platform_admin_can_manage_all_service_configuration() {
	identity := share.from_headers('user-1', 'platform-admin', '')
	decision := decide(identity, 'service-a', 'group-a')
	assert decision.can_manage_groups
	assert decision.can_manage_roles
	assert decision.can_manage_policies
	assert decision.can_manage_members
	assert decision.can_write_resources
}

fn test_service_admin_requires_service_scope() {
	identity := share.from_headers('user-1', 'service-a-admin', '/services/service-a/administrators')
	assert is_service_admin(identity, 'service-a')
	assert !is_service_admin(identity, 'service-b')
}

fn test_group_admin_can_manage_members_but_not_policies() {
	identity := share.from_headers('user-1', 'group-admin', '/services/service-a/groups/group-a/administrators')
	decision := decide(identity, 'service-a', 'group-a')
	assert decision.can_manage_members
	assert decision.can_assign_roles
	assert !decision.can_manage_policies
	assert !decision.can_write_resources
}

fn test_nested_group_uses_full_scope_path() {
	identity := share.from_headers('user-1', 'group-admin',
		'/services/service-a/groups/parent/child/administrators')
	decision := decide(identity, 'service-a', '/services/service-a/groups/parent/child')
	assert decision.can_manage_members
}

fn test_group_editor_and_viewer_have_resource_boundaries() {
	editor := share.from_headers('user-1', 'group-editor', '/services/service-a/groups/group-a/editors')
	viewer := share.from_headers('user-2', 'group-viewer', '/services/service-a/groups/group-a/viewers')
	assert decide(editor, 'service-a', 'group-a').can_write_resources
	assert !decide(viewer, 'service-a', 'group-a').can_write_resources
	assert decide(viewer, 'service-a', 'group-a').can_read_resources
}
