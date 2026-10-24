module main

import pkg.config
import pkg.server.repository
import pkg.server
import veb

fn main() {
	settings := config.load()
	mut app := server.new_app_with_config(settings.service_name, settings.database_url,
		repository.KeycloakConfig{
		base_url:      settings.keycloak_api_url
		realm:         settings.keycloak_realm
		client_id:     settings.keycloak_client_id
		client_secret: settings.keycloak_client_secret
		ca_cert:       settings.keycloak_ca_cert
		client_cert:   settings.keycloak_client_cert
		client_key:    settings.keycloak_client_key
		bff_client_id: 'vweb-bff'
	})
	println('${settings.service_name} back listening on ${settings.port}')
	veb.run[server.App, server.Context](mut app, settings.port)
}
