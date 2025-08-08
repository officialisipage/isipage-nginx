FROM openresty/openresty:alpine

RUN apk update && apk add --no-cache \
    certbot \
    bash \
    curl \
    lua-resty-core \
    lua-resty-lrucache

RUN mkdir -p /var/www/certbot /etc/nginx/lua && \
    touch /etc/nginx/domains.json

RUN mkdir -p /var/log/nginx && \
    touch /var/log/nginx/access.log /var/log/nginx/error.log

RUN mkdir -p /var/log/letsencrypt && chown -R root:root /var/log/letsencrypt

WORKDIR /usr/local/openresty/nginx
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
