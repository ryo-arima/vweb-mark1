module repository

fn test_empty_database_url_keeps_local_scaffold_ready() {
	repository := new_authorization_repository('')
	assert repository.ready()
}

fn test_unreachable_database_is_not_ready() {
	repository := new_authorization_repository('postgres://invalid:invalid@127.0.0.1:1/invalid')
	assert !repository.ready()
}
