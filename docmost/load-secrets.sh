#!/bin/sh

set -eu

load_secret() {
  target_name="$1"
  secret_file="$2"

  if [ ! -s "$secret_file" ]; then
    echo "docmost-entrypoint: secret for ${target_name} is missing or empty" >&2
    exit 1
  fi
  IFS= read -r secret_value <"$secret_file" || true
  if [ -z "$secret_value" ]; then
    echo "docmost-entrypoint: secret for ${target_name} must not be empty" >&2
    exit 1
  fi
  export "${target_name}=${secret_value}"
  unset secret_value
}

[ -z "${APP_SECRET_FILE:-}" ] ||
  load_secret APP_SECRET "$APP_SECRET_FILE"
[ -z "${DOCMOST_DB_PASSWORD_FILE:-}" ] ||
  load_secret DOCMOST_DB_PASSWORD "$DOCMOST_DB_PASSWORD_FILE"
[ -z "${DOCMOST_REDIS_PASSWORD_FILE:-}" ] ||
  load_secret DOCMOST_REDIS_PASSWORD "$DOCMOST_REDIS_PASSWORD_FILE"

if [ -n "${DOCMOST_DB_PASSWORD:-}" ]; then
  case "$DOCMOST_DB_PASSWORD" in
    *[!A-Za-z0-9._~-]*)
      echo "docmost-entrypoint: database password must be URL-safe" >&2
      exit 1
      ;;
  esac
  export DATABASE_URL="postgresql://${DOCMOST_DB_USER}:${DOCMOST_DB_PASSWORD}@${DOCMOST_DB_HOST}:${DOCMOST_DB_PORT}/${DOCMOST_DB_NAME}"
fi

if [ -n "${DOCMOST_REDIS_PASSWORD:-}" ]; then
  case "$DOCMOST_REDIS_PASSWORD" in
    *[!A-Za-z0-9._~-]*)
      echo "docmost-entrypoint: Redis password must be URL-safe" >&2
      exit 1
      ;;
  esac
  export REDISCLI_AUTH="$DOCMOST_REDIS_PASSWORD"
  if [ -n "${DOCMOST_REDIS_HOST:-}" ]; then
    export REDIS_URL="redis://:${DOCMOST_REDIS_PASSWORD}@${DOCMOST_REDIS_HOST}:${DOCMOST_REDIS_PORT}"
  fi
fi

[ -z "${DOCMOST_MAIL_DRIVER:-}" ] ||
  export MAIL_DRIVER="$DOCMOST_MAIL_DRIVER"
[ -z "${DOCMOST_SMTP_HOST:-}" ] ||
  export SMTP_HOST="$DOCMOST_SMTP_HOST"
[ -z "${DOCMOST_SMTP_PORT:-}" ] ||
  export SMTP_PORT="$DOCMOST_SMTP_PORT"
[ -z "${DOCMOST_SMTP_USERNAME:-}" ] ||
  export SMTP_USERNAME="$DOCMOST_SMTP_USERNAME"
[ -z "${DOCMOST_SMTP_PASSWORD:-}" ] ||
  export SMTP_PASSWORD="$DOCMOST_SMTP_PASSWORD"
[ -z "${DOCMOST_SMTP_SECURE:-}" ] ||
  export SMTP_SECURE="$DOCMOST_SMTP_SECURE"
[ -z "${DOCMOST_MAIL_FROM_ADDRESS:-}" ] ||
  export MAIL_FROM_ADDRESS="$DOCMOST_MAIL_FROM_ADDRESS"
[ -z "${DOCMOST_MAIL_FROM_NAME:-}" ] ||
  export MAIL_FROM_NAME="$DOCMOST_MAIL_FROM_NAME"

unset \
  APP_SECRET_FILE \
  DOCMOST_DB_PASSWORD_FILE \
  DOCMOST_REDIS_PASSWORD_FILE

exec "$@"
