#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
minimum_gb="${MIN_DOCKER_FREE_GB:-10}"
[[ "$minimum_gb" =~ ^[0-9]+$ && "$minimum_gb" -gt 0 ]] || {
  echo "check-disk-space: MIN_DOCKER_FREE_GB must be a positive integer" >&2
  exit 1
}

# shellcheck disable=SC1091
source "${project_dir}/jenkins/toolchain.lock"
helper_image="${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"
available_kb="$(
  docker run --rm --entrypoint sh "$helper_image" \
    -c 'df -Pk / | awk "NR == 2 { print \$4 }"'
)"
required_kb=$((minimum_gb * 1024 * 1024))
[[ "$available_kb" =~ ^[0-9]+$ ]] || {
  echo "check-disk-space: cannot determine Docker storage free space" >&2
  exit 1
}
if (( available_kb < required_kb )); then
  available_gb=$((available_kb / 1024 / 1024))
  echo "check-disk-space: only ${available_gb} GiB free in Docker storage; ${minimum_gb} GiB required" >&2
  docker system df >&2
  exit 1
fi

available_gb=$((available_kb / 1024 / 1024))
echo "check-disk-space: ${available_gb} GiB available in Docker storage"
