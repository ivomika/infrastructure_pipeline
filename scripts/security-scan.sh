#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_lock="${project_dir}/jenkins/toolchain.lock"
docmost_toolchain_lock="${project_dir}/docmost/toolchain.lock"
severity="${TRIVY_SEVERITY:-CRITICAL}"

fail() {
  echo "security-scan: $*" >&2
  exit 1
}

for command in docker trivy; do
  command -v "$command" >/dev/null ||
    fail "required command is unavailable: $command"
done
[[ -s "$toolchain_lock" ]] || fail "jenkins/toolchain.lock is missing"
[[ -s "$docmost_toolchain_lock" ]] || fail "docmost/toolchain.lock is missing"

set -a
# shellcheck disable=SC1090
source "$toolchain_lock"
# shellcheck disable=SC1090
source "$docmost_toolchain_lock"
set +a

images=(
  "${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"
  "${JENKINS_INBOUND_AGENT_TAG}@${JENKINS_INBOUND_AGENT_DIGEST}"
  "${DOCKER_SOCKET_PROXY_TAG}@${DOCKER_SOCKET_PROXY_DIGEST}"
  "$JENKINS_CONTROLLER_IMAGE"
  "$NODEJS_AGENT_IMAGE"
  "$JAVA_AGENT_IMAGE"
  "$FLUTTER_AGENT_IMAGE"
  "${DOCMOST_IMAGE_TAG}@${DOCMOST_IMAGE_DIGEST}"
  "${DOCMOST_POSTGRES_IMAGE_TAG}@${DOCMOST_POSTGRES_IMAGE_DIGEST}"
  "${DOCMOST_REDIS_IMAGE_TAG}@${DOCMOST_REDIS_IMAGE_DIGEST}"
)

for image in "${images[@]}"; do
  if [[ "$image" != *@sha256:* ]]; then
    docker image inspect "$image" >/dev/null 2>&1 ||
      fail "locally built image is unavailable: $image"
  fi
  echo "security-scan: scanning $image"
  trivy image \
    --exit-code 1 \
    --ignore-unfixed \
    --scanners vuln \
    --severity "$severity" \
    "$image"
done

echo "security-scan: all production images passed at severity $severity"
