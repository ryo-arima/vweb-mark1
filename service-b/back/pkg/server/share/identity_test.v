module share

fn test_identity_headers_are_split() {
	identity := from_headers('user-1', 'service-b-admin, group-editor', '/services/service-b/groups/group-b/editors')
	assert identity.subject == 'user-1'
	assert identity.roles == ['service-b-admin', 'group-editor']
	assert identity.groups == ['/services/service-b/groups/group-b/editors']
}
