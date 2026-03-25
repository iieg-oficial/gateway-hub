location ^~ /geoserver/web {
    include /etc/nginx/includes/vpn-access.inc;
    proxy_pass http://geoserver/geoserver/web;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/geoserver-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
}

location ^~ /geoserver/rest {
    include /etc/nginx/includes/vpn-access.inc;
    proxy_pass http://geoserver/geoserver/rest;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/geoserver-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
}

location ^~ /geoserver/j_spring_security {
    include /etc/nginx/includes/vpn-access.inc;
    proxy_pass http://geoserver/geoserver/j_spring_security;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/geoserver-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
}

location ^~ /geoserver/ {
    location ~ ^/geoserver/ows {
        valid_referers server_names *.$host $host localhost;
        if ($invalid_referer) {
            return 403;
        }

        if ($http_user_agent ~* (curl|wget|python|scrapy|httpclient|bot|spider|java|perl|ruby|php|go-http|node-fetch|axios|postman|insomnia|httpie|headless|phantom|selenium|puppeteer|playwright|ChatGPT|Google-Extended|anthropic|^$)) {
            return 403;
        }

        proxy_pass http://geoserver;
        include /etc/nginx/includes/proxy-params.inc;
        include /etc/nginx/includes/geoserver-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;

        proxy_cache geoserver_cache;
        proxy_cache_key "$request_uri$arg_outputFormat";
        proxy_cache_valid 200 6h;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 10s;
        proxy_cache_use_stale error timeout updating;
        proxy_ignore_headers "Set-Cookie" "Expires" "Cache-Control";
        proxy_no_cache $geoserver_no_cache;
        proxy_cache_bypass $geoserver_no_cache;
        add_header X-Cache-Status $upstream_cache_status always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

        if ($arg_request ~* "Transaction") {
            return 403;
        }

        proxy_intercept_errors on;
    }

    location ~ ^/geoserver/(wfs|wcs) {
        valid_referers server_names *.$host $host localhost;
        if ($invalid_referer) {
            return 403;
        }

        if ($http_user_agent ~* (curl|wget|python|scrapy|httpclient|bot|spider|java|perl|ruby|php|go-http|node-fetch|axios|postman|insomnia|httpie|headless|phantom|selenium|puppeteer|playwright|ChatGPT|Google-Extended|anthropic|^$)) {
            return 403;
        }

        limit_req zone=geoserver_download burst=10 nodelay;
        proxy_pass http://geoserver;
        include /etc/nginx/includes/proxy-params.inc;
        include /etc/nginx/includes/geoserver-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;

        proxy_cache geoserver_cache;
        proxy_cache_key "$request_uri$arg_outputFormat";
        proxy_cache_valid 200 6h;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 10s;
        proxy_cache_use_stale error timeout updating;
        proxy_ignore_headers "Set-Cookie" "Expires" "Cache-Control";
        proxy_no_cache $geoserver_no_cache;
        proxy_cache_bypass $geoserver_no_cache;
        add_header X-Cache-Status $upstream_cache_status always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

        if ($arg_request ~* "Transaction") {
            return 403;
        }

        proxy_intercept_errors on;
    }

    proxy_pass http://geoserver/geoserver/;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/geoserver-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
    proxy_read_timeout 120s;
}
