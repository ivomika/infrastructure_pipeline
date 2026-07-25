#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-}"
target_volume="${2:-${JENKINS_HOME_VOLUME:-infrastructure-pipeline_jenkins_home}}"
[[ -n "$archive" ]] || {
  echo "Usage: $0 <jenkins-home.tar.gz> [empty-target-volume]" >&2
  exit 2
}
[[ "$target_volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]] || {
  echo "restore-jenkins: invalid target volume name" >&2
  exit 1
}
if [[ "$archive" != /* ]]; then
  archive="${project_dir}/${archive}"
fi
[[ -s "$archive" ]] || {
  echo "restore-jenkins: archive is missing or empty: $archive" >&2
  exit 1
}

"${project_dir}/scripts/verify-backup.sh" "$archive"

source_date_epoch="$(git -C "$project_dir" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH="$source_date_epoch"
cd "$project_dir"
jenkins_container="$(docker compose ps -q jenkins)"
if [[ -n "$jenkins_container" ]] &&
  [[ "$(docker inspect --format '{{.State.Running}}' "$jenkins_container")" == "true" ]]; then
  echo "restore-jenkins: stop Jenkins before restoring a backup" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${project_dir}/jenkins/toolchain.lock"
helper_image="${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"
created_volume=false
if docker volume inspect "$target_volume" >/dev/null 2>&1; then
  existing_entries="$(
    docker run --rm --entrypoint sh \
      --volume "${target_volume}:/target:ro" \
      "$helper_image" \
      -c 'find /target -mindepth 1 -print -quit'
  )"
  [[ -z "$existing_entries" ]] || {
    echo "restore-jenkins: target volume is not empty; refusing to overwrite it" >&2
    exit 1
  }
else
  docker volume create \
    --label "com.ivomika.restored-from=$(basename "$archive")" \
    "$target_volume" >/dev/null
  created_volume=true
fi

archive_dir="$(cd "$(dirname "$archive")" && pwd)"
archive_name="$(basename "$archive")"
if ! docker run --rm --user 0 --entrypoint sh \
  --env ARCHIVE_NAME="$archive_name" \
  --volume "${archive_dir}:/backup:ro" \
  --volume "${target_volume}:/target" \
  "$helper_image" \
  -c 'tar -xzf "/backup/${ARCHIVE_NAME}" -C /target'; then
  if $created_volume; then
    docker volume rm "$target_volume" >/dev/null 2>&1 || true
  fi
  echo "restore-jenkins: restore failed" >&2
  exit 1
fi

echo "restore-jenkins: restored $archive into $target_volume"
echo "restore-jenkins: set JENKINS_HOME_VOLUME=$target_volume and run make bootstrap"
