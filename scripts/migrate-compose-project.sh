#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
old_project="infrastructure-pipelinse"
new_project="infrastructure-pipeline"
old_volume="${old_project}_jenkins_home"
new_volume="${new_project}_jenkins_home"
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
  echo "migrate-compose-project: $*" >&2
  exit 1
}

docker info >/dev/null 2>&1 || fail "Docker daemon is unavailable"

if ! docker volume inspect "$old_volume" >/dev/null 2>&1; then
  echo "migrate-compose-project: no legacy Jenkins volume found"
  exit 0
fi

if docker volume inspect "$new_volume" >/dev/null 2>&1; then
  migrated_from="$(
    docker volume inspect \
      --format '{{index .Labels "com.ivomika.migrated-from"}}' \
      "$new_volume"
  )"
  [[ "$migrated_from" == "$old_volume" ]] ||
    fail "$new_volume already exists and was not created by this migration"
  echo "migrate-compose-project: Jenkins volume was already migrated; legacy volume retained"
  exit 0
fi

if $check_only; then
  echo "migrate-compose-project: legacy Jenkins volume requires migration"
  exit 0
fi

source_date_epoch="$(git -C "$project_dir" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH="$source_date_epoch"

running_containers=()
while IFS= read -r container; do
  [[ -n "$container" ]] && running_containers+=("$container")
done < <(
  docker ps -q --filter "label=com.docker.compose.project=${old_project}"
)

if [[ "${#running_containers[@]}" -gt 0 ]]; then
  echo "migrate-compose-project: stopping the legacy Compose stack"
  (
    cd "$project_dir"
    docker compose --project-name "$old_project" down --remove-orphans
  )
fi

# shellcheck disable=SC1091
source "${project_dir}/jenkins/toolchain.lock"
helper_image="${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"

docker volume create \
  --label "com.ivomika.migrated-from=${old_volume}" \
  "$new_volume" >/dev/null

if ! docker run --rm --user 0 --entrypoint sh \
  --volume "${old_volume}:/source:ro" \
  --volume "${new_volume}:/target" \
  "$helper_image" \
  -c 'cp -a /source/. /target/'; then
  docker volume rm "$new_volume" >/dev/null 2>&1 || true
  fail "volume copy failed; the unchanged legacy volume is still available"
fi

old_count="$(
  docker run --rm --user 0 --entrypoint sh \
    --volume "${old_volume}:/data:ro" \
    "$helper_image" \
    -c 'find /data -mindepth 1 | wc -l'
)"
new_count="$(
  docker run --rm --user 0 --entrypoint sh \
    --volume "${new_volume}:/data:ro" \
    "$helper_image" \
    -c 'find /data -mindepth 1 | wc -l'
)"
[[ "$old_count" == "$new_count" ]] || {
  docker volume rm "$new_volume" >/dev/null 2>&1 || true
  fail "file-count verification failed; the unchanged legacy volume is still available"
}

echo "migrate-compose-project: copied $old_count entries to $new_volume"
echo "migrate-compose-project: retained $old_volume for rollback"
