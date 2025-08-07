FROM openresty/openresty:alpine

# Tambahkan perl agar opm bisa berjalan
RUN apk add --no-cache openssl perl \
  && opm get knyar/lua-resty-auto-ssl

WORKDIR /etc/nginx
