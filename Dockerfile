FROM openresty/openresty:alpine

RUN apk add --no-cache bash certbot curl openssl busybox-suid lua-filesystem

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/mime.types /etc/nginx/mime.types
COPY nginx/lua /etc/nginx/lua
COPY domains.json /etc/nginx/domains.json

RUN mkdir -p /var/www/certbot/.well-known/acme-challenge     && mkdir -p /var/lib/certbot     && mkdir -p /etc/nginx/ssl     && touch /var/log/nginx/access.log /var/log/nginx/error.log

COPY nginx/ssl /etc/nginx/ssl

COPY fixperms-and-reload.sh /usr/local/bin/fixperms-and-reload.sh
RUN chmod +x /usr/local/bin/fixperms-and-reload.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443
CMD ["/entrypoint.sh"]
