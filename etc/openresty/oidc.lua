local cjson = require("cjson.safe")
local dns = require("resty.dns.resolver")
local http = require("resty.http")
local ssl = require("ngx.ssl")
local session = require("resty.session")

local M = {}

local function required(name)
    local value = os.getenv(name)
    if not value or value == "" then
        error(name .. " is required")
    end
    return value
end

local public_url = required("VWEB_PUBLIC_URL"):gsub("/+$", "")
local public_host = public_url:match("^https?://([^/]+)$")
if not public_host then
    error("VWEB_PUBLIC_URL must be an absolute URL without a path")
end
local public_auth_pattern = "^" .. public_url:gsub("([^%w])", "%%%1") .. "/auth(.*)$"

local function read_file(path)
    local file, err = io.open(path, "rb")
    if not file then
        error("unable to read " .. path .. ": " .. (err or "unknown error"))
    end
    local content = file:read("*a")
    file:close()
    return content
end

local client_certificate_chain = assert(ssl.parse_pem_cert(read_file("/etc/pki/openresty/client.crt")))
local client_private_key = assert(ssl.parse_pem_priv_key(read_file("/etc/pki/openresty/client.key")))

local function resolve_service(name)
    local cache = ngx.shared.vweb_oidc
    local cached = cache:get("dns:" .. name)
    if cached then
        return cached
    end

    local resolver, err = dns:new({
        nameservers = { "127.0.0.11" },
        timeout = 1000,
        retrans = 2,
    })
    if not resolver then
        error("unable to initialize Docker DNS resolver")
    end

    local answers, query_err = resolver:query(name, { qtype = dns.TYPE_A })
    resolver:destroy()
    if not answers or answers.errcode or #answers == 0 then
        error("unable to resolve service " .. name .. ": " .. (query_err or "no A record"))
    end

    for _, answer in ipairs(answers) do
        if answer.address then
            cache:set("dns:" .. name, answer.address, 30)
            return answer.address
        end
    end
    error("unable to resolve service " .. name .. ": no A record")
end

local function decorate_keycloak_request(request)
    request.ssl_client_cert = client_certificate_chain
    request.ssl_client_priv_key = client_private_key
    request.ssl_server_name = "keycloak"
    return request
end

local function session_options(postgres_host)
    return {
        secret = required("SESSION_ENCRYPTION_KEY"),
        storage = "postgres",
        postgres = {
            host = postgres_host or resolve_service("postgres"),
            port = 5432,
            username = "bff",
            password = required("VWEB_BFF_DB_PASSWORD"),
            database = "vweb",
            table = "bff.sessions",
            table_meta = "bff.sessions_meta",
            connect_timeout = 5000,
            send_timeout = 5000,
            read_timeout = 10000,
        },
        -- Prevent the session cookie from being scoped to another host.
        cookie_prefix = "__Host-",
        cookie_name = "vweb_sid",
        cookie_path = "/",
        cookie_http_only = true,
        cookie_secure = true,
        cookie_same_site = "Lax",
        remember = false,
        audience = "vweb-bff",
        store_metadata = true,
        hash_storage_key = true,
        hash_subject = true,
        idling_timeout = 1800,
        rolling_timeout = 3600,
        absolute_timeout = 28800,
    }
end

local function internalize_endpoint(value, keycloak_ip)
    if type(value) ~= "string" then
        return value
    end
    local path = value:match(public_auth_pattern)
    if path then
        return "https://" .. keycloak_ip .. ":8443" .. path
    end
    return value
end

local function load_discovery()
    local cache = ngx.shared.vweb_oidc
    local cached = cache:get("discovery")
    if cached then
        local document = cjson.decode(cached)
        if document then
            return document
        end
    end

    local client = http.new()
    client:set_timeouts(5000, 5000, 10000)
    local keycloak_ip = resolve_service("keycloak")
    local response, err = client:request_uri(
        "https://" .. keycloak_ip .. ":8443/realms/vweb/.well-known/openid-configuration",
        decorate_keycloak_request({
            method = "GET",
            headers = {
                ["Host"] = public_host,
                ["X-Forwarded-Proto"] = "https",
                ["X-Forwarded-Host"] = public_host,
                ["X-Forwarded-Port"] = "443",
            },
            ssl_verify = true,
            keepalive = true,
        })
    )
    if not response or response.status ~= 200 then
        error("unable to load Keycloak discovery: " .. (err or tostring(response and response.status)))
    end

    local document, decode_err = cjson.decode(response.body)
    if not document then
        error("unable to decode Keycloak discovery: " .. (decode_err or "invalid JSON"))
    end

    for _, field in ipairs({
        "token_endpoint",
        "userinfo_endpoint",
        "jwks_uri",
        "introspection_endpoint",
        "revocation_endpoint",
        "pushed_authorization_request_endpoint",
    }) do
        document[field] = internalize_endpoint(document[field], keycloak_ip)
    end

    local encoded = cjson.encode(document)
    if not encoded then
        error("unable to cache Keycloak discovery")
    end
    cache:set("discovery", encoded, 300)
    return document
end

local function oidc_options()
    return {
        redirect_uri = public_url .. "/auth/callback",
        discovery = load_discovery(),
        client_id = "vweb-bff",
        client_secret = required("KEYCLOAK_BFF_CLIENT_SECRET"),
        token_endpoint_auth_method = "client_secret_basic",
        scope = "openid profile email",
        use_pkce = true,
        ssl_verify = "yes",
        timeout = {
            connect = 5000,
            send = 5000,
            read = 10000,
        },
        renew_access_token_on_expiry = true,
        session_contents = {
            id_token = true,
            access_token = true,
            user = true,
        },
        http_request_decorator = decorate_keycloak_request,
    }
end

local function append_values(target, values)
    if type(values) == "string" then
        table.insert(target, values)
    elseif type(values) == "table" then
        for _, value in ipairs(values) do
            if type(value) == "string" then
                table.insert(target, value)
            end
        end
    end
end

local function set_identity(result)
    local id_token = result and result.id_token or {}
    local roles = {}
    local realm_access = id_token.realm_access or {}
    append_values(roles, realm_access.roles)
    local resource_access = id_token.resource_access or {}
    local bff_access = resource_access["vweb-bff"] or {}
    append_values(roles, bff_access.roles)

    local groups = {}
    append_values(groups, id_token.groups)
    local email = id_token.email or id_token.preferred_username or ""
    ngx.var.bff_user_sub = id_token.sub or ""
    ngx.var.bff_user_email = email
    ngx.var.bff_user_roles = table.concat(roles, ",")
    ngx.var.bff_user_groups = table.concat(groups, ",")
end

local function fail(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({ error = message }))
    return ngx.exit(status)
end

function M.init()
    session.init(session_options("postgres"))
end

function M.authenticate(unauthenticated_action, target_url)
    local openidc = require("resty.openidc")
    local result, err, _, openidc_session = openidc.authenticate(
        oidc_options(),
        target_url,
        unauthenticated_action,
        session_options()
    )
    if openidc_session then
        openidc_session:close()
    end
    if err then
        ngx.log(ngx.ERR, "OIDC authentication failed")
        if unauthenticated_action == "deny" then
            return fail(401, "authentication required")
        end
        return fail(502, "authentication provider unavailable")
    end
    if not result then
        if unauthenticated_action == "deny" then
            return fail(401, "authentication required")
        end
        return fail(500, "authentication result unavailable")
    end
    set_identity(result)
end

function M.session_info()
    local current, err, exists = session.open()
    if err and err ~= "missing session cookie" then
        ngx.log(ngx.ERR, "BFF session lookup failed")
        return fail(500, "session store unavailable")
    end
    if not exists then
        return fail(401, "authentication required")
    end

    local data = current:get_data() or {}
    local id_token = data.id_token or {}
    current:close()
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        authenticated = true,
        subject = id_token.sub,
        email = id_token.email or id_token.preferred_username,
        groups = id_token.groups or {},
    }))
end

function M.logout()
    local ok, err = session.destroy(session_options())
    if not ok and err then
        ngx.log(ngx.ERR, "BFF logout failed")
        return fail(500, "logout failed")
    end
    return ngx.redirect("/")
end

return M
