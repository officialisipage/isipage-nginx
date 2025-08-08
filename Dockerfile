FROM openresty/openresty:alpine

RUN apk update && apk add --no-cache \
    certbot \
    bash \
    curl \
    lua-resty-core \
    lua-resty-lrucache

RUN mkdir -p /var/www/certbot /etc/nginx/lua && \
    touch /etc/nginx/domains.json && \
    chown -R nginx:nginx /var/www/certbot /etc/nginx/domains.json

WORKDIR /usr/local/openresty/nginx
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
