FROM nginx:1.30.4-alpine

RUN apk add --no-cache gettext \
    && rm -f /etc/nginx/conf.d/default.conf

COPY nginx/templates/ /etc/nginx/templates/
COPY nginx/conf.d/ /etc/nginx/templates/conf.d/
COPY nginx/includes/ /etc/nginx/includes/
COPY nginx/error-pages/ /etc/nginx/error-pages/
COPY nginx/static/ /usr/share/nginx/html/

RUN mkdir -p /etc/nginx/certs /var/cache/nginx-data/sextante

EXPOSE 80 443

CMD ["/bin/sh", "-c", \
    "envsubst '${REAL_IP_FROM}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf && \
    for f in /etc/nginx/templates/conf.d/*; do \
        envsubst '${SEXTANTE_HOST} ${PORTAL_HOST} ${SITIO_HOST} ${MAPALAB_HOST}' < \"$f\" > /etc/nginx/conf.d/$(basename \"${f%.template}\"); \
    done && \
    envsubst '${PORTAL_HOST} ${MAPALAB_HOST} ${ACERVO_HOST} ${MARIACHI_HOST} ${SEXTANTE_HOST} ${APP_DOMAIN} ${SSL_CERTIFICATE} ${SSL_CERTIFICATE_KEY} ${GTM_ID} ${SEO_ENABLED} ${CONN_LIMIT}' \
        < /etc/nginx/templates/gateway.conf.template > /etc/nginx/conf.d/gateway.conf && \
    for c in $ADMIN_ALLOW_CIDRS; do echo \"allow $c;\"; done > /etc/nginx/includes/allow-admin.inc && \
    for c in $MONITOR_ALLOW_CIDRS; do echo \"allow $c;\"; done > /etc/nginx/includes/allow-monitor.inc && \
    for c in $INTERNAL_UPLOAD_ALLOW_CIDRS; do echo \"allow $c;\"; done > /etc/nginx/includes/allow-internal-upload.inc && \
    envsubst '${CSP_EXTRA_ORIGINS}' \
        < /etc/nginx/includes/security-headers.inc.template > /etc/nginx/includes/security-headers.inc && \
    if [ -n \"$GTM_ID\" ]; then envsubst '${GTM_ID}' < /etc/nginx/includes/gtm.inc.template > /etc/nginx/includes/gtm.inc; else : > /etc/nginx/includes/gtm.inc; fi && \
    if [ -n \"$SSL_TRUSTED_CERTIFICATE\" ] && [ -r \"$SSL_TRUSTED_CERTIFICATE\" ]; then \
        envsubst '${SSL_TRUSTED_CERTIFICATE}' < /etc/nginx/includes/ssl-stapling.inc.template > /etc/nginx/includes/ssl-stapling.inc; \
    else \
        echo \"OCSP stapling desactivado: SSL_TRUSTED_CERTIFICATE vacia o ilegible ('$SSL_TRUSTED_CERTIFICATE')\" >&2; \
        : > /etc/nginx/includes/ssl-stapling.inc; \
    fi && \
    nginx -g 'daemon off;'"]
