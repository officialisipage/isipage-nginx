FROM openresty/openresty:alpine

RUN apk add --no-cache bash certbot curl openssl busybox-suid lua-filesystem python3 py3-pip certbot perl

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/mime.types /etc/nginx/mime.types
COPY nginx/lua /etc/nginx/lua
COPY domains.json /etc/nginx/domains.json

# Buat user+group nginx (aman kalau sudah ada)
RUN addgroup -S nginx 2>/dev/null || true \
    && adduser -S -G nginx nginx 2>/dev/null || true

# Siapkan webroot, certbot, ssl, dan logs
RUN mkdir -p /var/lib/certbot \
    && mkdir -p /var/www/certbot/.well-known/acme-challenge /var/lib/certbot /var/log/nginx \
    && chown 777 /var/www/certbot /var/lib/certbot /var/log/nginx
    && mkdir -p /etc/nginx/ssl \
    && mkdir -p /var/log/nginx \
    # && touch /var/log/nginx/access.log /var/log/nginx/error.log \
    
COPY nginx/ssl /etc/nginx/ssl

COPY fixperms-and-reload.sh /usr/local/bin/fixperms-and-reload.sh
RUN chmod +x /usr/local/bin/fixperms-and-reload.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443
CMD ["/entrypoint.sh"]
