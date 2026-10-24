module config

import os

pub struct Config {
pub:
	environment            string
	service_name           string
	port                   int
	database_url           string
	keycloak_api_url       string
	keycloak_realm         string
	keycloak_client_id     string
	keycloak_client_secret string
	keycloak_ca_cert       string
	keycloak_client_cert   string
	keycloak_client_key    string
}

pub fn load() Config {
	return Config{
		environment:            os.getenv_opt('APP_ENV') or { 'development' }
		service_name:           os.getenv_opt('SERVICE_NAME') or { 'service-a' }
		port:                   (os.getenv_opt('PORT') or { '8000' }).int()
		database_url:           os.getenv('DATABASE_URL')
		keycloak_api_url:       os.getenv_opt('KEYCLOAK_API_URL') or { '' }
		keycloak_realm:         os.getenv_opt('KEYCLOAK_REALM') or { 'vweb' }
		keycloak_client_id:     os.getenv_opt('KEYCLOAK_API_CLIENT_ID') or { '' }
		keycloak_client_secret: os.getenv_opt('KEYCLOAK_API_CLIENT_SECRET') or { '' }
		keycloak_ca_cert:       os.getenv_opt('KEYCLOAK_CA_CERT') or { '' }
		keycloak_client_cert:   os.getenv_opt('KEYCLOAK_CLIENT_CERT') or { '' }
		keycloak_client_key:    os.getenv_opt('KEYCLOAK_CLIENT_KEY') or { '' }
	}
}
