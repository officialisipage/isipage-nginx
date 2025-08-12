#!/usr/bin/env bash
set -euo pipefail

# Pastikan group nginx ada
if ! getent group nginx >/dev/null; then
  addgroup -S nginx || true    # Alpine
  # groupadd -r nginx || true  # Debian/Ubuntu (pakai yg sesuai image kamu)
fi

NGROUP=nginx
BASE=/var/lib/certbot
LIVE="$BASE/live"
ARCHIVE="$BASE/archive"

# Ikuti symlink di LIVE
if [ -d "$LIVE" ]; then
  find -L "$LIVE" -type f -name 'fullchain*.pem' -exec chgrp "$NGROUP" {} + -exec chmod 644 {} +
  find -L "$LIVE" -type f -name 'privkey*.pem'   -exec chgrp "$NGROUP" {} + -exec chmod 640 {} +
fi

# Pastikan file asli di ARCHIVE juga benar
if [ -d "$ARCHIVE" ]; then
  find "$ARCHIVE" -type f -name 'fullchain*.pem' -exec chgrp "$NGROUP" {} + -exec chmod 644 {} +
  find "$ARCHIVE" -type f -name 'privkey*.pem'   -exec chgrp "$NGROUP" {} + -exec chmod 640 {} +
fi

# Reload nginx
nginx -t && nginx -s reload || true
