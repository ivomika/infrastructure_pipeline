#!/bin/sh

set -eu

: "${JENKINS_ADMIN_ID:?JENKINS_ADMIN_ID is required}"
: "${JENKINS_ADMIN_PASSWORD_FILE:?JENKINS_ADMIN_PASSWORD_FILE is required}"

if [ ! -s "$JENKINS_ADMIN_PASSWORD_FILE" ]; then
  echo "validate-admin: Jenkins admin password secret is missing or empty" >&2
  exit 1
fi

IFS= read -r admin_password <"$JENKINS_ADMIN_PASSWORD_FILE" || true
if [ -z "$admin_password" ]; then
  echo "validate-admin: Jenkins admin password must not be empty" >&2
  exit 1
fi
if [ "$JENKINS_ADMIN_ID" = "admin" ] && [ "$admin_password" = "admin" ]; then
  echo "validate-admin: admin/admin credentials are forbidden" >&2
  exit 1
fi
unset admin_password

exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
