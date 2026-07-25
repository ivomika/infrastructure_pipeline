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

admin_id="$(resolved_env JENKINS_ADMIN_ID)"
admin_password="$(resolved_env JENKINS_ADMIN_PASSWORD)"
library_name="$(resolved_env SHARED_LIBRARY_NAME)"
library_url="$(resolved_env SHARED_LIBRARY_REPOSITORY_URL)"
library_branch="$(resolved_env SHARED_LIBRARY_DEFAULT_BRANCH)"
library_credentials="$(resolved_env SHARED_LIBRARY_CREDENTIALS_ID)"

[[ -n "$admin_id" ]] || fail "JENKINS_ADMIN_ID must not be empty"
[[ "${#admin_password}" -ge 12 ]] ||
  fail "JENKINS_ADMIN_PASSWORD must contain at least 12 characters"
[[ "$admin_id/$admin_password" != "admin/admin" ]] ||
  fail "admin/admin credentials are forbidden"
[[ -n "$library_name" ]] || fail "SHARED_LIBRARY_NAME must not be empty"
[[ -n "$library_url" && "$library_url" != *"your-org"* ]] ||
  fail "set SHARED_LIBRARY_REPOSITORY_URL in .env"
[[ -n "$library_branch" ]] || fail "SHARED_LIBRARY_DEFAULT_BRANCH must not be empty"
[[ -n "$library_credentials" ]] || fail "SHARED_LIBRARY_CREDENTIALS_ID must not be empty"
unset admin_password

"${project_dir}/scripts/preflight-secrets.sh"
"${project_dir}/scripts/verify-locks.sh" --offline

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

"${project_dir}/scripts/smoke-test.sh"

echo "bootstrap: Jenkins is ready at http://${readiness_host}:${host_port}/"
