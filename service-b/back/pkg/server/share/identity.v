module share

pub struct BffIdentity {
pub:
	subject string
	roles   []string
	groups  []string
}

pub fn from_headers(subject string, roles string, groups string) BffIdentity {
	return BffIdentity{
		subject: subject
		roles:   split_header(roles)
		groups:  split_header(groups)
	}
}

fn split_header(value string) []string {
	if value.trim_space() == '' {
		return []string{}
	}
	return value.split(',').map(it.trim_space()).filter(it != '')
}
