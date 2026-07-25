#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-}"
[[ -n "$archive" ]] || {
  echo "Usage: $0 <jenkins-home.tar.gz>" >&2
  exit 2
}
if [[ "$archive" != /* ]]; then
  archive="${project_dir}/${archive}"
fi
[[ -s "$archive" ]] || {
  echo "verify-backup: archive is missing or empty: $archive" >&2
  exit 1
}

archive_dir="$(cd "$(dirname "$archive")" && pwd)"
archive_name="$(basename "$archive")"
checksum_file="${archive}.sha256"
if [[ -f "$checksum_file" ]]; then
  if command -v sha256sum >/dev/null; then
    (cd "$archive_dir" && sha256sum --check "$(basename "$checksum_file")")
  else
    expected="$(awk '{ print $1; exit }' "$checksum_file")"
    actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    [[ "$actual" == "$expected" ]] || {
      echo "verify-backup: SHA-256 mismatch" >&2
      exit 1
    }
  fi
fi

# shellcheck disable=SC1091
source "${project_dir}/jenkins/toolchain.lock"
helper_image="${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}"
test_volume="jenkins-restore-check-$$"
test_volume="$(tr -cd 'a-zA-Z0-9_.-' <<<"$test_volume")"

cleanup() {
  docker volume rm "$test_volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create \
  --label com.ivomika.purpose=restore-check \
  "$test_volume" >/dev/null
docker run --rm --user 0 --entrypoint sh \
  --env ARCHIVE_NAME="$archive_name" \
  --volume "${archive_dir}:/backup:ro" \
  --volume "${test_volume}:/restore" \
  "$helper_image" \
  -c 'tar -xzf "/backup/${ARCHIVE_NAME}" -C /restore'

archive_files="$(
  docker run --rm --entrypoint sh \
    --env ARCHIVE_NAME="$archive_name" \
    --volume "${archive_dir}:/backup:ro" \
    "$helper_image" \
    -c 'tar -tzf "/backup/${ARCHIVE_NAME}" | awk "!/\\/$/ { count++ } END { print count + 0 }"'
)"
restored_files="$(
  docker run --rm --entrypoint sh \
    --volume "${test_volume}:/restore:ro" \
    "$helper_image" \
    -c 'find /restore -mindepth 1 ! -type d | wc -l'
)"
[[ "$archive_files" -gt 0 && "$archive_files" == "$restored_files" ]] || {
  echo "verify-backup: restored file count differs (archive=$archive_files, restored=$restored_files)" >&2
  exit 1
}

echo "verify-backup: restored $restored_files files into an isolated test volume"
