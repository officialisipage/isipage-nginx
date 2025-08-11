#!/usr/bin/env bash
set -euo pipefail

addgroup -S nginx 2>/dev/null || true

mkdir -p /var/www/certbot/.well-known/acme-challenge
chmod -R 755 /var/www/certbot || true

mkdir -p /var/lib/certbot

touch /etc/nginx/domains.json
chgrp nginx /etc/nginx/domains.json || true
chmod 664 /etc/nginx/domains.json || true

if [ ! -s /etc/nginx/ssl/dummy.key ] || [ ! -s /etc/nginx/ssl/dummy.crt ]; then
  echo "Generating dummy cert..."
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650     -keyout /etc/nginx/ssl/dummy.key     -out /etc/nginx/ssl/dummy.crt     -subj "/CN=localhost"
fi

if [ ! -s /etc/nginx/ssl/isipage.crt ] || [ ! -s /etc/nginx/ssl/isipage.key ]; then
  echo "WARN: /etc/nginx/ssl/isipage.crt/key missing for *.isipage.com"
fi

cat >/etc/crontabs/root <<'CRON'
0 0,12 * * * certbot renew --config-dir /var/lib/certbot --work-dir /tmp --logs-dir /tmp --no-permissions-check --deploy-hook "/usr/local/bin/fixperms-and-reload.sh"
CRON
crond

exec openresty -g 'daemon off;'
