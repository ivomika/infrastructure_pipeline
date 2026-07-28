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
  echo "docmost-setup: $*" >&2
  exit 1
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

for command in curl jq; do
  command -v "$command" >/dev/null ||
    fail "required command is unavailable: $command"
done
[[ -s "$env_file" ]] || fail ".env is missing or empty"

host_address="$(resolved_env DOCMOST_HOST_ADDRESS)"
host_port="$(resolved_env DOCMOST_HTTP_PORT)"
host_address="${host_address:-127.0.0.1}"
host_port="${host_port:-3000}"
case "$host_address" in
  0.0.0.0) request_host="127.0.0.1" ;;
  ::) request_host="[::1]" ;;
  *:*) request_host="[${host_address}]" ;;
  *) request_host="$host_address" ;;
esac
base_url="http://${request_host}:${host_port}"

curl --fail --silent --show-error "${base_url}/api/health" >/dev/null ||
  fail "Docmost is not healthy at ${base_url}"
if $check_only; then
  echo "docmost-setup: Docmost is healthy at ${base_url}"
  exit 0
fi

owner_name="$(resolved_env DOCMOST_OWNER_NAME)"
owner_email="$(resolved_env DOCMOST_OWNER_EMAIL)"
owner_password="$(resolved_env DOCMOST_OWNER_PASSWORD)"
workspace_name="$(resolved_env DOCMOST_WORKSPACE_NAME)"
[[ -n "$owner_name" && -n "$owner_email" && -n "$owner_password" && -n "$workspace_name" ]] ||
  fail "owner and workspace settings are incomplete"

response_file="$(mktemp)"
cleanup() {
  rm -f -- "$response_file"
  unset owner_password
}
trap cleanup EXIT

request_body="$(
  jq -n \
    --arg name "$owner_name" \
    --arg email "$owner_email" \
    --arg password "$owner_password" \
    --arg workspaceName "$workspace_name" \
    '{name: $name, email: $email, password: $password, workspaceName: $workspaceName}'
)"
status="$(
  curl --silent --show-error \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --data "$request_body" \
    "${base_url}/api/auth/setup"
)"
unset request_body

if [[ "$status" == "200" ]]; then
  echo "docmost-setup: owner '${owner_email}' and workspace '${workspace_name}' created"
  exit 0
fi
if [[ "$status" == "403" ]] &&
  jq -e '.message == "Workspace setup already completed."' "$response_file" >/dev/null 2>&1; then
  echo "docmost-setup: workspace setup already completed"
  exit 0
fi

echo "docmost-setup: setup API returned HTTP ${status}" >&2
jq -c . "$response_file" >&2 2>/dev/null || sed -n '1,20p' "$response_file" >&2
exit 1
