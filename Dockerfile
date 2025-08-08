FROM openresty/openresty:alpine

RUN apk add --no-cache sudo

RUN apk update && apk add --no-cache \
    certbot \
    bash \
    curl \
    lua-resty-core \
    lua-resty-lrucache

RUN mkdir -p /var/lib/certbot && chmod -R 777 /var/lib/certbot
RUN mkdir -p /var/www/certbot && chmod -R 777 /var/www/certbot

RUN mkdir -p /var/www/certbot/.well-known/acme-challenge && \
    chmod -R 777 /var/www/certbot

RUN mkdir -p /var/www/certbot /etc/nginx/lua && \
    touch /etc/nginx/domains.json

RUN mkdir -p /var/log/nginx && \
    touch /var/log/nginx/access.log /var/log/nginx/error.log

RUN mkdir -p /var/log/letsencrypt && chown -R root:root /var/log/letsencrypt

RUN echo "nginx ALL=(ALL) NOPASSWD: /usr/bin/certbot" >> /etc/sudoers
WORKDIR /usr/local/openresty/nginx
EXPOSE 80 443
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
