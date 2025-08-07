# Gunakan base image OpenResty
FROM openresty/openresty:alpine

# Install dependensi
RUN apk add --no-cache \
    curl \
    git \
    socat \
    openssl \
    bash \
    jq

# Install lua-resty-auto-ssl
RUN mkdir -p /opt/lua-resty-auto-ssl && \
    git clone https://github.com/auto-ssl/lua-resty-auto-ssl /opt/lua-resty-auto-ssl && \
    mkdir -p /usr/local/openresty/lualib/resty/auto-ssl && \
    cp -r /opt/lua-resty-auto-ssl/lib/resty/auto-ssl/* /usr/local/openresty/lualib/resty/auto-ssl/ && \
    chmod -R 755 /usr/local/openresty/lualib/resty/auto-ssl

# Buat direktori untuk cert dummy & auto-ssl cache
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/dummy.key \
      -out /etc/nginx/ssl/dummy.crt \
      -days 3650 \
      -subj "/CN=localhost"

# Siapkan direktori auto-ssl
RUN mkdir -p /etc/resty-auto-ssl && \
    chmod 700 /etc/resty-auto-ssl

ENV AUTO_SSL_DIR=/etc/resty-auto-ssl

# Salin seluruh konfigurasi lokal ke image
COPY nginx /etc/nginx

# Expose HTTP dan HTTPS
EXPOSE 80 443

# Jalankan Nginx
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
