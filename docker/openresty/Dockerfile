FROM openresty/openresty:1.27.1.2-alpine

# Install the pure-Lua OIDC, HTTP, JWT, PostgreSQL, and session libraries used
# by the BFF. Perl and curl are build-time dependencies of the package manager.
ARG LUA_RESTY_OPENIDC_VERSION=1.8.0

# lua-resty-openidc 1.8.x is the first release compatible with session 4.x.
RUN apk add --no-cache curl perl \
    && /usr/local/openresty/bin/opm get bungle/lua-resty-session \
    && /usr/local/openresty/bin/opm get ledgetech/lua-resty-http \
    && /usr/local/openresty/bin/opm get cdbattags/lua-resty-jwt \
    && /usr/local/openresty/bin/opm get xiangnanscu/pgmoon \
    && curl --fail --silent --show-error --location \
       "https://raw.githubusercontent.com/zmartzone/lua-resty-openidc/v${LUA_RESTY_OPENIDC_VERSION}/lib/resty/openidc.lua" \
       --output /usr/local/openresty/site/lualib/resty/openidc.lua \
    && apk del curl perl
