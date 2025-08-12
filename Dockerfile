FROM openresty/openresty:alpine

# tools
RUN apk add --no-cache \
    bash certbot curl openssl busybox-suid lua-filesystem \
    python3 py3-pip perl

# Copy config ke path default OpenResty
COPY nginx/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx/mime.types /etc/nginx/mime.types
COPY nginx/lua /etc/nginx/lua
COPY domains.json /etc/nginx/domains.json
COPY nginx/ssl /etc/nginx/ssl

# user+group nginx (aman kalau sudah ada)
RUN addgroup -S nginx 2>/dev/null || true \
 && adduser -S -G nginx nginx 2>/dev/null || true

# Siapkan dirs
RUN mkdir -p /var/www/certbot/.well-known/acme-challenge \
 && mkdir -p /var/lib/certbot \
 && mkdir -p /var/log/nginx \
 && chmod -R 755 /var/www/certbot \
 && chmod -R 755 /var/log/nginx

# (opsional DEV) longgarkan hak supaya certbot gampang nulis
# RUN chmod -R 777 /var/lib/certbot /var/www/certbot

# tools helper
COPY fixperms-and-reload.sh /usr/local/bin/fixperms-and-reload.sh
RUN chmod +x /usr/local/bin/fixperms-and-reload.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN chmod -R 777 /var/lib/certbot/tmp

EXPOSE 80 443
CMD ["/entrypoint.sh"]
