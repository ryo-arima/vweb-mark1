module controller

pub struct HealthResponse {
pub:
	status    string
	service   string
	component string
}

pub fn health_response(service string, status string) HealthResponse {
	return HealthResponse{
		status:    status
		service:   service
		component: 'service-back'
	}
}

pub fn identity_response(service string, subject string) map[string]string {
	return {
		'service':         service
		'identity_source': 'bff'
		'user_subject':    subject
	}
}
