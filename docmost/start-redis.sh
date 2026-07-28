#!/bin/sh

set -eu

: "${DOCMOST_REDIS_PASSWORD:?DOCMOST_REDIS_PASSWORD is required}"

exec docker-entrypoint.sh \
  redis-server \
  --appendonly yes \
  --maxmemory-policy noeviction \
  --requirepass "$DOCMOST_REDIS_PASSWORD"
