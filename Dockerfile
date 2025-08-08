FROM openresty/openresty:alpine

RUN apk add --no-cache sudo

RUN apk update && apk add --no-cache \
    nano \
    certbot \
    bash \
    curl \
    lua-resty-core \
    lua-resty-lrucache


RUN mkdir -p /var/www/certbot/.well-known/acme-challenge \
    && mkdir -p /var/lib/certbot \
    && chmod -R 777 /var/www/certbot \
    && chmod -R 777 /var/lib/certbot \
    && chmod -R 777 /tmp


RUN mkdir -p /var/www/certbot /etc/nginx/lua && \
    touch /etc/nginx/domains.json \
    && chmod -R 777 /etc/nginx/domains.json\
    && chown root /etc/nginx/domains.json



RUN mkdir -p /var/log/nginx && \
    touch /var/log/nginx/access.log /var/log/nginx/error.log

RUN mkdir -p /var/log/letsencrypt && chown -R root:root /var/log/letsencrypt

WORKDIR /usr/local/openresty/nginx
USER root
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
