FROM openresty/openresty:alpine

RUN apk add --no-cache bash openssl certbot

COPY nginx/mime.types /etc/nginx/mime.types
COPY nginx/ssl /etc/nginx/ssl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
