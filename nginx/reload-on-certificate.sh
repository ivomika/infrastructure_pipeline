#!/bin/sh

(
  while sleep 60; do
    if [ -f /var/www/certbot/.reload-nginx ]; then
      nginx -s reload && rm -f /var/www/certbot/.reload-nginx
    fi
  done
) &
