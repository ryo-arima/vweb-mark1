module usecase

pub fn subject_from_header(value string) string {
	return value.trim_space()
}
