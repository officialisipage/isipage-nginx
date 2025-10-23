#!/usr/bin/env bash
set -euo pipefail

# Setup awal
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

# Siapkan domains.json (array) & pools.json (object) jika belum ada
if [ ! -f /etc/nginx/domains.json ]; then
  cat >/etc/nginx/domains.json <<'JSON'
[]
JSON
fi

if [ ! -f /etc/nginx/pools.json ]; then
  cat >/etc/nginx/pools.json <<'JSON'
{
  "pool_public": [ { "host": "103.125.181.241", "port": 2000 } ],
  "pool_api":    [ { "host": "103.125.181.241", "port": 4000 } ],
  "pool_fe":     [ { "host": "103.125.181.241", "port": 5173 } ]
}
JSON
fi

# Jalankan Flask di background
python3 /app/app.py &

# Jalankan OpenResty (Nginx)
openresty -g 'daemon off;'
