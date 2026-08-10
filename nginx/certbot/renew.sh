#!/bin/sh
set -u

while true; do
  certbot renew \
    --webroot \
    --webroot-path /var/www/certbot \
    --quiet \
    --deploy-hook "touch /var/www/certbot/.reload-nginx"

  sleep "$CERTBOT_RENEW_INTERVAL"
done
