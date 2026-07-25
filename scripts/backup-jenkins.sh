#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="${1:-${project_dir}/backups/jenkins-home-${timestamp}.tar.gz}"
volume_name="${JENKINS_HOME_VOLUME:-infrastructure-pipeline_jenkins_home}"

if [[ "$destination" != /* ]]; then
  destination="${project_dir}/${destination}"
fi
destination_dir="$(dirname "$destination")"
archive_name="$(basename "$destination")"
[[ "$archive_name" =~ ^[A-Za-z0-9_.-]+\.tar\.gz$ ]] || {
  echo "backup-jenkins: backup filename must end in .tar.gz" >&2
  exit 1
}
[[ ! -e "$destination" && ! -e "${destination}.sha256" ]] || {
  echo "backup-jenkins: destination already exists: $destination" >&2
  exit 1
}

docker volume inspect "$volume_name" >/dev/null 2>&1 || {
  echo "backup-jenkins: Jenkins volume does not exist: $volume_name" >&2
  exit 1
}

mkdir -p "$destination_dir"
destination_dir="$(cd "$destination_dir" && pwd)"

# shellcheck disable=SC1091
source "${project_dir}/jenkins/toolchain.lock"
helper_image="${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"
source_date_epoch="$(git -C "$project_dir" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH="$source_date_epoch"

cd "$project_dir"
jenkins_container="$(docker compose ps -q jenkins)"
was_running=false
if [[ -n "$jenkins_container" ]] &&
  [[ "$(docker inspect --format '{{.State.Running}}' "$jenkins_container")" == "true" ]]; then
  was_running=true
  docker compose stop jenkins
fi

restart_jenkins() {
  if $was_running; then
    docker compose start jenkins >/dev/null
  fi
}
trap restart_jenkins EXIT

docker run --rm --user 0 --entrypoint sh \
  --env BACKUP_NAME="$archive_name" \
  --env HOST_UID="$(id -u)" \
  --env HOST_GID="$(id -g)" \
  --volume "${volume_name}:/data:ro" \
  --volume "${destination_dir}:/backup" \
  "$helper_image" \
  -c 'tar --numeric-owner -czf "/backup/${BACKUP_NAME}" -C /data . &&
      chown "${HOST_UID}:${HOST_GID}" "/backup/${BACKUP_NAME}"'

if command -v sha256sum >/dev/null; then
  (
    cd "$destination_dir"
    sha256sum "$archive_name" >"${archive_name}.sha256"
  )
else
  (
    cd "$destination_dir"
    shasum -a 256 "$archive_name" >"${archive_name}.sha256"
  )
fi

restart_jenkins
was_running=false
trap - EXIT

echo "backup-jenkins: created $destination"
echo "backup-jenkins: verify with scripts/verify-backup.sh '$destination'"
