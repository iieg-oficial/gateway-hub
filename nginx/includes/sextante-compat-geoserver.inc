location ^~ /geoserver/web {
    return 301 /sextante/web$is_args$args;
}

location ^~ /geoserver/rest {
    return 301 /sextante/rest$is_args$args;
}

location ^~ /geoserver/j_spring_security {
    return 301 /sextante/j_spring_security$is_args$args;
}

location ^~ /geoserver/ontoy {
    return 301 /sextante/ontoy;
}

location ^~ /geoserver/ {
    rewrite ^/geoserver/(.*)$ /sextante/$1 last;
}
