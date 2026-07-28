#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_lock="${project_dir}/jenkins/toolchain.lock"
plane_toolchain_lock="${project_dir}/plane/toolchain.lock"
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
[[ -s "$plane_toolchain_lock" ]] || fail "plane/toolchain.lock is missing"

set -a
# shellcheck disable=SC1090
source "$toolchain_lock"
# shellcheck disable=SC1090
source "$plane_toolchain_lock"
set +a

images=(
  "${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"
  "${JENKINS_INBOUND_AGENT_TAG}@${JENKINS_INBOUND_AGENT_DIGEST}"
  "${DOCKER_SOCKET_PROXY_TAG}@${DOCKER_SOCKET_PROXY_DIGEST}"
  "$JENKINS_CONTROLLER_IMAGE"
  "$NODEJS_AGENT_IMAGE"
  "$JAVA_AGENT_IMAGE"
  "$FLUTTER_AGENT_IMAGE"
  "${PLANE_FRONTEND_IMAGE_TAG}@${PLANE_FRONTEND_IMAGE_DIGEST}"
  "${PLANE_SPACE_IMAGE_TAG}@${PLANE_SPACE_IMAGE_DIGEST}"
  "${PLANE_ADMIN_IMAGE_TAG}@${PLANE_ADMIN_IMAGE_DIGEST}"
  "${PLANE_LIVE_IMAGE_TAG}@${PLANE_LIVE_IMAGE_DIGEST}"
  "${PLANE_BACKEND_IMAGE_TAG}@${PLANE_BACKEND_IMAGE_DIGEST}"
  "${PLANE_PROXY_IMAGE_TAG}@${PLANE_PROXY_IMAGE_DIGEST}"
  "${PLANE_POSTGRES_IMAGE_TAG}@${PLANE_POSTGRES_IMAGE_DIGEST}"
  "${PLANE_VALKEY_IMAGE_TAG}@${PLANE_VALKEY_IMAGE_DIGEST}"
  "${PLANE_RABBITMQ_IMAGE_TAG}@${PLANE_RABBITMQ_IMAGE_DIGEST}"
  "${PLANE_MINIO_IMAGE_TAG}@${PLANE_MINIO_IMAGE_DIGEST}"
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
