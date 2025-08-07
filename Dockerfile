FROM openresty/openresty:alpine

# Install dependensi
RUN apk add --no-cache curl git openssl socat nano perl

# Install lua-resty-auto-ssl
RUN mkdir -p /opt/lua-resty-auto-ssl && \
    git clone https://github.com/auto-ssl/lua-resty-auto-ssl /opt/lua-resty-auto-ssl && \
    mkdir -p /usr/local/openresty/lualib/resty/auto-ssl && \
    cp -r /opt/lua-resty-auto-ssl/lib/resty/auto-ssl/* /usr/local/openresty/lualib/resty/auto-ssl/

# Siapkan direktori cert dummy agar Nginx tidak error saat startup
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/ssl/dummy.key -out /etc/nginx/ssl/dummy.crt -days 3650 -nodes -subj "/CN=localhost"

# Buat folder untuk auto-ssl certs
RUN mkdir -p /etc/resty-auto-ssl && chmod 700 /etc/resty-auto-ssl

ENV AUTO_SSL_DIR /etc/resty-auto-ssl
