FROM nginx:1.28.2-alpine

RUN apk add --no-cache gettext \
    && rm -f /etc/nginx/conf.d/default.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/templates/ /etc/nginx/templates/
COPY nginx/conf.d/ /etc/nginx/templates/conf.d/
COPY nginx/includes/ /etc/nginx/includes/
COPY nginx/error-pages/ /etc/nginx/error-pages/
COPY nginx/static/ /usr/share/nginx/html/
COPY nginx/version.json /etc/nginx/version.json

RUN mkdir -p /etc/nginx/certs /var/cache/nginx/geoserver

EXPOSE 80 443

CMD ["/bin/sh", "-c", \
    "for f in /etc/nginx/templates/conf.d/*; do \
        envsubst '${GEOSERVER_HOST}' < \"$f\" > /etc/nginx/conf.d/$(basename \"${f%.template}\"); \
    done && \
    envsubst '${PORTAL_HOST} ${MAPALAB_HOST} ${ACERVO_HOST} ${ACERVO_CONSOLE_HOST} ${MARIACHI_HOST} ${GEOSERVER_HOST} ${HUACHICOL_HOST} ${APP_DOMAIN} ${SSL_CERTIFICATE} ${SSL_CERTIFICATE_KEY} ${GTM_ID} ${SEO_ENABLED}' \
        < /etc/nginx/templates/gateway.conf.template > /etc/nginx/conf.d/gateway.conf && \
    if [ -n \"$GTM_ID\" ]; then envsubst '${GTM_ID}' < /etc/nginx/includes/gtm.inc.template > /etc/nginx/includes/gtm.inc; else : > /etc/nginx/includes/gtm.inc; fi && \
    nginx -g 'daemon off;'"]
