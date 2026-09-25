location ^~ /sextante/web {
    include /etc/nginx/includes/allow-admin.inc;
    deny all;
    limit_req zone=general burst=20 nodelay;
    proxy_pass http://sextante/sextante/web;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/sextante-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
}

location ^~ /sextante/rest {
    include /etc/nginx/includes/allow-admin.inc;
    deny all;
    limit_req zone=general burst=20 nodelay;
    proxy_pass http://sextante/sextante/rest;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/sextante-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
}

location ^~ /sextante/j_spring_security {
    include /etc/nginx/includes/allow-admin.inc;
    deny all;
    limit_req zone=general burst=20 nodelay;
    proxy_pass http://sextante/sextante/j_spring_security;
    include /etc/nginx/includes/proxy-params.inc;
    include /etc/nginx/includes/sextante-hide-headers.inc;
    proxy_set_header Accept-Encoding identity;
}

location ^~ /sextante/ {
    location ~ "[;]" {
        return 403;
    }

    location ~ ^/sextante/([^/]+/)?(wps|gwc/rest|rest|web)(/|$) {
        return 403;
    }

    location ~ ^/sextante/gwc/service/ {
        limit_except GET HEAD OPTIONS {
            deny all;
        }

        proxy_pass http://sextante;
        include /etc/nginx/includes/sextante-proxy-params.inc;
        include /etc/nginx/includes/sextante-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;

        proxy_cache sextante_cache;
        proxy_cache_key "$host$request_uri";
        proxy_cache_valid 200 30d;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 30s;
        proxy_cache_use_stale error timeout updating;
        proxy_cache_background_update on;
        proxy_ignore_headers "Set-Cookie" "Expires" "Cache-Control";

        proxy_hide_header Cache-Control;
        proxy_hide_header Expires;
        proxy_hide_header Pragma;
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        add_header X-Cache-Status $upstream_cache_status always;
        include /etc/nginx/includes/security-headers.inc;
    }

    location ~ ^/sextante/([^/]+/)?wms {
        limit_except GET HEAD OPTIONS {
            deny all;
        }

        proxy_pass http://sextante;
        include /etc/nginx/includes/sextante-proxy-params.inc;
        include /etc/nginx/includes/sextante-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;
        proxy_read_timeout 120s;

        proxy_cache sextante_cache;
        proxy_cache_key "$host$request_uri";
        proxy_cache_valid 200 6h;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 30s;
        proxy_cache_lock_age 30s;
        proxy_cache_use_stale error timeout updating;
        proxy_cache_background_update on;
        proxy_ignore_headers "Set-Cookie" "Expires" "Cache-Control";
        proxy_no_cache $sextante_no_cache;
        proxy_cache_bypass $sextante_no_cache;
        add_header X-Cache-Status $upstream_cache_status always;
        include /etc/nginx/includes/security-headers.inc;
    }

    location ~ ^/sextante/ows {
        limit_except GET HEAD OPTIONS {
            deny all;
        }

        set $referer_host "";
        if ($http_referer ~* "^https?://([^/:]+)") { set $referer_host $1; }
        set $valid_referer 0;
        if ($http_referer = "")           { set $valid_referer 1; }
        if ($referer_host = $host)        { set $valid_referer 1; }
        if ($referer_host = "localhost")  { set $valid_referer 1; }
        if ($valid_referer = 0) {
            return 403;
        }

        if ($ua_bloqueado_sextante) {
            return 403;
        }

        proxy_pass http://sextante;
        include /etc/nginx/includes/sextante-proxy-params.inc;
        include /etc/nginx/includes/sextante-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;

        proxy_cache sextante_cache;
        proxy_cache_key "$host$request_uri";
        proxy_cache_valid 200 6h;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 30s;
        proxy_cache_lock_age 30s;
        proxy_cache_use_stale error timeout updating;
        proxy_ignore_headers "Set-Cookie" "Expires" "Cache-Control";
        proxy_no_cache $sextante_no_cache;
        proxy_cache_bypass $sextante_no_cache;
        add_header X-Cache-Status $upstream_cache_status always;
        include /etc/nginx/includes/security-headers.inc;

        if ($arg_request ~* "Transaction") {
            return 403;
        }

        proxy_intercept_errors on;
    }

    location ~ ^/sextante/(wfs|wcs) {
        limit_except GET HEAD OPTIONS {
            deny all;
        }

        set $referer_host "";
        if ($http_referer ~* "^https?://([^/:]+)") { set $referer_host $1; }
        set $valid_referer 0;
        if ($http_referer = "")           { set $valid_referer 1; }
        if ($referer_host = $host)        { set $valid_referer 1; }
        if ($referer_host = "localhost")  { set $valid_referer 1; }
        if ($valid_referer = 0) {
            return 403;
        }

        if ($ua_bloqueado_sextante) {
            return 403;
        }

        limit_req zone=sextante_download burst=300;
        limit_req zone=mapalab_plugin burst=10 nodelay;
        proxy_pass http://sextante;
        include /etc/nginx/includes/sextante-proxy-params.inc;
        include /etc/nginx/includes/sextante-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;

        include /etc/nginx/includes/security-headers.inc;

        if ($arg_request ~* "Transaction") {
            return 403;
        }

        proxy_intercept_errors on;
    }

    location ~ ^/sextante/[^/]+/(wfs|wcs) {
        limit_except GET HEAD OPTIONS {
            deny all;
        }

        set $referer_host "";
        if ($http_referer ~* "^https?://([^/:]+)") { set $referer_host $1; }
        set $valid_referer 0;
        if ($http_referer = "")           { set $valid_referer 1; }
        if ($referer_host = $host)        { set $valid_referer 1; }
        if ($referer_host = "localhost")  { set $valid_referer 1; }
        if ($valid_referer = 0) {
            return 403;
        }

        if ($ua_bloqueado_sextante) {
            return 403;
        }

        limit_req zone=sextante_download burst=300;
        limit_req zone=mapalab_plugin burst=10 nodelay;
        proxy_pass http://sextante;
        include /etc/nginx/includes/sextante-proxy-params.inc;
        include /etc/nginx/includes/sextante-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;

        if ($arg_request ~* "Transaction") {
            return 403;
        }

        proxy_intercept_errors on;
    }

    location /sextante/ {
        limit_except GET HEAD {
            deny all;
        }

        limit_req zone=sextante_download burst=300;
        limit_req zone=mapalab_plugin burst=10 nodelay;
        proxy_pass http://sextante/sextante/;
        include /etc/nginx/includes/sextante-proxy-params.inc;
        include /etc/nginx/includes/sextante-hide-headers.inc;
        proxy_set_header Accept-Encoding identity;
        proxy_read_timeout 120s;
    }
}
