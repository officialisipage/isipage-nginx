FROM openresty/openresty:alpine

RUN apk add --no-cache git curl unzip openssl perl

# Clone dan copy hanya file Lua yang dibutuhkan
RUN mkdir -p /opt/lua-resty-auto-ssl && \
    git clone https://github.com/auto-ssl/lua-resty-auto-ssl /opt/lua-resty-auto-ssl && \
    mkdir -p /usr/local/openresty/lualib/resty/auto-ssl && \
    cp -r /opt/lua-resty-auto-ssl/lib/resty/auto-ssl/* /usr/local/openresty/lualib/resty/auto-ssl/

# Dummy cert untuk fallback SSL
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/dummy.key -out /etc/nginx/dummy.crt -days 3650 -nodes -subj "/CN=localhost"

WORKDIR /etc/nginx

# 🟢 Ini bagian penting agar Nginx (OpenResty) benar-benar dijalankan

# ✅ Inilah bagian yang sebelumnya hilang:
ENV OPENRESTY_CONF=/etc/nginx/nginx.conf
CMD ["/usr/local/openresty/bin/openresty", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]

