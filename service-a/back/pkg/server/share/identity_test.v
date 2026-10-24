module share

fn test_identity_headers_are_split() {
	identity := from_headers('user-1', 'service-a-admin, group-viewer', '/services/service-a/groups/group-a/viewers')
	assert identity.subject == 'user-1'
	assert identity.roles == ['service-a-admin', 'group-viewer']
	assert identity.groups == ['/services/service-a/groups/group-a/viewers']
}
