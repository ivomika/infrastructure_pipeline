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

exec certbot "$@"
