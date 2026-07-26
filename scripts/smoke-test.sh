#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${project_dir}/.env"
work_dir="$(mktemp -d)"
cookie_jar="${work_dir}/cookies"
job_prefix="infrastructure-smoke-$$"
created_jobs=()

cleanup() {
  if [[ -n "${crumb_field:-}" && -n "${crumb:-}" ]]; then
    for job in "${created_jobs[@]}"; do
      curl --fail --silent --show-error \
        --user "${admin_id}:${admin_password}" \
        --cookie "$cookie_jar" \
        --header "${crumb_field}:${crumb}" \
        --request POST \
        "${jenkins_url}/job/${job}/doDelete" >/dev/null 2>&1 || true
    done
  fi
  rm -rf -- "$work_dir"
  unset admin_password
}
trap cleanup EXIT

fail() {
  echo "smoke-test: $*" >&2
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

for command in curl docker jq; do
  command -v "$command" >/dev/null ||
    fail "required command is unavailable: $command"
done
[[ -s "$env_file" ]] || fail ".env is missing or empty"

admin_id="$(resolved_env JENKINS_ADMIN_ID)"
admin_password="$(resolved_env JENKINS_ADMIN_PASSWORD)"
host_address="$(resolved_env JENKINS_HOST_ADDRESS)"
host_port="$(resolved_env JENKINS_HTTP_PORT)"
host_address="${host_address:-127.0.0.1}"
host_port="${host_port:-8080}"
case "$host_address" in
  0.0.0.0) api_host="127.0.0.1" ;;
  ::) api_host="[::1]" ;;
  *:*) api_host="[${host_address}]" ;;
  *) api_host="$host_address" ;;
esac
jenkins_url="http://${api_host}:${host_port}"

[[ -n "$admin_id" && -n "$admin_password" ]] ||
  fail "Jenkins admin credentials are missing"

cd "$project_dir"
source_date_epoch="$(git log -1 --format=%ct)"
export SOURCE_DATE_EPOCH="$source_date_epoch"

container_id="$(docker compose ps -q jenkins)"
[[ -n "$container_id" ]] || fail "Jenkins container is not running"
health_status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")"
[[ "$health_status" == "healthy" ]] ||
  fail "Jenkins container is not healthy (status: $health_status)"

curl --fail --silent --show-error \
  --user "${admin_id}:${admin_password}" \
  "${jenkins_url}/api/json" \
  --output "${work_dir}/api.json"
jq -e '.useSecurity == true and .numExecutors == 0' "${work_dir}/api.json" >/dev/null ||
  fail "Jenkins API does not expose the locked-down controller configuration"

crumb_json="$(
  curl --fail --silent --show-error \
    --user "${admin_id}:${admin_password}" \
    --cookie-jar "$cookie_jar" \
    "${jenkins_url}/crumbIssuer/api/json"
)"
crumb_field="$(jq -r '.crumbRequestField' <<<"$crumb_json")"
crumb="$(jq -r '.crumb' <<<"$crumb_json")"
[[ -n "$crumb_field" && "$crumb_field" != "null" && -n "$crumb" && "$crumb" != "null" ]] ||
  fail "Jenkins did not issue a CSRF crumb"

curl --fail --silent --show-error \
  --user "${admin_id}:${admin_password}" \
  --cookie "$cookie_jar" \
  --header "${crumb_field}:${crumb}" \
  --request POST \
  "${jenkins_url}/configuration-as-code/export" \
  --output "${work_dir}/jcasc.yaml"
grep -Eq 'allowsSignup:[[:space:]]*false' "${work_dir}/jcasc.yaml" ||
  fail "JCasC export does not disable signup"
grep -Eq 'globalMatrix:' "${work_dir}/jcasc.yaml" ||
  fail "JCasC export does not contain the authorization matrix"
grep -Eq '^[[:space:]]*-[[:space:]]+docker:' "${work_dir}/jcasc.yaml" ||
  fail "JCasC export does not contain the Docker cloud"

docker compose exec -T jenkins \
  curl --fail --silent --show-error \
  http://docker-socket-proxy:2375/_ping |
  grep -Fxq 'OK' ||
  fail "Jenkins cannot reach the Docker socket proxy"

run_agent_job() {
  local label="$1"
  local job="${job_prefix}-${label}"
  local job_xml="${work_dir}/${job}.xml"
  local response_headers="${work_dir}/${job}.headers"
  local queue_location queue_id queue_json build_number build_json
  local deadline result built_on

  created_jobs+=("$job")
  {
    echo '<?xml version="1.1" encoding="UTF-8"?>'
    echo '<project>'
    echo '  <actions/>'
    echo '  <description>Ephemeral agent smoke test</description>'
    echo '  <keepDependencies>false</keepDependencies>'
    echo '  <properties/>'
    echo '  <scm class="hudson.scm.NullSCM"/>'
    echo '  <canRoam>false</canRoam>'
    echo "  <assignedNode>${label}</assignedNode>"
    echo '  <disabled>false</disabled>'
    echo '  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>'
    echo '  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>'
    echo '  <triggers/>'
    echo '  <concurrentBuild>false</concurrentBuild>'
    echo '  <builders>'
    echo '    <hudson.tasks.Shell>'
    echo '      <command>test -n "$NODE_NAME"</command>'
    echo '      <configuredLocalRules/>'
    echo '    </hudson.tasks.Shell>'
    echo '  </builders>'
    echo '  <publishers/>'
    echo '  <buildWrappers/>'
    echo '</project>'
  } >"$job_xml"

  curl --fail --silent --show-error \
    --user "${admin_id}:${admin_password}" \
    --cookie "$cookie_jar" \
    --header "${crumb_field}:${crumb}" \
    --header 'Content-Type: application/xml' \
    --request POST \
    --data-binary "@${job_xml}" \
    "${jenkins_url}/createItem?name=${job}" \
    --output /dev/null

  curl --fail --silent --show-error \
    --user "${admin_id}:${admin_password}" \
    --cookie "$cookie_jar" \
    --header "${crumb_field}:${crumb}" \
    --request POST \
    --dump-header "$response_headers" \
    --output /dev/null \
    "${jenkins_url}/job/${job}/build?delay=0sec"
  queue_location="$(
    awk -F': ' 'tolower($1) == "location" { sub(/\r$/, "", $2); print $2 }' \
      "$response_headers"
  )"
  queue_id="$(sed -E 's#^.*/queue/item/([0-9]+)/?.*$#\1#' <<<"$queue_location")"
  [[ "$queue_id" =~ ^[0-9]+$ ]] || fail "cannot determine queue item for $label"

  deadline=$((SECONDS + ${SMOKE_AGENT_TIMEOUT_SECONDS:-600}))
  build_number=""
  while [[ -z "$build_number" ]]; do
    queue_json="$(
      curl --fail --silent --show-error \
        --user "${admin_id}:${admin_password}" \
        "${jenkins_url}/queue/item/${queue_id}/api/json"
    )"
    [[ "$(jq -r '.cancelled // false' <<<"$queue_json")" != "true" ]] ||
      fail "agent job was cancelled for $label"
    build_number="$(jq -r '.executable.number // empty' <<<"$queue_json")"
    if (( SECONDS >= deadline )); then
      why="$(jq -r '.why // "unknown reason"' <<<"$queue_json")"
      fail "agent was not provisioned for $label: $why"
    fi
    [[ -n "$build_number" ]] || sleep 5
  done

  result=""
  while [[ -z "$result" || "$result" == "null" ]]; do
    build_json="$(
      curl --fail --silent --show-error \
        --user "${admin_id}:${admin_password}" \
        "${jenkins_url}/job/${job}/${build_number}/api/json?tree=result,builtOn"
    )"
    result="$(jq -r '.result' <<<"$build_json")"
    if (( SECONDS >= deadline )); then
      fail "agent job did not finish for $label"
    fi
    [[ "$result" != "null" ]] || sleep 5
  done

  built_on="$(jq -r '.builtOn // empty' <<<"$build_json")"
  [[ "$result" == "SUCCESS" ]] || fail "agent job failed for $label: $result"
  [[ -n "$built_on" ]] || fail "agent job for $label did not report an ephemeral node"
  echo "smoke-test: $label agent succeeded on $built_on"
}

run_agent_job nodejs
run_agent_job java
run_agent_job flutter

echo "smoke-test: controller, JCasC, API, Docker proxy, and all agents passed"
