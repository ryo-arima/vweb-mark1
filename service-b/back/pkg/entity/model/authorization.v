module model

pub struct User {
pub:
	id           string
	keycloak_sub string
	email        string
	display_name string
}

pub struct Group {
pub:
	id          string
	parent_id   ?string
	name        string
	path        string
	description string
	keycloak_id string
}

pub struct Role {
pub:
	id          string
	name        string
	description string
}

pub struct Policy {
pub:
	id       string
	role_id  string
	resource string
	action   string
	effect   string
}

pub struct Member {
pub mut:
	id           string
	group_id     string
	group_name   string
	group_path   string
	user_id      string
	keycloak_sub string
	email        string
	display_name string
	role_names   []string
}

pub struct MemberRole {
pub:
	member_id string
	role_id   string
}
