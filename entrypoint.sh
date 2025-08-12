#!/usr/bin/env bash
set -euo pipefail

# Directories
mkdir -p /var/www/certbot/.well-known/acme-challenge
chmod -R 755 /var/www/certbot || true
mkdir -p /var/lib/certbot
mkdir -p /var/log/nginx
# touch /var/log/nginx/access.log /var/log/nginx/error.log

# # domains.json
# [ -f /etc/nginx/domains.json ] || echo '{}' > /etc/nginx/domains.json
# addgroup -S nginx 2>/dev/null || true
# chgrp nginx /etc/nginx/domains.json || true
# chmod 664 /etc/nginx/domains.json || true

# Dummy cert fallback
mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/dummy.key ] || [ ! -f /etc/nginx/ssl/dummy.crt ]; then
  openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/ssl/dummy.key -out /etc/nginx/ssl/dummy.crt \
    -days 3650 -nodes -subj "/CN=localhost"
fi

# Pastikan static cert *.isipage.com ada (kalau belum, akan warning di log)
ls -l /etc/nginx/ssl || true

# Jalanin nginx
openresty -g 'daemon off;'
