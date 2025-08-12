#!/usr/bin/env bash
set -euo pipefail

# Setup awal (sama seperti sebelumnya)
mkdir -p /var/www/certbot/.well-known/acme-challenge
chmod -R 755 /var/www/certbot || true
mkdir -p /var/lib/certbot
mkdir -p /var/log/nginx

# Dummy cert fallback
mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/dummy.key ] || [ ! -f /etc/nginx/ssl/dummy.crt ]; then
  openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/ssl/dummy.key -out /etc/nginx/ssl/dummy.crt \
    -days 3650 -nodes -subj "/CN=localhost"
fi

# Jalankan Flask di background
python3 /app/app.py &

# Jalankan OpenResty (Nginx)
openresty -g 'daemon off;'
