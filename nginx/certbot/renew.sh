#!/bin/sh
set -u

while true; do
  /bin/sh /opt/certbot/renew-once.sh || true
  sleep "$CERTBOT_RENEW_INTERVAL"
done
