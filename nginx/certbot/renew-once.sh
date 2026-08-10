#!/bin/sh
set -u

. /opt/certbot/metrics.sh

if certbot renew \
    --webroot \
    --webroot-path /var/www/certbot \
    --quiet \
    --deploy-hook "touch /var/www/certbot/.reload-nginx"
then
  write_certbot_metrics 1
else
  status=$?
  write_certbot_metrics 0 || true
  exit "$status"
fi
