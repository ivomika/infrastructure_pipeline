#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${project_dir}/.env"
check_only=false

if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi
[[ "$#" -eq 0 ]] || {
  echo "Usage: $0 [--check]" >&2
  exit 2
}

fail() {
  echo "bootstrap: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null || fail "required command is unavailable: $1"
}

read_env() {
  local name="$1"
  awk -v name="$name" '
    index($0, name "=") == 1 {
      print substr($0, length(name) + 2)
      exit
    }
  ' "$env_file"
}

resolved_env() {
  local name="$1"
  local shell_value
  shell_value="${!name:-}"
  if [[ -n "$shell_value" ]]; then
    printf '%s' "$shell_value"
  else
    read_env "$name"
  fi
}

version_at_least() {
  awk -v have="$1" -v need="$2" '
    BEGIN {
      split(have, current, ".")
      split(need, minimum, ".")
      for (i = 1; i <= 3; i++) {
        current[i] += 0
        minimum[i] += 0
        if (current[i] > minimum[i]) exit 0
        if (current[i] < minimum[i]) exit 1
      }
      exit 0
    }
  '
}

require_command curl
require_command docker
require_command git
require_command openssl
require_command python3

docker info >/dev/null 2>&1 || fail "Docker daemon is unavailable"
docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin is unavailable"
docker buildx version >/dev/null 2>&1 || fail "Docker Buildx is unavailable"

compose_version="$(docker compose version --short | sed 's/^v//')"
version_at_least "$compose_version" "2.24.0" ||
  fail "Docker Compose 2.24.0+ is required (found $compose_version)"

if [[ ! -f "$env_file" ]]; then
  install -m 600 "${project_dir}/.env.example" "$env_file"
  generated_password="$(openssl rand -hex 24)"
  temporary_env="$(mktemp "${env_file}.XXXXXX")"
  awk -v password="$generated_password" '
    /^JENKINS_ADMIN_PASSWORD=/ {
      print "JENKINS_ADMIN_PASSWORD=" password
      next
    }
    { print }
  ' "$env_file" >"$temporary_env"
  chmod 600 "$temporary_env"
  mv "$temporary_env" "$env_file"
  echo "bootstrap: created .env with a generated Jenkins admin password"
fi

ensure_generated_secret() {
  local name="$1"
  local description="$2"
  local generated_value temporary_env

  [[ -z "$(resolved_env "$name")" ]] || return 0

  generated_value="$(openssl rand -hex 32)"
  temporary_env="$(mktemp "${env_file}.XXXXXX")"
  awk -v name="$name" -v value="$generated_value" '
    index($0, name "=") == 1 {
      print name "=" value
      found=1
      next
    }
    { print }
    END {
      if (!found) print name "=" value
    }
  ' "$env_file" >"$temporary_env"
  chmod 600 "$temporary_env"
  mv "$temporary_env" "$env_file"
  unset generated_value
  echo "bootstrap: generated ${description} in .env"
}

ensure_generated_secret DOCMOST_DB_PASSWORD "a Docmost database password"
ensure_generated_secret DOCMOST_APP_SECRET "a Docmost application secret"
ensure_generated_secret DOCMOST_REDIS_PASSWORD "a Docmost Redis password"
ensure_generated_secret DOCMOST_OWNER_PASSWORD "a Docmost owner password"
ensure_generated_secret PLANE_DB_PASSWORD "a Plane database password"
ensure_generated_secret PLANE_REDIS_PASSWORD "a Plane Valkey password"
ensure_generated_secret PLANE_RABBITMQ_PASSWORD "a Plane RabbitMQ password"
ensure_generated_secret PLANE_MINIO_ROOT_PASSWORD "a Plane MinIO password"
ensure_generated_secret PLANE_SECRET_KEY "a Plane application signing key"
ensure_generated_secret PLANE_LIVE_SERVER_SECRET_KEY "a Plane live-server signing key"

admin_id="$(resolved_env JENKINS_ADMIN_ID)"
admin_password="$(resolved_env JENKINS_ADMIN_PASSWORD)"
docmost_db_password="$(resolved_env DOCMOST_DB_PASSWORD)"
docmost_app_secret="$(resolved_env DOCMOST_APP_SECRET)"
docmost_redis_password="$(resolved_env DOCMOST_REDIS_PASSWORD)"
docmost_owner_name="$(resolved_env DOCMOST_OWNER_NAME)"
docmost_owner_email="$(resolved_env DOCMOST_OWNER_EMAIL)"
docmost_owner_password="$(resolved_env DOCMOST_OWNER_PASSWORD)"
docmost_workspace_name="$(resolved_env DOCMOST_WORKSPACE_NAME)"
docmost_auto_setup="$(resolved_env DOCMOST_AUTO_SETUP)"
plane_db_password="$(resolved_env PLANE_DB_PASSWORD)"
plane_redis_password="$(resolved_env PLANE_REDIS_PASSWORD)"
plane_rabbitmq_password="$(resolved_env PLANE_RABBITMQ_PASSWORD)"
plane_minio_root_user="$(resolved_env PLANE_MINIO_ROOT_USER)"
plane_minio_root_user="${plane_minio_root_user:-plane}"
plane_minio_root_password="$(resolved_env PLANE_MINIO_ROOT_PASSWORD)"
plane_secret_key="$(resolved_env PLANE_SECRET_KEY)"
plane_live_secret_key="$(resolved_env PLANE_LIVE_SERVER_SECRET_KEY)"
library_name="$(resolved_env SHARED_LIBRARY_NAME)"
library_url="$(resolved_env SHARED_LIBRARY_REPOSITORY_URL)"
library_branch="$(resolved_env SHARED_LIBRARY_DEFAULT_BRANCH)"
library_credentials="$(resolved_env SHARED_LIBRARY_CREDENTIALS_ID)"

[[ -n "$admin_id" ]] || fail "JENKINS_ADMIN_ID must not be empty"
[[ "${#admin_password}" -ge 8 ]] ||
  fail "JENKINS_ADMIN_PASSWORD must contain at least 8 characters"
[[ "$admin_id/$admin_password" != "admin/admin" ]] ||
  fail "admin/admin credentials are forbidden"
[[ "${#docmost_db_password}" -ge 8 && "$docmost_db_password" =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "DOCMOST_DB_PASSWORD must contain at least 8 URL-safe characters"
[[ "${#docmost_app_secret}" -ge 32 ]] ||
  fail "DOCMOST_APP_SECRET must contain at least 32 characters"
[[ "${#docmost_redis_password}" -ge 8 && "$docmost_redis_password" =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "DOCMOST_REDIS_PASSWORD must contain at least 8 URL-safe characters"
[[ -n "$docmost_owner_name" && "${#docmost_owner_name}" -le 50 ]] ||
  fail "DOCMOST_OWNER_NAME must contain between 1 and 50 characters"
[[ -n "$docmost_owner_email" && "$docmost_owner_email" == *@*.* ]] ||
  fail "DOCMOST_OWNER_EMAIL must be a valid email address"
[[ "${#docmost_owner_password}" -ge 8 && "${#docmost_owner_password}" -le 70 ]] ||
  fail "DOCMOST_OWNER_PASSWORD must contain between 8 and 70 characters"
[[ -n "$docmost_workspace_name" && "${#docmost_workspace_name}" -le 50 ]] ||
  fail "DOCMOST_WORKSPACE_NAME must contain between 1 and 50 characters"
case "$docmost_auto_setup" in
  true | false) ;;
  *) fail "DOCMOST_AUTO_SETUP must be true or false" ;;
esac
[[ "${#plane_db_password}" -ge 8 && "$plane_db_password" =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "PLANE_DB_PASSWORD must contain at least 8 URL-safe characters"
[[ "${#plane_redis_password}" -ge 8 && "$plane_redis_password" =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "PLANE_REDIS_PASSWORD must contain at least 8 URL-safe characters"
[[ "${#plane_rabbitmq_password}" -ge 8 && "$plane_rabbitmq_password" =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "PLANE_RABBITMQ_PASSWORD must contain at least 8 URL-safe characters"
[[ -n "$plane_minio_root_user" ]] ||
  fail "PLANE_MINIO_ROOT_USER must not be empty"
[[ "${#plane_minio_root_password}" -ge 8 && "$plane_minio_root_password" =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "PLANE_MINIO_ROOT_PASSWORD must contain at least 8 URL-safe characters"
[[ "${#plane_secret_key}" -ge 32 ]] ||
  fail "PLANE_SECRET_KEY must contain at least 32 characters"
[[ "${#plane_live_secret_key}" -ge 32 ]] ||
  fail "PLANE_LIVE_SERVER_SECRET_KEY must contain at least 32 characters"
[[ -n "$library_name" ]] || fail "SHARED_LIBRARY_NAME must not be empty"
[[ -n "$library_url" && "$library_url" != *"your-org"* ]] ||
  fail "set SHARED_LIBRARY_REPOSITORY_URL in .env"
[[ -n "$library_branch" ]] || fail "SHARED_LIBRARY_DEFAULT_BRANCH must not be empty"
[[ -n "$library_credentials" ]] || fail "SHARED_LIBRARY_CREDENTIALS_ID must not be empty"
unset \
  admin_password \
  docmost_db_password \
  docmost_app_secret \
  docmost_redis_password \
  docmost_owner_password \
  plane_db_password \
  plane_redis_password \
  plane_rabbitmq_password \
  plane_minio_root_password \
  plane_secret_key \
  plane_live_secret_key

"${project_dir}/scripts/preflight-secrets.sh"
"${project_dir}/scripts/verify-locks.sh" --offline
"${project_dir}/scripts/check-disk-space.sh"

source_date_epoch="$(git -C "$project_dir" log -1 --format=%ct)"
[[ "$source_date_epoch" =~ ^[0-9]+$ && "$source_date_epoch" -gt 0 ]] ||
  fail "cannot determine the current commit timestamp"
export SOURCE_DATE_EPOCH="$source_date_epoch"

cd "$project_dir"
if $check_only; then
  "${project_dir}/scripts/migrate-compose-project.sh" --check
else
  "${project_dir}/scripts/migrate-compose-project.sh"
fi
docker compose --profile agent-image config --quiet

jenkins_container="$(docker compose ps -q jenkins)"
if [[ -z "$jenkins_container" ]]; then
  host_address="$(resolved_env JENKINS_HOST_ADDRESS)"
  host_port="$(resolved_env JENKINS_HTTP_PORT)"
  host_address="${host_address:-127.0.0.1}"
  host_port="${host_port:-8080}"
  [[ "$host_port" =~ ^[0-9]+$ && "$host_port" -ge 1 && "$host_port" -le 65535 ]] ||
    fail "JENKINS_HTTP_PORT must be between 1 and 65535"
  python3 - "$host_address" "$host_port" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
family = socket.AF_INET6 if ":" in host else socket.AF_INET
sock = socket.socket(family, socket.SOCK_STREAM)
try:
    sock.bind((host, port))
except OSError as error:
    raise SystemExit(f"bootstrap: Jenkins host port is unavailable: {host}:{port}: {error}")
finally:
    sock.close()
PY
fi

docmost_container="$(docker compose ps -q docmost)"
if [[ -z "$docmost_container" ]]; then
  docmost_host_address="$(resolved_env DOCMOST_HOST_ADDRESS)"
  docmost_host_port="$(resolved_env DOCMOST_HTTP_PORT)"
  docmost_host_address="${docmost_host_address:-127.0.0.1}"
  docmost_host_port="${docmost_host_port:-3000}"
  [[ "$docmost_host_port" =~ ^[0-9]+$ && "$docmost_host_port" -ge 1 && "$docmost_host_port" -le 65535 ]] ||
    fail "DOCMOST_HTTP_PORT must be between 1 and 65535"
  python3 - "$docmost_host_address" "$docmost_host_port" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
family = socket.AF_INET6 if ":" in host else socket.AF_INET
sock = socket.socket(family, socket.SOCK_STREAM)
try:
    sock.bind((host, port))
except OSError as error:
    raise SystemExit(f"bootstrap: Docmost host port is unavailable: {host}:{port}: {error}")
finally:
    sock.close()
PY
fi

plane_container="$(docker compose ps -q plane-proxy)"
if [[ -z "$plane_container" ]]; then
  plane_host_address="$(resolved_env PLANE_HOST_ADDRESS)"
  plane_host_port="$(resolved_env PLANE_HTTP_PORT)"
  plane_host_address="${plane_host_address:-127.0.0.1}"
  plane_host_port="${plane_host_port:-9010}"
  [[ "$plane_host_port" =~ ^[0-9]+$ && "$plane_host_port" -ge 1 && "$plane_host_port" -le 65535 ]] ||
    fail "PLANE_HTTP_PORT must be between 1 and 65535"
  python3 - "$plane_host_address" "$plane_host_port" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
family = socket.AF_INET6 if ":" in host else socket.AF_INET
sock = socket.socket(family, socket.SOCK_STREAM)
try:
    sock.bind((host, port))
except OSError as error:
    raise SystemExit(f"bootstrap: Plane host port is unavailable: {host}:{port}: {error}")
finally:
    sock.close()
PY
fi

if $check_only; then
  echo "bootstrap: all preflight checks passed"
  exit 0
fi

"${project_dir}/scripts/verify-locks.sh"
"${project_dir}/scripts/build-images.sh"
"${project_dir}/scripts/start.sh"

host_address="$(resolved_env JENKINS_HOST_ADDRESS)"
host_port="$(resolved_env JENKINS_HTTP_PORT)"
host_address="${host_address:-127.0.0.1}"
host_port="${host_port:-8080}"
case "$host_address" in
  0.0.0.0) readiness_host="127.0.0.1" ;;
  ::) readiness_host="[::1]" ;;
  *:*) readiness_host="[${host_address}]" ;;
  *) readiness_host="$host_address" ;;
esac
readiness_url="http://${readiness_host}:${host_port}/login"
timeout="${BOOTSTRAP_TIMEOUT_SECONDS:-600}"
deadline=$((SECONDS + timeout))

until curl --fail --silent --show-error --output /dev/null "$readiness_url"; do
  if (( SECONDS >= deadline )); then
    docker compose logs --tail 100 jenkins >&2 || true
    fail "Jenkins did not become ready within ${timeout}s"
  fi
  sleep 5
done

docmost_host_address="$(resolved_env DOCMOST_HOST_ADDRESS)"
docmost_host_port="$(resolved_env DOCMOST_HTTP_PORT)"
docmost_host_address="${docmost_host_address:-127.0.0.1}"
docmost_host_port="${docmost_host_port:-3000}"
case "$docmost_host_address" in
  0.0.0.0) docmost_readiness_host="127.0.0.1" ;;
  ::) docmost_readiness_host="[::1]" ;;
  *:*) docmost_readiness_host="[${docmost_host_address}]" ;;
  *) docmost_readiness_host="$docmost_host_address" ;;
esac
docmost_readiness_url="http://${docmost_readiness_host}:${docmost_host_port}/api/health"
docmost_timeout="$(resolved_env DOCMOST_BOOTSTRAP_TIMEOUT_SECONDS)"
docmost_timeout="${docmost_timeout:-600}"
[[ "$docmost_timeout" =~ ^[0-9]+$ && "$docmost_timeout" -gt 0 ]] ||
  fail "DOCMOST_BOOTSTRAP_TIMEOUT_SECONDS must be a positive integer"
docmost_deadline=$((SECONDS + docmost_timeout))

until curl --fail --silent --show-error --output /dev/null "$docmost_readiness_url"; do
  if (( SECONDS >= docmost_deadline )); then
    docker compose logs --tail 100 docmost-db docmost-redis docmost >&2 || true
    fail "Docmost did not become ready within ${docmost_timeout}s"
  fi
  sleep 5
done

if [[ "$docmost_auto_setup" == "true" ]]; then
  "${project_dir}/docmost/setup.sh"
fi

plane_host_address="$(resolved_env PLANE_HOST_ADDRESS)"
plane_host_port="$(resolved_env PLANE_HTTP_PORT)"
plane_host_address="${plane_host_address:-127.0.0.1}"
plane_host_port="${plane_host_port:-9010}"
case "$plane_host_address" in
  0.0.0.0) plane_readiness_host="127.0.0.1" ;;
  ::) plane_readiness_host="[::1]" ;;
  *:*) plane_readiness_host="[${plane_host_address}]" ;;
  *) plane_readiness_host="$plane_host_address" ;;
esac
plane_readiness_url="http://${plane_readiness_host}:${plane_host_port}/"
plane_timeout="$(resolved_env PLANE_BOOTSTRAP_TIMEOUT_SECONDS)"
plane_timeout="${plane_timeout:-900}"
[[ "$plane_timeout" =~ ^[0-9]+$ && "$plane_timeout" -gt 0 ]] ||
  fail "PLANE_BOOTSTRAP_TIMEOUT_SECONDS must be a positive integer"
plane_deadline=$((SECONDS + plane_timeout))

until curl --fail --silent --show-error --output /dev/null "$plane_readiness_url"; do
  if (( SECONDS >= plane_deadline )); then
    docker compose logs --tail 100 \
      plane-db \
      plane-redis \
      plane-mq \
      plane-minio \
      plane-migrator \
      plane-api \
      plane-proxy >&2 ||
      true
    fail "Plane did not become ready within ${plane_timeout}s"
  fi
  sleep 5
done

"${project_dir}/scripts/smoke-test.sh"

echo "bootstrap: Jenkins is ready at http://${readiness_host}:${host_port}/"
echo "bootstrap: Docmost is ready at http://${docmost_readiness_host}:${docmost_host_port}/"
echo "bootstrap: Plane is ready at http://${plane_readiness_host}:${plane_host_port}/"
