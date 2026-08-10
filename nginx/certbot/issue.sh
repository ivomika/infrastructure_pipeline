#!/bin/sh
set -eu

set -- certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --non-interactive \
  --agree-tos \
  --expand \
  --email "$CERTBOT_EMAIL" \
  --cert-name "$TLS_CERT_NAME"

for domain in \
  "$JENKINS_HOST" \
  "$PLANE_HOST" \
  "$DOCMOST_HOST" \
  "$NEXUS_HOST" \
  "$NEXUS_DOCKER_HOST" \
  "$GRAFANA_HOST"
do
  set -- "$@" --domain "$domain"
done

. /opt/certbot/metrics.sh

if certbot "$@"; then
  write_certbot_metrics 1 || true
else
  status=$?
  write_certbot_metrics 0 || true
  exit "$status"
fi
