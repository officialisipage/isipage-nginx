#!/usr/bin/env bash
set -euo pipefail
if getent group nginx >/dev/null; then NGROUP=nginx; else NGROUP=root; fi
LIVE=/var/lib/certbot/live
if [ -d "$LIVE" ]; then
  find "$LIVE" -type f -name "privkey.pem" -exec chgrp "$NGROUP" {} + -exec chmod 640 {} +
  find "$LIVE" -type f -name "fullchain.pem" -exec chgrp "$NGROUP" {} + -exec chmod 644 {} +
fi
nginx -s reload || true
