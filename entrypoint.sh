#!/usr/bin/env bash
set -euo pipefail

mkdir -p /var/www/certbot/.well-known/acme-challenge
chmod -R 755 /var/www/certbot || true
mkdir -p /var/lib/certbot

if [ ! -f /etc/nginx/domains.json ]; then
  echo "{}" > /etc/nginx/domains.json
fi
addgroup -S nginx 2>/dev/null || true
chgrp nginx /etc/nginx/domains.json || true
chmod 664 /etc/nginx/domains.json || true

# Ensure dummy cert exists for dynamic domains
mkdir -p /etc/nginx/ssl
if [ ! -s /etc/nginx/ssl/dummy.key ] || [ ! -s /etc/nginx/ssl/dummy.crt ]; then
  openssl req -x509 -newkey rsa:2048     -keyout /etc/nginx/ssl/dummy.key -out /etc/nginx/ssl/dummy.crt     -days 3650 -nodes -subj "/CN=localhost"
fi

# Ensure static subdomain certs exist (isipage)
if [ ! -s /etc/nginx/ssl/isipage.crt ] || [ ! -s /etc/nginx/ssl/isipage.key ]; then
  echo "⚠️  /etc/nginx/ssl/isipage.crt or .key missing or empty. Place your real certs."
fi

openresty -g 'daemon off;'
