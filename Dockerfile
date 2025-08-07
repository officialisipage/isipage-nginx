FROM openresty/openresty:alpine

RUN apk add --no-cache openssl \
 && opm get knyar/lua-resty-auto-ssl

WORKDIR /etc/nginx
